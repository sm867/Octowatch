import SwiftUI

/// Shown when the GitHub CLI is missing or not signed in.
struct GHSetupView: View {
    @Bindable var viewModel: WorkflowViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Octowatch")
                .font(.title2.bold())

            Text("Octowatch requires the GitHub CLI (gh).\nInstall it with `brew install gh`, then run:\n`gh auth login`.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                viewModel.refresh()
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Retry")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
