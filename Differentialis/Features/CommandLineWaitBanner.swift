import SwiftUI

/// Shown above a comparison that `differentialis --wait` opened, so it is clear git is waiting and
/// how to hand control back: Done for a diff, Save (in the merge header) or Cancel for a merge.
struct CommandLineWaitBanner: View {
    @Environment(AppModel.self) private var model
    let comparison: Comparison

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brand)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            if comparison.mergeSession != nil {
                Button("Cancel Merge") { model.closeComparison(comparison.id) }
                    .buttonStyle(.borderless)
                    .help("Close without saving; git keeps the file unresolved")
            } else {
                Button("Done") { model.closeComparison(comparison.id) }
                    .buttonStyle(.glassProminent).tint(Theme.brand)
                    .controlSize(.small)
                    .help("Close this comparison and return to git")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }

    private var message: String {
        guard let session = comparison.mergeSession else {
            return "The command line is waiting. Click Done to move on."
        }
        if let output = session.output {
            return "Save writes the result to \(output.path) and returns to the command line."
        }
        return "The command line is waiting. Close this merge when you’re finished."
    }
}
