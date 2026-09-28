import AppKit
import SwiftUI

struct LauncherBrandMark: View {
    var body: some View {
        MacticianMark()
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
    }
}

struct MacticianMark: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let ribbonStyle = StrokeStyle(
                lineWidth: width * 0.135,
                lineCap: .round,
                lineJoin: .round
            )
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.24, style: .continuous)
                    .fill(LauncherTheme.ColorToken.window)
                Path { path in
                    path.move(to: CGPoint(x: width * 0.18, y: height * 0.80))
                    path.addLine(to: CGPoint(x: width * 0.18, y: height * 0.58))
                    path.addLine(to: CGPoint(x: width * 0.30, y: height * 0.25))
                    path.addLine(to: CGPoint(x: width * 0.40, y: height * 0.25))
                    path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.68))
                }
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.35, blue: 0.78),
                            Color(red: 0.46, green: 0.24, blue: 0.89)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: ribbonStyle
                )
                Path { path in
                    path.move(to: CGPoint(x: width * 0.82, y: height * 0.80))
                    path.addLine(to: CGPoint(x: width * 0.82, y: height * 0.58))
                    path.addLine(to: CGPoint(x: width * 0.70, y: height * 0.25))
                    path.addLine(to: CGPoint(x: width * 0.60, y: height * 0.25))
                    path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.68))
                }
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.48, green: 0.36, blue: 1.00),
                            Color(red: 0.39, green: 0.21, blue: 0.84)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    ),
                    style: ribbonStyle
                )
                Capsule()
                    .fill(Color(red: 0.78, green: 0.65, blue: 0.36))
                    .frame(width: max(1, width * 0.025), height: height * 0.17)
                    .position(x: width * 0.50, y: height * 0.64)
                Circle()
                    .fill(LauncherTheme.ColorToken.primaryAction)
                    .frame(width: width * 0.055, height: width * 0.055)
                    .position(x: width * 0.18, y: height * 0.75)
                Circle()
                    .fill(LauncherTheme.ColorToken.primaryAction)
                    .frame(width: width * 0.055, height: width * 0.055)
                    .position(x: width * 0.82, y: height * 0.75)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct LauncherDragRegion: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView { DragView() }
    func updateNSView(_: NSView, context _: Context) { }

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

struct LauncherStatusIcon: View {
    let symbol: String
    let color: Color
    var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
            Circle()
                .stroke(color.opacity(0.42), lineWidth: 1)
            if spinning {
                ProgressView()
                    .controlSize(.small)
                    .tint(color)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }
}

struct LauncherStatusHeader: View {
    let symbol: String
    let color: Color
    let title: String
    let description: String
    var spinning = false

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            LauncherStatusIcon(symbol: symbol, color: color, spinning: spinning)
            VStack(alignment: .leading, spacing: LauncherTheme.Spacing.xSmall) {
                Text(title)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                Text(description)
                    .font(.system(size: 15))
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct LauncherFieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(LauncherTheme.ColorToken.textTertiary)
    }
}

struct LauncherMenuControl<MenuContent: View>: View {
    let value: String
    let showsBackground: Bool
    let menuContent: MenuContent

    init(
        value: String,
        showsBackground: Bool = true,
        @ViewBuilder content: () -> MenuContent
    ) {
        self.value = value
        self.showsBackground = showsBackground
        menuContent = content()
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: LauncherTheme.Spacing.small) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: LauncherTheme.Spacing.small)
            }
            .padding(.horizontal, showsBackground ? LauncherTheme.Spacing.medium : 0)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
                    .fill(
                        showsBackground
                            ? LauncherTheme.ColorToken.raisedControl.opacity(0.82)
                            : .clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
                    .stroke(
                        showsBackground ? LauncherTheme.ColorToken.neutralBorder : .clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .accessibilityValue(value)
    }
}

struct LauncherSectionHeader: View {
    let title: String
    let description: String?

    init(_ title: String, description: String? = nil) {
        self.title = title
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherTheme.Spacing.xSmall) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(LauncherTheme.ColorToken.textPrimary)
            if let description {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct LauncherDivider: View {
    var body: some View {
        Rectangle()
            .fill(LauncherTheme.ColorToken.neutralBorder)
            .frame(height: 1)
    }
}

// The main launcher uses larger actions; settings retain their existing control styles.
struct LauncherActionButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, support }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var accent: Color {
        switch kind {
        case .primary: return Color(red: 0, green: 0.94, blue: 0.53)
        case .secondary: return LauncherTheme.ColorToken.raisedControl
        case .support: return Color(red: 0.66, green: 0.12, blue: 0.94)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: kind == .secondary ? .medium : .bold))
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(
                !isEnabled ? LauncherTheme.ColorToken.textTertiary
                    : kind == .primary ? LauncherTheme.ColorToken.window : .white
            )
            .padding(.horizontal, 22)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(
                        colors: isEnabled
                            ? [accent.opacity(isHovered ? 1 : 0.94), accent]
                            : [LauncherTheme.ColorToken.raisedControl],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        Color.white.opacity(kind == .secondary ? (isHovered ? 0.32 : 0.20) : 0.12),
                        lineWidth: 1
                    )
            )
            .shadow(color: accent.opacity(isEnabled && kind != .secondary ? 0.20 : 0), radius: 12, y: 3)
            .brightness(configuration.isPressed ? -0.08 : isHovered ? 0.04 : 0)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.98)
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(isFocused ? LauncherTheme.ColorToken.interactive : .clear, lineWidth: 2)
                    .padding(-3)
            )
            .onHover { isHovered = $0 }
    }
}

