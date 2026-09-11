import SwiftUI

/// The processing screen's determinate ring.
///
/// A 2pt track with an accent arc drawn clockwise from twelve o'clock. The arc
/// follows the reported fraction and never overshoots it, which is why it
/// animates on a linear curve rather than a spring.
struct RIGProgressRing: View {
    /// 0...1.
    let fraction: Double
    var diameter: CGFloat = 214
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(RIGTheme.text(12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(RIGTheme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)
                .animation(NocturneMotion.progress, value: fraction)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// The soft accent bloom behind the processing ring, breathing on a 2.2s cycle.
struct RIGProcessingGlow: View {
    @State private var isBright = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [RIGTheme.Accent.a800, .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 130
                )
            )
            .opacity(isBright ? 0.8 : 0.35)
            .animation(
                .easeInOut(duration: NocturneMotion.glowPeriod / 2).repeatForever(autoreverses: true),
                value: isBright
            )
            .onAppear { isBright = true }
            .accessibilityHidden(true)
    }
}

/// The light bar that sweeps down the photograph while the garment is being
/// separated. Its position tracks real progress, so it reads as work being
/// done rather than as decoration.
struct RIGProcessingSweep: View {
    /// 0...1.
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let bandHeight = height * 0.44
            LinearGradient(
                colors: [.clear, RIGTheme.accent.opacity(0.42), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: bandHeight)
            .offset(y: fraction * (height + bandHeight) - bandHeight)
            .animation(NocturneMotion.progress, value: fraction)
        }
        .accessibilityHidden(true)
    }
}

/// One line of the processing checklist. The three states — waiting, running,
/// done — are the design's, and the icon carries the distinction.
struct RIGProgressStep: View {
    enum State { case waiting, running, done }

    let label: String
    let state: State

    var body: some View {
        HStack(spacing: 9) {
            icon
                .font(.system(size: 15))
                .frame(width: 18)
            Text(label)
                .font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .foregroundStyle(colour)
        .opacity(state == .waiting ? 0.7 : 1)
        .animation(NocturneMotion.control, value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .done: Image(systemName: "checkmark.circle.fill")
        case .running: RIGSpinner(diameter: 15)
        case .waiting: Image(systemName: "circle")
        }
    }

    private var colour: Color {
        switch state {
        case .done: return RIGTheme.accent
        case .running: return RIGTheme.textPrimary
        case .waiting: return RIGTheme.text(35)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .done: return "\(label): tamamlandı"
        case .running: return "\(label): sürüyor"
        case .waiting: return "\(label): bekliyor"
        }
    }
}

/// The indeterminate spinner: a ring with one accent quarter, turning once
/// every 0.9s.
struct RIGSpinner: View {
    var diameter: CGFloat = 22
    var lineWidth: CGFloat = 2

    @State private var isTurning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(RIGTheme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .background(Circle().strokeBorder(RIGTheme.text(14), lineWidth: lineWidth))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(isTurning ? 360 : 0))
            .animation(
                .linear(duration: NocturneMotion.spinPeriod).repeatForever(autoreverses: false),
                value: isTurning
            )
            .onAppear { isTurning = true }
            .accessibilityHidden(true)
    }
}

/// A thin determinate bar. Used at two weights: 3pt for a whole queue, 2pt
/// inside one row.
struct RIGProgressBar: View {
    /// 0...1.
    let fraction: Double
    var height: CGFloat = 3
    var tint: Color = RIGTheme.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(RIGTheme.text(12))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: height)
        .animation(NocturneMotion.standard(0.5), value: fraction)
        .accessibilityHidden(true)
    }
}

/// A shimmering placeholder block for the loading state.
struct RIGSkeleton: View {
    var cornerRadius: CGFloat = RIGTheme.Radius.large

    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(RIGTheme.text(8))
                .overlay(
                    LinearGradient(
                        colors: [.clear, RIGTheme.text(13), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 240)
                    .offset(x: phase * (proxy.size.width + 240))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .onAppear {
                    withAnimation(
                        .linear(duration: NocturneMotion.shimmerPeriod).repeatForever(autoreverses: false)
                    ) {
                        phase = 1
                    }
                }
        }
        .accessibilityHidden(true)
    }
}
