import SwiftUI

struct MenuBarLabel: View {
    let status: AggregateStatus
    let pulsePhase: Bool

    var body: some View {
        Image(nsImage: renderIcon())
    }

    @MainActor
    private func renderIcon() -> NSImage {
        let content = Image(systemName: status.iconName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(status.bubbleColor)
            .opacity(status == .inProgress ? (pulsePhase ? 1.0 : 0.4) : 1.0)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2.0

        guard let cgImage = renderer.cgImage else {
            return NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: nil)
                ?? NSImage()
        }

        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: CGFloat(cgImage.width) / 2.0,
                height: CGFloat(cgImage.height) / 2.0
            )
        )
        nsImage.isTemplate = false
        return nsImage
    }
}

extension AggregateStatus {
    var bubbleColor: Color {
        switch self {
        case .idle: return .gray
        case .allGreen: return .green
        case .inProgress: return .orange
        case .failed: return .red
        case .mixed: return .red
        }
    }
}
