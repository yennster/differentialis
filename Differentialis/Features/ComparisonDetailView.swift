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
            MergeView(base: comparison.base ?? .empty(name: "base"),
                      left: comparison.a, right: comparison.b)
        }
    }
}
