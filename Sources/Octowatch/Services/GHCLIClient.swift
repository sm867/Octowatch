import Foundation

enum GHError: LocalizedError {
    case notInstalled
    case notAuthenticated
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "GitHub CLI (gh) not found. Install it with `brew install gh`."
        case .notAuthenticated:
            return "gh is not signed in. Run `gh auth login` in Terminal."
        case .commandFailed(let message):
            return message
        }
    }
}

/// Talks to GitHub exclusively through the `gh` CLI, so the app never handles tokens.
actor GHCLIClient {
    private static let searchPaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    private var ghPath: String? = GHCLIClient.searchPaths.first {
        FileManager.default.isExecutableFile(atPath: $0)
    }

    // MARK: - API

    func fetchAuthenticatedUser() async throws -> GitHubUser {
        let data = try await run(["api", "-H", "Accept: application/vnd.github+json", "user"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubUser.self, from: data)
    }

    /// Resolves local clones to GitHub repos in batched GraphQL calls; inaccessible repos are skipped.
    func fetchRepositories(_ local: [LocalRepo]) async throws -> [Repository] {
        let selection = "databaseId name nameWithOwner isPrivate url owner { login } defaultBranchRef { name }"
        var result: [Repository] = []
        for (_, repo) in try await queryBatches(local, selection: selection) {
            guard let id = repo["databaseId"] as? Int,
                let name = repo["name"] as? String,
                let fullName = repo["nameWithOwner"] as? String,
                let owner = (repo["owner"] as? [String: Any])?["login"] as? String,
                let url = repo["url"] as? String
            else { continue }
            result.append(
                Repository(
                    id: id, name: name, fullName: fullName,
                    owner: RepositoryOwner(login: owner),
                    isPrivate: repo["isPrivate"] as? Bool ?? false,
                    htmlUrl: url,
                    defaultBranch: (repo["defaultBranchRef"] as? [String: Any])?["name"] as? String))
        }
        return result
    }

    struct RepoInfo: Sendable {
        let openPRs: Int?
        /// Rollup of all checks on the default branch's head commit; nil when it has none.
        let checks: AggregateStatus?
        let pushedAt: Date?
    }

    /// Open PR count and head-commit check state, keyed by "owner/name".
    func fetchRepoInfo(_ repos: [LocalRepo]) async throws -> [String: RepoInfo] {
        let selection =
            "pushedAt pullRequests(states: OPEN) { totalCount } "
            + "defaultBranchRef { target { ... on Commit { statusCheckRollup { state } } } }"

        var result: [String: RepoInfo] = [:]
        for (key, repo) in try await queryBatches(repos, selection: selection) {
            let prs = (repo["pullRequests"] as? [String: Any])?["totalCount"] as? Int
            let rollup = ((repo["defaultBranchRef"] as? [String: Any])?["target"] as? [String: Any])?[
                "statusCheckRollup"] as? [String: Any]

            let checks: AggregateStatus?
            switch rollup?["state"] as? String {
            case "SUCCESS": checks = .allGreen
            case "FAILURE", "ERROR": checks = .failed
            case "PENDING", "EXPECTED": checks = .inProgress
            default: checks = nil
            }
            let pushedAt = (repo["pushedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            result[key] = RepoInfo(openPRs: prs, checks: checks, pushedAt: pushedAt)
        }
        return result
    }

    // MARK: - GraphQL

    private static let batchSize = 50

    /// Runs one aliased `repository(...)` query per batch of repos; returns objects keyed by "owner/name".
    private func queryBatches(_ repos: [LocalRepo], selection: String) async throws -> [(String, [String: Any])] {
        // Names come from local git config, so only allow GitHub's own charset in the query.
        let safe = repos.filter { Self.isSafe($0.owner) && Self.isSafe($0.name) }
        var out: [(String, [String: Any])] = []

        for start in stride(from: 0, to: safe.count, by: Self.batchSize) {
            let batch = Array(safe[start..<min(start + Self.batchSize, safe.count)])
            let fields = batch.enumerated().map { index, item in
                "r\(index): repository(owner: \"\(item.owner)\", name: \"\(item.name)\") { \(selection) }"
            }.joined(separator: " ")

            // gh exits non-zero if any single repo is unresolvable, but still prints the rest.
            let data = try await run(["api", "graphql", "-f", "query={ \(fields) }"], tolerateErrors: true)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let dataObject = root["data"] as? [String: Any]
            else { continue }

            for (index, item) in batch.enumerated() {
                if let repo = dataObject["r\(index)"] as? [String: Any] {
                    out.append(("\(item.owner)/\(item.name)", repo))
                }
            }
        }
        return out
    }

    private static func isSafe(_ name: String) -> Bool {
        !name.isEmpty
            && name.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == "."
            }
    }

    // MARK: - Process

    private func run(_ arguments: [String], tolerateErrors: Bool = false) async throws -> Data {
        guard let ghPath else { throw GHError.notInstalled }

        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = arguments

            // GUI apps start with a minimal PATH; gh may need git and friends.
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["GH_PROMPT_DISABLED"] = "1"
            env["NO_COLOR"] = "1"
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice

            try process.run()

            // A hung gh (network drop, sleep/wake) would otherwise stall polling forever.
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: watchdog)
            defer { watchdog.cancel() }

            // Drain stderr concurrently so a full pipe can't block the child.
            let errTask = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = await errTask.value
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                if process.terminationReason == .uncaughtSignal {
                    throw GHError.commandFailed("gh timed out")
                }
                // gh exits with 4 when authentication is required.
                if process.terminationStatus == 4 { throw GHError.notAuthenticated }
                let message = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if message.localizedCaseInsensitiveContains("gh auth login") {
                    throw GHError.notAuthenticated
                }
                if tolerateErrors, !output.isEmpty { return output }
                throw GHError.commandFailed(message.isEmpty ? "gh failed (exit \(process.terminationStatus))" : message)
            }
            return output
        }.value
    }
}
