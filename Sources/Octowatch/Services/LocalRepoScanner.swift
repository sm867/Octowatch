import Foundation

struct LocalRepo: Sendable, Hashable {
    let owner: String
    let name: String
}

enum LocalRepoScanner {
    private static let maxDepth = 2
    private static let skipped: Set<String> = ["node_modules", "build", "dist", "Pods", "vendor"]

    /// Finds git clones under `root` (the folder itself, its children and grandchildren)
    /// whose `origin` points to github.com.
    static func scan(root: URL) -> [LocalRepo] {
        var found: Set<LocalRepo> = []
        walk(root, depth: 0, into: &found)
        return found.sorted { ($0.owner, $0.name) < ($1.owner, $1.name) }
    }

    private static func walk(_ dir: URL, depth: Int, into found: inout Set<LocalRepo>) {
        let fm = FileManager.default
        let gitDir = dir.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: gitDir.path, isDirectory: &isDir) {
            if isDir.boolValue, let repo = originRepo(configURL: gitDir.appendingPathComponent("config")) {
                found.insert(repo)
            }
            return
        }

        guard depth < maxDepth,
            let children = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return }

        for child in children where !skipped.contains(child.lastPathComponent) {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                walk(child, depth: depth + 1, into: &found)
            }
        }
    }

    private static func originRepo(configURL: URL) -> LocalRepo? {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }

        var inOrigin = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line == "[remote \"origin\"]"
            } else if inOrigin, line.hasPrefix("url") {
                guard let eq = line.firstIndex(of: "=") else { continue }
                let url = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                return parse(remoteURL: url)
            }
        }
        return nil
    }

    // Handles git@github.com:o/r(.git), ssh://git@github.com/o/r and https://github.com/o/r(.git)
    static func parse(remoteURL: String) -> LocalRepo? {
        guard let hostRange = remoteURL.range(of: "github.com") else { return nil }
        var rest = remoteURL[hostRange.upperBound...]
        guard let first = rest.first, first == ":" || first == "/" else { return nil }
        rest = rest.dropFirst()

        var parts = rest.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        parts = Array(parts.prefix(2))
        if parts[1].hasSuffix(".git") { parts[1].removeLast(4) }
        guard !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return LocalRepo(owner: parts[0], name: parts[1])
    }
}
