import SwiftUI

/// "Parça bilgileri" — the last step before saving.
///
/// The design leads with the result rather than with the form: a thumbnail and
/// a line confirming the background came off, then the short set of fields RIG
/// actually asks for, then one full-width save. The reassurance underneath
/// ("Alanları sonra da düzenleyebilirsin") is doing real work — it is what
/// makes it reasonable to ask for so little here.
struct GarmentDetailsStep: View {
    @Binding var fields: GarmentMetadataFields

    let previewPath: String?
    let isBackgroundRemoved: Bool
    let isSaving: Bool
    let errorMessage: String?
    let onDismissError: () -> Void
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RIGFlowHeader(title: "Parça bilgileri", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: RIGTheme.Spacing.l) {
                    resultSummary

                    if let errorMessage {
                        RIGErrorBanner(message: errorMessage, onDismiss: onDismissError)
                    }

                    NocturneMetadataFields(fields: $fields)
                }
                .padding(.horizontal, RIGTheme.Spacing.xl)
                .padding(.top, RIGTheme.Spacing.l)
                .padding(.bottom, RIGTheme.Spacing.xl)
            }

            VStack(spacing: 0) {
                Button {
                    onSave()
                } label: {
                    if isSaving {
                        HStack(spacing: 8) {
                            RIGSpinner(diameter: 16)
                            Text("Kaydediliyor…")
                        }
                    } else {
                        Text("Dolabıma kaydet")
                    }
                }
                .buttonStyle(RIGPrimaryButtonStyle())
                .disabled(!fields.isValid || isSaving)
                .opacity(fields.isValid ? 1 : 0.45)
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.top, 14)
            .padding(.bottom, RIGTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RIGTheme.pageBackground)
    }

    private var resultSummary: some View {
        HStack(spacing: 14) {
            GarmentImageView(relativePath: previewPath, symbolName: fields.category.symbolName)
                .padding(RIGTheme.Spacing.s)
                .frame(width: 82, height: 106)
                .background(RIGTheme.cardBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous))
                .nocturneElevationSmall(radius: RIGTheme.Radius.medium)

            VStack(alignment: .leading, spacing: 2) {
                RIGTheme.kicker(isBackgroundRemoved ? "Arka plan kaldırıldı" : "Orijinal fotoğraf", tracking: 1.1)
                Text("Hazır")
                    .font(.system(size: 17, weight: .medium))
                    .padding(.top, 2)
                Text("Alanları sonra da düzenleyebilirsin")
                    .font(.system(size: 12))
                    .foregroundStyle(RIGTheme.text(52))
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A simple wrapping row of chips.
///
/// `LazyVGrid` with an adaptive column would size every cell to the widest,
/// which reads wrong for pills of different word lengths. This lays them out
/// left to right and wraps, which is what the design shows.
struct FlowingChips<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

/// Left-to-right wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The metadata RIG asks for, in the design's form style.
///
/// Shared by the single-garment details step and the bulk queue's per-item
/// review, so the two ask for the same things in the same shapes rather than
/// drifting apart.
struct NocturneMetadataFields: View {
    @Binding var fields: GarmentMetadataFields

    var body: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.l) {
            RIGField(label: "Ad") {
                RIGTextField(placeholder: "Örn. Keten gömlek", text: $fields.displayName)
            }

            RIGField(label: "Kategori") {
                FlowingChips(
                    items: GarmentCategory.allCases.sorted { $0.displayOrder < $1.displayOrder }
                ) { category in
                    RIGChip(title: category.displayName, isOn: fields.category == category) {
                        fields.category = category
                    }
                }
            }

            RIGField(label: "Renk") {
                FlowingChips(items: ColorFamily.allCases) { family in
                    RIGColorDot(
                        colour: RIGTheme.swatch(for: family),
                        isOn: fields.colorFamily == family,
                        label: family.displayName
                    ) {
                        fields.colorFamily = family
                    }
                }
            }

            RIGField(label: "Sezon") {
                FlowingChips(items: Season.allCases) { season in
                    RIGChip(title: season.displayName, isOn: fields.seasons.contains(season.set)) {
                        toggle(season)
                    }
                }
            }

            RIGField(label: "Alt tür") {
                RIGTextField(placeholder: "İsteğe bağlı", text: $fields.subtype)
            }

            Toggle("Favori", isOn: $fields.isFavorite)
                .font(.system(size: 14))
                .tint(RIGTheme.accent)
                .padding(.vertical, 4)
        }
    }

    private func toggle(_ season: Season) {
        var updated = fields.seasons
        if updated.contains(season.set) {
            updated.remove(season.set)
        } else {
            updated.insert(season.set)
        }
        // A garment with no season at all cannot be ranked, so the last one
        // cannot be switched off.
        if !updated.normalized.isEmpty {
            fields.seasons = updated
        }
    }
}
