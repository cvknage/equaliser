import SwiftUI

/// Displays the current audio routing status.
/// Uses RoutingViewModel for all presentation logic (text, colors, icons).
struct RoutingStatusView: View {
    let viewModel: RoutingViewModel

    init(viewModel: RoutingViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            statusText
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(viewModel.statusBackgroundColor)
        .cornerRadius(6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if viewModel.showsProgressIndicator {
            ProgressView()
                .controlSize(.small)
        } else if let iconName = viewModel.statusIconName {
            Image(systemName: iconName)
                .foregroundStyle(viewModel.statusIconColor)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        let text = Text(viewModel.detailedStatusText)
            .foregroundStyle(viewModel.detailedStatusColor)
            .fontWeight(viewModel.statusTextIsMedium ? .medium : .regular)

        if let lineLimit = viewModel.statusTextLineLimit {
            text.lineLimit(lineLimit)
        } else {
            text
        }
    }
}

#Preview("Idle") {
    RoutingStatusView(viewModel: RoutingViewModel(store: EqualiserStore()))
        .padding()
}