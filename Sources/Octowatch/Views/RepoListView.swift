import SwiftUI

struct RepoListView: View {
    let repos: [RepoSummary]
    let pulsePhase: Bool
    let isLoading: Bool

    var body: some View {
        if repos.isEmpty && !isLoading {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tray")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No repositories selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(repos) { repo in
                        RepoRow(repo: repo, pulsePhase: pulsePhase)
                        if repo.id != repos.last?.id {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }
}

private struct RepoRow: View {
    let repo: RepoSummary
    let pulsePhase: Bool

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Circle()
                    .fill(repo.status.bubbleColor)
                    .frame(width: 10, height: 10)
                    .opacity(repo.status == .inProgress ? (pulsePhase ? 1.0 : 0.4) : 1.0)

                Text(repo.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer()

                if let prs = repo.openPRs {
                    Label("\(prs)", systemImage: "arrow.triangle.pull")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(prs > 0 ? .primary : .tertiary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open() {
        if let url = repo.url {
            NSWorkspace.shared.open(url)
        }
    }
}
