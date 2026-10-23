import SwiftUI

/// Routes an open comparison to the correct view for its mode.
struct ComparisonDetailView: View {
    let comparison: Comparison

    var body: some View {
        switch comparison.mode {
        case .text:
            TextComparisonView(a: comparison.a, b: comparison.b)
        case .image:
            ImageComparisonView(a: comparison.a, b: comparison.b)
        case .folder:
            FolderComparisonView(a: comparison.a, b: comparison.b)
        case .merge:
            if let session = comparison.mergeSession {
                MergeView(session: session)
            }
        case .binary:
            BinaryComparisonView(a: comparison.a, b: comparison.b)
        case .pasted:
            if let document = comparison.pasted {
                PastedTextComparisonView(document: document)
            }
        }
    }
}
