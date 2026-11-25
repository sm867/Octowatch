import Foundation
import SwiftUI

@Observable
@MainActor
final class WorkflowViewModel {
    // MARK: - State

    var isAuthenticated = false
    var username = ""
    var repos: [Repository] = []
    var isLoading = false
    var errorMessage: String?
    var showSettings = false
    var aggregateStatus: AggregateStatus = .idle
    var pulsePhase: Bool = false
    var reposFolder: String = ""
    var repoSummaries: [RepoSummary] = []
    private var repoInfo: [String: GHCLIClient.RepoInfo] = [:]

    // MARK: - Settings (persisted)

    var pollingInterval: TimeInterval {
        get { UserDefaults.standard.double(forKey: "pollingIntervalSeconds").nonZero ?? 300 }
        set {
            UserDefaults.standard.set(newValue, forKey: "pollingIntervalSeconds")
            restartPolling()
        }
    }

    var notificationSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notificationSoundEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notificationSoundEnabled") }
    }

    var selectedRepoFullNames: Set<String> {
        get {
            guard let data = UserDefaults.standard.string(forKey: "selectedRepos"),
                let names = try? JSONDecoder().decode(Set<String>.self, from: Data(data.utf8))
            else { return [] }
            return names
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
                let str = String(data: data, encoding: .utf8)
            {
                UserDefaults.standard.set(str, forKey: "selectedRepos")
            }
        }
    }

    // MARK: - Private

    private let client = GHCLIClient()
    private var pollingTask: Task<Void, Never>?
    private var pulseTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var retryLoad = false
    private var previousStatuses: [String: AggregateStatus] = [:]

    // MARK: - Init

    init() {
        reposFolder = UserDefaults.standard.string(forKey: "reposFolder") ?? ""
        Task { await loadInitialData() }
        observeWake()
    }

    /// Refresh right after the Mac wakes instead of waiting out the remaining poll interval.
    private func observeWake() {
        wakeTask = Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didWakeNotification)
            {
                try? await Task.sleep(for: .seconds(3))  // let the network come back
                await self?.tick()
            }
        }
    }

    /// One scheduled refresh; retries the full load while not signed in (e.g. network was down at launch).
    private func tick() async {
        if isAuthenticated {
            await fetchStatuses()
        } else if retryLoad {
            await loadInitialData()
        }
    }

    // MARK: - Repos folder

    func setReposFolder(_ path: String) {
        reposFolder = path
        UserDefaults.standard.set(path, forKey: "reposFolder")
        selectedRepoFullNames = []
        Task { await loadInitialData() }
    }

    // MARK: - Data Loading

    /// Checks that `gh` is usable, then discovers GitHub clones in the chosen folder.
    func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        do {
            let user = try await client.fetchAuthenticatedUser()
            username = user.login
            isAuthenticated = true
            NotificationService.requestPermission()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            // Transient failures (network, timeout) must not kill auto-refresh.
            if case GHError.commandFailed = error {
                retryLoad = true
                if pollingTask == nil { startPolling() }
                return
            }
            retryLoad = false
            isAuthenticated = false
            stopPolling()
            stopPulse()
            return
        }

        retryLoad = false
        do {
            repos = try await discoverRepos()
        } catch {
            // Keep polling; fetchStatuses re-runs discovery while the repo list is empty.
            errorMessage = error.localizedDescription
        }

        // Select all repos by default if none selected
        if selectedRepoFullNames.isEmpty {
            selectedRepoFullNames = Set(repos.map(\.fullName))
        }

        await fetchStatuses()
        if pollingTask == nil { startPolling() }
        startPulse()
        isLoading = false
    }

    private func discoverRepos() async throws -> [Repository] {
        guard !reposFolder.isEmpty else { return [] }
        let root = URL(fileURLWithPath: reposFolder)
        let local = await Task.detached { LocalRepoScanner.scan(root: root) }.value
        let repos = local.isEmpty ? [] : try await client.fetchRepositories(local)
        return repos.sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
    }

    /// Refreshes only the repos selected in Settings; hidden ones are never queried.
    func fetchStatuses() async {
        guard isAuthenticated else { return }
        errorMessage = nil

        if repos.isEmpty, !reposFolder.isEmpty {
            do {
                repos = try await discoverRepos()
                if selectedRepoFullNames.isEmpty { selectedRepoFullNames = Set(repos.map(\.fullName)) }
            } catch {
                handleError(error)
                return
            }
        }

        let activeRepos = repos.filter { selectedRepoFullNames.contains($0.fullName) }
        guard !activeRepos.isEmpty else {
            repoSummaries = []
            aggregateStatus = .idle
            return
        }

        do {
            repoInfo = try await client.fetchRepoInfo(
                activeRepos.map { LocalRepo(owner: $0.owner.login, name: $0.name) })
            let summaries = computeRepoSummaries(activeRepos: activeRepos)
            notifyChanges(summaries)
            repoSummaries = summaries
            aggregateStatus = computeAggregateStatus(summaries)
        } catch {
            handleError(error)
        }
    }

    func refresh() {
        Task {
            if isAuthenticated {
                await fetchStatuses()
                // Self-heal: make sure the poll loop is alive after a manual refresh.
                if isAuthenticated, pollingTask == nil { startPolling() }
            } else {
                await loadInitialData()
            }
        }
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollingInterval))
                guard !Task.isCancelled else { break }
                await tick()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func restartPolling() {
        if isAuthenticated {
            startPolling()
        }
    }

    // MARK: - Notifications

    private func notifyChanges(_ summaries: [RepoSummary]) {
        var current: [String: AggregateStatus] = [:]
        for repo in summaries {
            current[repo.fullName] = repo.status
            guard let previous = previousStatuses[repo.fullName], previous != repo.status else { continue }

            if repo.status == .failed {
                NotificationService.sendStatusChanged(
                    repo: repo, passed: false, playSound: notificationSoundEnabled)
            } else if repo.status == .allGreen, previous == .inProgress || previous == .failed {
                NotificationService.sendStatusChanged(
                    repo: repo, passed: true, playSound: notificationSoundEnabled)
            }
        }
        previousStatuses = current
    }

    // MARK: - Helpers

    private func computeRepoSummaries(activeRepos: [Repository]) -> [RepoSummary] {
        activeRepos.map { repo in
            let info = repoInfo[repo.fullName]
            return RepoSummary(
                fullName: repo.fullName,
                name: repo.name,
                status: info?.checks ?? .idle,
                openPRs: info?.openPRs,
                url: URL(string: repo.htmlUrl),
                lastActivity: info?.pushedAt)
        }
        .sorted {
            // Tier 0: failed/running; tier 1: open PRs (most first); tier 2: most recent activity.
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            switch $0.tier {
            case 0:
                if $0.status.sortRank != $1.status.sortRank { return $0.status.sortRank < $1.status.sortRank }
            case 1:
                if $0.openPRs != $1.openPRs { return ($0.openPRs ?? 0) > ($1.openPRs ?? 0) }
            default:
                if $0.lastActivity != $1.lastActivity {
                    return ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
                }
            }
            return $0.name.lowercased() < $1.name.lowercased()
        }
    }

    private func startPulse() {
        stopPulse()
        pulseTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { break }
                pulsePhase.toggle()
            }
        }
    }

    private func stopPulse() {
        pulseTask?.cancel()
        pulseTask = nil
    }

    /// Worst status wins: any failure, then anything running, then healthy.
    private func computeAggregateStatus(_ summaries: [RepoSummary]) -> AggregateStatus {
        if summaries.contains(where: { $0.status == .failed }) { return .failed }
        if summaries.contains(where: { $0.status == .inProgress }) { return .inProgress }
        if summaries.contains(where: { $0.status == .allGreen }) { return .allGreen }
        return .idle
    }

    private func handleError(_ error: Error) {
        if let ghError = error as? GHError, case .notAuthenticated = ghError {
            isAuthenticated = false
            stopPolling()
            stopPulse()
        }
        errorMessage = error.localizedDescription
    }
}

// MARK: - Sorting

extension RepoSummary {
    var tier: Int {
        switch status {
        case .failed, .mixed, .inProgress: return 0
        default: return (openPRs ?? 0) > 0 ? 1 : 2
        }
    }
}

extension AggregateStatus {
    /// Failing repos first, then running, unknown, and healthy last.
    var sortRank: Int {
        switch self {
        case .failed, .mixed: return 0
        case .inProgress: return 1
        case .idle: return 2
        case .allGreen: return 3
        }
    }
}

// MARK: - Double Extension

extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
