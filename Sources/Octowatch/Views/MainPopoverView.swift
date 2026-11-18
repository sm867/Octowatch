import SwiftUI

struct MainPopoverView: View {
    @Bindable var viewModel: WorkflowViewModel

    var body: some View {
        Group {
            if !viewModel.isAuthenticated {
                GHSetupView(viewModel: viewModel)
            } else if viewModel.showSettings {
                SettingsView(viewModel: viewModel) {
                    viewModel.showSettings = false
                    viewModel.refresh()
                }
            } else {
                authenticatedContent
            }
        }
        .background(.ultraThinMaterial)
    }

    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            HeaderView(
                onRefresh: { viewModel.refresh() },
                onSettings: { viewModel.showSettings = true },
                isLoading: viewModel.isLoading
            )

            Divider()

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            if viewModel.reposFolder.isEmpty {
                chooseFolderPrompt
            } else {
                RepoListView(
                    repos: viewModel.repoSummaries,
                    pulsePhase: viewModel.pulsePhase,
                    isLoading: viewModel.isLoading
                )
            }

            Divider()

            FooterView(username: viewModel.username)
        }
    }

    private var chooseFolderPrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("Choose the folder with your git clones")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Choose Folder…") {
                FolderPicker.choose { viewModel.setReposFolder($0) }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.1))
    }
}
