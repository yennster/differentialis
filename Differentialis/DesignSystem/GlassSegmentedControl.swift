import SwiftUI

/// A pill segmented control with a sliding tinted-glass selection, matching the
/// purple toggles in the Custom Comparison popover and the image mode switcher.
struct GlassSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Option]
    var tint: Color = Theme.brand
    var compact: Bool = false

    struct Option: Identifiable {
        var value: Value
        var title: String
        var systemImage: String?
        var id: AnyHashable { value }
    }

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(3)
        .background(.black.opacity(0.18), in: Capsule())
        .glassEffect(.regular, in: .capsule)
    }

    @ViewBuilder
    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        Button {
            withAnimation(.snappy(duration: 0.22)) { selection = option.value }
        } label: {
            HStack(spacing: 5) {
                if let image = option.systemImage {
                    Image(systemName: image).font(.system(size: 11, weight: .semibold))
                }
                Text(option.title)
                    .font(.system(size: compact ? 11.5 : 13, weight: .semibold))
            }
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 7)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? Theme.badgeForeground : Color.secondary)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .background {
                if isSelected {
                    Capsule()
                        .fill(tint)
                        .matchedGeometryEffect(id: "segment", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
