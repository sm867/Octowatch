import SwiftUI

@main
struct OctowatchApp: App {
    @State private var viewModel = WorkflowViewModel()

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView(viewModel: viewModel)
                .frame(width: 400, height: 500)
        } label: {
            MenuBarLabel(status: viewModel.aggregateStatus, pulsePhase: viewModel.pulsePhase)
        }
        .menuBarExtraStyle(.window)
    }
}
