import AppKit
import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var updateController: LauncherUpdateController
    @State private var showSettings = false
    @State private var showResetConfirmation = false

    private let heroImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MacticianHero", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        GeometryReader { geometry in
            let surfaceWidth = max(0, geometry.size.width - LauncherTheme.Metric.outerInset * 2)
            let surfaceHeight = max(0, geometry.size.height - LauncherTheme.Metric.outerInset * 2)
            ZStack {
                LauncherTheme.ColorToken.window.ignoresSafeArea()
                clientSurface(
                    compactHeight: geometry.size.height < 720,
                    availableWidth: surfaceWidth,
                    availableHeight: surfaceHeight
                )
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(
            get: {
                model.shouldShowTelemetryNotice && !model.isNativeIPadRuntimeSelected
            },
            set: { isPresented in
                if !isPresented && !model.isNativeIPadRuntimeSelected {
                    model.shouldShowTelemetryNotice = false
                }
            }
        )) {
            LauncherTelemetryNoticeView(model: model)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showSettings) {
            LauncherSettingsView(
                model: model,
                updateController: updateController,
                showResetConfirmation: $showResetConfirmation
            )
        }
        .sheet(item: $model.announcement) { announcement in
            LauncherAnnouncementView(
                announcement: announcement,
                dismiss: model.dismissAnnouncement
            )
            .interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshHotkeyStatus()
        }
    }

    private func clientSurface(
        compactHeight: Bool,
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> some View {
        ZStack {
            artwork

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 0) {
                        hero(compact: compactHeight)
                        LauncherStateDeck(model: model, showSettings: $showSettings)
                        communityActions
                            .padding(.top, LauncherTheme.Spacing.large)
                    }
                    .padding(.horizontal, LauncherTheme.Metric.stateDeckInset)
                    .padding(.bottom, LauncherTheme.Spacing.large)
                    .frame(maxWidth: .infinity)
                }
                footer
            }
            .frame(width: availableWidth)
        }
        .frame(width: availableWidth, height: availableHeight)
        .background(LauncherTheme.ColorToken.surface)
        .clipShape(
            RoundedRectangle(cornerRadius: LauncherTheme.Metric.surfaceRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LauncherTheme.Metric.surfaceRadius, style: .continuous)
                .stroke(LauncherTheme.ColorToken.neutralBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.52), radius: 22, y: 10)
    }

    private var artwork: some View {
        GeometryReader { geometry in
            ZStack {
                if let heroImage {
                    Image(nsImage: heroImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }

                LinearGradient(
                    stops: [
                        .init(color: LauncherTheme.ColorToken.window.opacity(0.65), location: 0),
                        .init(color: LauncherTheme.ColorToken.window.opacity(0.34), location: 0.34),
                        .init(color: LauncherTheme.ColorToken.window.opacity(0.76), location: 0.7),
                        .init(color: LauncherTheme.ColorToken.window.opacity(0.98), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [LauncherTheme.ColorToken.window.opacity(0.78), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: LauncherTheme.Spacing.medium) {
            LauncherBrandMark()
            VStack(alignment: .leading, spacing: 3) {
                Text("Mactician")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                Text(LauncherL10n.text("header.subtitle"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
            }

            LauncherDragRegion()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)

            Text(LauncherBuildInfo.display)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(LauncherTheme.ColorToken.textSecondary)
        }
        .padding(.horizontal, LauncherTheme.Metric.trafficLightReserve)
        .frame(height: 64)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .bottom) { LauncherDivider() }
    }

    private func hero(compact: Bool) -> some View {
        let prominent = model.mode == .ready && !model.isNativeIPadRuntimeSelected
        return HStack {
            VStack(alignment: .leading, spacing: LauncherTheme.Spacing.regular) {
                Text(LauncherL10n.text("hero.title"))
                    .font(.system(size: compact ? (prominent ? 38 : 32) : 44, weight: .black, design: .serif))
                    .lineSpacing(0)
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: Color.black.opacity(0.45), radius: 6, y: 2)

                Text(LauncherL10n.text("hero.description"))
                    .font(.system(size: compact ? 17 : 19, weight: .medium))
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, LauncherTheme.Metric.stateDeckPadding)
        .frame(height: compact ? (prominent ? 176 : 144) : (prominent ? 296 : 196), alignment: .leading)
    }

    private var communityActions: some View {
        HStack(spacing: LauncherTheme.Spacing.large) {
            Image(systemName: "heart.fill")
                .font(.system(size: 28))
                .foregroundColor(LauncherTheme.ColorToken.interactive)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(LauncherL10n.text("community.title"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(LauncherTheme.ColorToken.textPrimary)
                Text(LauncherL10n.text("community.description"))
                    .font(.system(size: 15))
                    .foregroundColor(LauncherTheme.ColorToken.textSecondary)
            }
            Spacer(minLength: LauncherTheme.Spacing.small)

            Link(destination: MacticianIdentity.donateURL) {
                Label(LauncherL10n.text("action.donate"), systemImage: "heart")
                    .frame(minWidth: 106)
            }
            .buttonStyle(LauncherActionButtonStyle(kind: .support))

            Link(destination: MacticianIdentity.feedbackURL) {
                Label(LauncherL10n.text("action.suggest_improvement"), systemImage: "lightbulb")
            }
            .buttonStyle(LauncherActionButtonStyle(kind: .secondary))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, LauncherTheme.Metric.stateDeckPadding)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.06, green: 0.035, blue: 0.12).opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LauncherTheme.ColorToken.interactive.opacity(0.65), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: LauncherTheme.Spacing.small) {
            Label(LauncherL10n.text("footer.private_build"), systemImage: "lock.fill")
            Text("\u{00b7}")
            Text(LauncherL10n.text("footer.apple_silicon"))
            Text("\u{00b7}")
            Link(destination: MacticianIdentity.websiteURL) {
                Label(LauncherL10n.text("footer.developer_website"), systemImage: "link")
                    .foregroundColor(LauncherTheme.ColorToken.interactive)
            }
            .buttonStyle(.plain)
            .help(LauncherL10n.text("footer.developer_website"))
            Spacer()
            Text(LauncherL10n.text("footer.legal"))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(LauncherTheme.ColorToken.textSecondary)
        .padding(.horizontal, LauncherTheme.Metric.stateDeckInset + 12)
        .frame(height: 44)
    }
}
