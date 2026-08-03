import SwiftUI

enum KyndynTheme {
    static let pink = Color(red: 1.00, green: 0.31, blue: 0.48)
    static let purple = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let blue = Color(red: 0.11, green: 0.55, blue: 1.00)
    static let green = Color(red: 0.16, green: 0.78, blue: 0.44)
    static let amber = Color(red: 1.00, green: 0.58, blue: 0.00)
    static let brand = purple

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [pink, purple, blue],
            startPoint: .leading, endPoint: .trailing)
    }

    static func screenBackground(for scheme: ColorScheme) -> some ShapeStyle {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.07, green: 0.09, blue: 0.14),
                   Color(red: 0.10, green: 0.08, blue: 0.16)]
                : [Color(red: 0.96, green: 0.98, blue: 1.00),
                   Color(red: 0.99, green: 0.97, blue: 0.99)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct KyndynScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(KyndynTheme.screenBackground(for: colorScheme))
            .ignoresSafeArea()
    }
}

private struct KyndynCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color?
    let raised: Bool

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color.white.opacity(0.075)
                          : Color.white.opacity(0.90))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(tint?.opacity(colorScheme == .dark ? 0.42 : 0.28)
                            ?? Color.primary.opacity(0.08), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if let tint {
                    Capsule()
                        .fill(tint)
                        .frame(width: 4)
                        .padding(.vertical, 13)
                        .padding(.leading, 5)
                        .accessibilityHidden(true)
                }
            }
            .shadow(
                color: raised ? Color.black.opacity(colorScheme == .dark ? 0.22 : 0.07) : .clear,
                radius: raised ? 12 : 0, y: raised ? 5 : 0)
    }
}

extension View {
    func kyndynCard(tint: Color? = nil, raised: Bool = false) -> some View {
        modifier(KyndynCardModifier(tint: tint, raised: raised))
    }
}

struct KyndynSectionHeader: View {
    let title: String
    var count: Int? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)
            if let count {
                Text("\(count)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12), in: Capsule())
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct KyndynStatusPill: View {
    let text: String
    let systemImage: String
    var tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
