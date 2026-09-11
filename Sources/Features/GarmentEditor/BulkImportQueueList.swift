import SwiftUI

/// The queue overview from the design: a count, an aggregate bar, and one row
/// per photograph showing where it has got to.
///
/// The design's bulk screen is *only* this list — it has no per-photograph
/// review, and its own next-steps note asks for one to be added. RIG already
/// reviews every garment before it is saved, so the list is used for what it
/// is genuinely good at: showing the shape of the batch, before the run starts
/// and after it finishes.
struct BulkImportQueueList: View {
    let queue: BulkImportQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rows
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(queue.count == 1 ? "1 parça" : "\(queue.count) parça")
                    .font(.system(size: 26, weight: .medium))
                    .tracking(-0.5)
                Spacer(minLength: 8)
                Text(statusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(RIGTheme.text(55))
                    .multilineTextAlignment(.trailing)
            }

            RIGProgressBar(fraction: settledFraction)
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.bottom, RIGTheme.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(queue.count) parça. \(statusLine)")
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, item in
                    BulkQueueRow(
                        item: item,
                        position: index + 1,
                        isCurrent: queue.current?.id == item.id
                    )
                }
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.top, 8)
        }
    }

    private var statusLine: String {
        var parts: [String] = []
        if queue.savedCount > 0 { parts.append("\(queue.savedCount) hazır") }
        if queue.failedCount > 0 { parts.append("\(queue.failedCount) hata") }
        if queue.skippedCount > 0 { parts.append("\(queue.skippedCount) atlandı") }
        let remaining = queue.count - queue.savedCount - queue.failedCount - queue.skippedCount
        if remaining > 0 { parts.append("\(remaining) bekliyor") }
        return parts.joined(separator: " · ")
    }

    /// How much of the batch has reached a final state.
    private var settledFraction: Double {
        guard queue.count > 0 else { return 0 }
        let settled = queue.savedCount + queue.skippedCount + queue.failedCount
        return Double(settled) / Double(queue.count)
    }
}

/// One photograph's row in the queue.
struct BulkQueueRow: View {
    let item: BulkImportQueueItem
    let position: Int
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 11) {
            thumbnail

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Parça \(position)")
                        .font(.system(size: 14))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    RIGTag(text: stateLabel, kind: stateKind)
                }

                RIGProgressBar(fraction: fraction, height: 2, tint: tint)
                    .padding(.top, 9)

                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(RIGTheme.text(48))
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
        .padding(9)
        .background(RIGTheme.cardBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous)
                .strokeBorder(item.isFailed ? RIGTheme.Neutral.n700 : .clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Parça \(position): \(stateLabel). \(note)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let result = item.importResult {
                GarmentImageView(relativePath: result.thumbnailRelativePath ?? result.cutoutRelativePath)
                    .padding(4)
            } else {
                RoundedRectangle(cornerRadius: RIGTheme.Radius.small, style: .continuous)
                    .fill(RIGTheme.Neutral.n900)
            }
        }
        .frame(width: 46, height: 60)
        .background(RIGTheme.pageBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.small, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.small, style: .continuous))
    }

    private var stateLabel: String {
        switch item.status {
        case .pending: return isCurrent ? "İşleniyor" : "Bekliyor"
        case .ready: return "İncelemede"
        case .failed: return "Hata"
        case .saved: return "Hazır"
        case .skipped: return "Atlandı"
        }
    }

    private var stateKind: RIGTag.Kind {
        switch item.status {
        case .pending: return isCurrent ? .accent : .neutral
        case .ready: return .accent
        case .failed: return .outline
        case .saved, .skipped: return .neutral
        }
    }

    private var fraction: Double {
        switch item.status {
        case .pending: return isCurrent ? 0.48 : 0
        case .ready: return 0.8
        case .saved: return 1
        case .failed, .skipped: return 0
        }
    }

    private var tint: Color {
        item.isFailed ? RIGTheme.Neutral.n600 : RIGTheme.accent
    }

    private var note: String {
        switch item.status {
        case .pending: return isCurrent ? "Arka plan kaldırılıyor…" : "Sırada"
        case .ready: return "Bilgileri bekleniyor"
        case .failed(let message): return message
        case .saved: return "Dolabına eklendi"
        case .skipped: return "Atlandı, saklanmadı"
        }
    }
}