struct LauncherPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(LauncherTheme.ColorToken.surface)
            .padding(.horizontal, LauncherTheme.Spacing.large)
            .frame(minHeight: LauncherTheme.Metric.primaryControlHeight)
            .background(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius, style: .continuous)
                    .fill(
                        isEnabled
                            ? LauncherTheme.ColorToken.primaryAction.opacity(isHovered ? 1 : 0.94)
                            : LauncherTheme.ColorToken.raisedControl
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.25 : 0.08), lineWidth: 1)
            )
            .shadow(
                color: LauncherTheme.ColorToken.primaryAction.opacity(
                    isEnabled && !configuration.isPressed ? 0.24 : 0
                ),
                radius: 8,
                y: 3
            )
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.99)
            .foregroundColor(isEnabled ? LauncherTheme.ColorToken.surface : LauncherTheme.ColorToken.textTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius + 2)
                    .stroke(
                        isFocused ? LauncherTheme.ColorToken.interactive : .clear,
                        lineWidth: 2
                    )
                    .padding(-3)
            )
            .onHover { isHovered = $0 }
    }
}

struct LauncherOutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(
                isEnabled
                    ? LauncherTheme.ColorToken.textPrimary
                    : LauncherTheme.ColorToken.textTertiary
            )
            .padding(.horizontal, LauncherTheme.Spacing.large)
            .frame(minHeight: LauncherTheme.Metric.primaryControlHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: LauncherTheme.Metric.controlRadius,
                    style: .continuous
                )
                .fill(LauncherTheme.ColorToken.surface)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: LauncherTheme.Metric.controlRadius,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(
                        isEnabled
                            ? (configuration.isPressed ? 0.36 : isHovered ? 0.25 : 0.13)
                            : 0.08
                    ),
                    lineWidth: 1.5
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius + 2)
                    .stroke(
                        isFocused ? LauncherTheme.ColorToken.interactive : .clear,
                        lineWidth: 2
                    )
                    .padding(-3)
            )
            .onHover { isHovered = $0 }
    }
}

struct LauncherSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isEnabled ? LauncherTheme.ColorToken.textPrimary : LauncherTheme.ColorToken.textTertiary)
            .padding(.horizontal, LauncherTheme.Spacing.regular)
            .frame(minHeight: LauncherTheme.Metric.standardControlHeight)
            .background(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius, style: .continuous)
                    .fill(
                        LauncherTheme.ColorToken.raisedControl.opacity(
                            configuration.isPressed ? 1 : isEnabled ? (isHovered ? 0.94 : 0.78) : 0.38
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius, style: .continuous)
                    .stroke(LauncherTheme.ColorToken.neutralBorder, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius + 2)
                    .stroke(isFocused ? LauncherTheme.ColorToken.interactive : .clear, lineWidth: 2)
                    .padding(-3)
            )
            .onHover { isHovered = $0 }
    }
}

struct LauncherTertiaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false
    var tint = LauncherTheme.ColorToken.interactive

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isEnabled ? tint : LauncherTheme.ColorToken.textTertiary)
            .padding(.horizontal, LauncherTheme.Spacing.small)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.09 : isHovered ? 0.05 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius + 2)
                    .stroke(isFocused ? LauncherTheme.ColorToken.interactive : .clear, lineWidth: 2)
                    .padding(-3)
            )
            .onHover { isHovered = $0 }
    }
}

struct LauncherDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isEnabled ? LauncherTheme.ColorToken.danger : LauncherTheme.ColorToken.textTertiary)
            .padding(.horizontal, LauncherTheme.Spacing.regular)
            .frame(minHeight: LauncherTheme.Metric.standardControlHeight)
            .background(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
                    .fill(
                        LauncherTheme.ColorToken.danger.opacity(
                            configuration.isPressed ? 0.16 : isHovered ? 0.12 : 0.08
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius)
                    .stroke(LauncherTheme.ColorToken.danger.opacity(isEnabled ? 0.42 : 0.12), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LauncherTheme.Metric.controlRadius + 2)
                    .stroke(isFocused ? LauncherTheme.ColorToken.interactive : .clear, lineWidth: 2)
                    .padding(-3)
            )
            .onHover { isHovered = $0 }
    }
}

struct LauncherIconButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(LauncherTheme.ColorToken.textSecondary)
            .frame(width: 34, height: 34)
            .background(
                Circle().fill(Color.white.opacity(configuration.isPressed ? 0.12 : isHovered ? 0.08 : 0.04))
            )
            .overlay(Circle().stroke(LauncherTheme.ColorToken.neutralBorder, lineWidth: 1))
            .overlay(
                Circle()
                    .stroke(isFocused ? LauncherTheme.ColorToken.interactive : .clear, lineWidth: 2)
                    .padding(-3)
            )
            .onHover { isHovered = $0 }
    }
}

struct LauncherProgressBar: View {
    let value: Double

    var body: some View {
        ProgressView(value: value)
            .progressViewStyle(.linear)
            .tint(LauncherTheme.ColorToken.interactive)
            .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}
