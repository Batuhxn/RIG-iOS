import SwiftUI
import UIKit

// MARK: - Processing

/// The background-removal screen: a progress ring around the photograph, a
/// light sweeping down it, and the three stages of the pipeline confirming
/// themselves in turn.
///
/// One honesty note about the number. `GarmentImportService` reports no
/// progress — it is a single async call — so the percentage here is an
/// *estimate* that advances on a timer and deliberately stalls short of the
/// end. Only the real result moves it to 100. The interface therefore never
/// claims the work is finished before it is; it only admits it cannot say
/// exactly how far along it is.
struct ProcessingStep: View {
    let didCrop: Bool
    let onCancel: () -> Void

    /// Set by the owner when the real work completes, which releases the
    /// estimate to 100 and lets the step finish.
    var isFinishing: Bool = false

    @State private var estimate: Double = 0
    @State private var timer: Timer?
    /// Mirrors `isFinishing` into state the timer can actually see.
    ///
    /// The repeating closure is created once and captures the `ProcessingStep`
    /// value that existed then, so reading the `isFinishing` *property* inside
    /// it would read the value from that first render forever. `@State` is
    /// reference-backed and shared across re-renders, so this flag is not.
    @State private var hasRealResult = false

    private var percent: Int { Int((estimate * 100).rounded()) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                RIGProcessingGlow()
                    .frame(width: 262, height: 262)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [RIGTheme.Neutral.n700, RIGTheme.Neutral.n900],
                            center: UnitPoint(x: 0.4, y: 0.25),
                            startRadius: 0,
                            endRadius: 190
                        )
                    )
                    .frame(width: 150, height: 190)
                    .overlay(RIGProcessingSweep(fraction: estimate))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                RIGProgressRing(fraction: estimate)
            }
            .frame(width: 214, height: 214)

            VStack(spacing: 4) {
                Text("Arka plan kaldırılıyor")
                    .font(.system(size: 20, weight: .medium))
                Text("\(didCrop ? "Kırpılan alan işleniyor" : "Orijinal fotoğraf işleniyor") · %\(percent)")
                    .font(.system(size: 13))
                    .foregroundStyle(RIGTheme.text(55))
            }
            .padding(.top, RIGTheme.Spacing.xxl)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Arka plan kaldırılıyor")

            VStack(alignment: .leading, spacing: 10) {
                RIGProgressStep(label: "Fotoğraf hazırlanıyor", state: state(threshold: 0.30))
                RIGProgressStep(label: "Parça ayrıştırılıyor", state: state(threshold: 0.75))
                RIGProgressStep(label: "Kenarlar yumuşatılıyor", state: state(threshold: 1.00))
            }
            .padding(.horizontal, 42)
            .padding(.top, RIGTheme.Spacing.xxl)

            Spacer(minLength: 0)

            Button("İptal", action: onCancel)
                .buttonStyle(RIGQuietButtonStyle())
                .padding(.horizontal, RIGTheme.Spacing.xl)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RIGTheme.pageBackground)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onChange(of: isFinishing) { _, finishing in
            guard finishing else { return }
            hasRealResult = true
            stop()
            withAnimation(NocturneMotion.progress) { estimate = 1 }
        }
    }

    private func state(threshold: Double) -> RIGProgressStep.State {
        if estimate >= threshold { return .done }
        if estimate >= threshold - 0.45 { return .running }
        return .waiting
    }

    private func start() {
        stop()
        estimate = 0
        hasRealResult = false
        timer = Timer.scheduledTimer(withTimeInterval: 0.055, repeats: true) { _ in
            Task { @MainActor in
                guard !hasRealResult else { return }
                // Stalls at 0.9: the remaining tenth belongs to the real result.
                let step = estimate < 0.65 ? 0.03 : 0.02
                estimate = min(0.9, estimate + step)
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Review

/// The result screen: the cut-out garment on a transparency checkerboard, with
/// a before/after toggle and a way to try again.
struct ReviewStep: View {
    let result: GarmentImportResult
    let didCrop: Bool
    let onBack: () -> Void
    let onRetry: () -> Void
    let onContinue: () -> Void

    @Environment(\.rigServices) private var services
    @State private var showingAfter = true

    private var hasCutout: Bool { result.cutoutRelativePath != nil }

    var body: some View {
        VStack(spacing: 0) {
            RIGFlowHeader(title: "Sonuç", onBack: onBack)

            VStack(spacing: RIGTheme.Spacing.l) {
                ZStack {
                    RIGCheckerboard()

                    GarmentImageView(
                        relativePath: showingAfter
                            ? (result.cutoutRelativePath ?? result.originalRelativePath)
                            : result.originalRelativePath
                    )
                    .padding(RIGTheme.Spacing.xxl)
                    .scaleEffect(showingAfter ? 1 : 1.14)
                    .shadow(color: .black.opacity(showingAfter ? 0.6 : 0), radius: 25, y: 18)
                    .animation(NocturneMotion.cutout, value: showingAfter)

                    VStack {
                        HStack {
                            RIGTag(text: badgeText, kind: .accent)
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous))
                .nocturneElevationSmall(radius: RIGTheme.Radius.large)

                if hasCutout {
                    RIGSegmentedControl(
                        options: [(true, "Sonra"), (false, "Önce")],
                        selection: $showingAfter
                    )
                }

                if let message = result.backgroundRemovalMessage {
                    Text("\(message) Orijinal fotoğraf kullanılacak.")
                        .font(.system(size: 12))
                        .foregroundStyle(RIGTheme.text(55))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.top, 14)

            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Devam et", action: onContinue)
                    .buttonStyle(RIGPrimaryButtonStyle())
                Button("Yeniden dene", action: onRetry)
                    .buttonStyle(RIGQuietButtonStyle())
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.top, RIGTheme.Spacing.l)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RIGTheme.pageBackground)
    }

    private var badgeText: String {
        if !hasCutout { return "Orijinal fotoğraf" }
        return didCrop ? "Kırpıldı · arka plan kaldırıldı" : "Arka plan kaldırıldı"
    }
}

// MARK: - Background-removal failure

/// The dedicated failure screen from the design. It is not a dead end: the two
/// ways on are to crop tighter and try again, or to keep the original
/// photograph — which is what RIG has always done when Vision finds nothing.
struct RemovalFailureStep: View {
    let message: String
    let onCropAndRetry: () -> Void
    let onContinueWithOriginal: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: RIGTheme.Spacing.l) {
                Circle()
                    .strokeBorder(RIGTheme.Neutral.n700, lineWidth: 1)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(RIGTheme.Neutral.n400)
                    )
                    .accessibilityHidden(true)

                Text("Arka plan kaldırılamadı")
                    .font(.system(size: 21, weight: .medium))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(RIGTheme.text(55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 38)

            Spacer(minLength: 0)

            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Kırpıp tekrar dene", action: onCropAndRetry)
                    .buttonStyle(RIGPrimaryButtonStyle())
                Button("Orijinal fotoğrafla devam et", action: onContinueWithOriginal)
                    .buttonStyle(RIGQuietButtonStyle())
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RIGTheme.pageBackground)
    }
}

// MARK: - Success

/// The confirmation screen, with the check that draws itself.
struct SuccessStep: View {
    let garmentName: String
    let categoryName: String
    let thumbnailPath: String?
    let onDone: () -> Void
    let onAddAnother: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [RIGTheme.Accent.a800, .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 52
                            )
                        )
                    DrawnCheck(progress: hasAppeared ? 1 : 0)
                        .stroke(RIGTheme.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .frame(width: 54, height: 54)
                }
                .frame(width: 104, height: 104)
                .scaleEffect(hasAppeared ? 1 : 0.6)
                .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Dolabına eklendi")
                        .font(.system(size: 24, weight: .medium))
                    Text("\(garmentName) · \(categoryName)")
                        .font(.system(size: 13))
                        .foregroundStyle(RIGTheme.text(55))
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                GarmentImageView(relativePath: thumbnailPath)
                    .padding(RIGTheme.Spacing.m)
                    .frame(width: 120, height: 154)
                    .background(RIGTheme.cardBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous))
                    .nocturneElevationMedium(radius: RIGTheme.Radius.large)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)

            Spacer(minLength: 0)

            VStack(spacing: RIGTheme.Spacing.s) {
                Button("Dolabı gör", action: onDone)
                    .buttonStyle(RIGPrimaryButtonStyle())
                Button("Bir parça daha ekle", action: onAddAnother)
                    .buttonStyle(RIGQuietButtonStyle())
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RIGTheme.pageBackground)
        .onAppear {
            withAnimation(NocturneMotion.pop) { hasAppeared = true }
        }
    }
}

/// The tick, drawn rather than faded in.
private struct DrawnCheck: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.17, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.height * 0.73))
        path.addLine(to: CGPoint(x: rect.width * 0.83, y: rect.height * 0.27))
        return path.trimmedPath(from: 0, to: progress)
    }
}
