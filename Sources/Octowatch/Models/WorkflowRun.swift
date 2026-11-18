import Foundation

// MARK: - GitHub User

struct GitHubUser: Codable, Sendable {
    let login: String
    let id: Int
    let avatarUrl: String
}

// MARK: - Repository

struct Repository: Sendable, Identifiable {
    let id: Int
    let name: String
    let fullName: String
    let owner: RepositoryOwner
    let isPrivate: Bool
    let htmlUrl: String
    let defaultBranch: String?

}

struct RepositoryOwner: Sendable {
    let login: String
}

// MARK: - Aggregate Status

enum AggregateStatus: Sendable {
    case idle
    case allGreen
    case inProgress
    case failed
    case mixed

    var iconName: String {
        switch self {
        case .idle: return "circle.dashed"
        case .allGreen: return "checkmark.circle.fill"
        case .inProgress: return "clock.arrow.circlepath"
        case .failed: return "xmark.circle.fill"
        case .mixed: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Repo Summary

struct RepoSummary: Identifiable, Sendable {
    let fullName: String
    let name: String
    let status: AggregateStatus
    let openPRs: Int?
    let url: URL?
    var lastActivity: Date? = nil
    var id: String { fullName }
}
