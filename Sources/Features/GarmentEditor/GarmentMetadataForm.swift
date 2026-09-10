import SwiftUI

/// The metadata RIG asks for. Deliberately short.
///
/// The ML spike found that coarse category information carried nearly all of
/// the useful signal while free-text descriptions carried the rest of the cost,
/// so RIG asks for a category and a colour family and does not ask anyone to
/// write prose about their trousers.
struct GarmentMetadataFields: Equatable {
    var displayName: String = ""
    var subtype: String = ""
    var category: GarmentCategory = .top
    var colorFamily: ColorFamily = .black
    var seasons: SeasonSet = .all
    var isFavorite: Bool = false
    var notes: String = ""

    var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty && !seasons.normalized.isEmpty
    }

    init() {}

    init(item: ClothingItem) {
        displayName = item.displayName
        subtype = item.subtype
        category = item.category
        colorFamily = item.primaryColor
        seasons = item.seasons
        isFavorite = item.isFavorite
        notes = item.notes
    }

    func apply(to item: ClothingItem, now: Date = Date()) {
        item.displayName = trimmedName
        item.subtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = category
        item.primaryColor = colorFamily
        item.seasons = seasons
        item.isFavorite = isFavorite
        item.notes = notes
        item.touch(now)
    }
}

struct GarmentMetadataForm: View {
    @Binding var fields: GarmentMetadataFields

    private let swatchColumns = [GridItem(.adaptive(minimum: 62), spacing: RIGTheme.Spacing.s)]

    var body: some View {
        Group {
            Section("Garment") {
                TextField("Name", text: $fields.displayName)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Garment name")
                TextField("Kind, for example crewneck (optional)", text: $fields.subtype)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Garment kind")
                Picker("Category", selection: $fields.category) {
                    ForEach(GarmentCategory.allCases.sorted { $0.displayOrder < $1.displayOrder }) { category in
                        Text(category.displayName).tag(category)
                    }
                }
            }

            Section {
                LazyVGrid(columns: swatchColumns, spacing: RIGTheme.Spacing.m) {
                    ForEach(ColorFamily.allCases) { family in
                        ColorSwatchButton(
                            family: family,
                            isSelected: fields.colorFamily == family
                        ) {
                            fields.colorFamily = family
                        }
                    }
                }
                .padding(.vertical, RIGTheme.Spacing.xs)
            } header: {
                Text("Primary colour")
            } footer: {
                Text("You choose the colour family. RIG does not guess it from the photo.")
            }

            Section {
                ForEach(Season.allCases) { season in
                    Toggle(season.displayName, isOn: seasonBinding(season))
                }
                Toggle("All year", isOn: allSeasonBinding)
            } header: {
                Text("Seasons")
            } footer: {
                Text("Used to keep summer-only and winter-only pieces out of the same look. This is not a weather forecast.")
            }

            Section("Optional") {
                Toggle("Favourite", isOn: $fields.isFavorite)
                TextField("Notes", text: $fields.notes, axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityLabel("Notes")
            }
        }
    }

    private func seasonBinding(_ season: Season) -> Binding<Bool> {
        Binding(
            get: { fields.seasons.contains(season.set) },
            set: { isOn in
                var updated = fields.seasons
                if isOn {
                    updated.formUnion(season.set)
                } else {
                    updated.subtract(season.set)
                }
                fields.seasons = updated
            }
        )
    }

    private var allSeasonBinding: Binding<Bool> {
        Binding(
            get: { fields.seasons.normalized == SeasonSet.all },
            set: { isOn in
                fields.seasons = isOn ? SeasonSet.all : SeasonSet()
            }
        )
    }
}

struct ColorSwatchButton: View {
    let family: ColorFamily
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: RIGTheme.Spacing.xs) {
                RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous)
                    .fill(RIGTheme.swatch(for: family))
                    .frame(height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : RIGTheme.hairline, lineWidth: isSelected ? 2.5 : 0.5)
                    )
                Text(family.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
            }
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(family.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
