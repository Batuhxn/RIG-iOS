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
    var category: GarmentCategory?
    var colorFamily: ColorFamily?
    var seasons: SeasonSet = []
    var isFavorite: Bool = false
    var notes: String = ""

    var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty && category != nil && colorFamily != nil && !seasons.isEmpty
    }

    mutating func setSeason(_ season: Season, selected: Bool) {
        if selected {
            seasons.formUnion(season.set)
        } else {
            seasons.subtract(season.set)
        }
    }

    mutating func setAllYear(_ selected: Bool) {
        seasons = selected ? .all : []
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

    @discardableResult
    func apply(to item: ClothingItem, now: Date = Date()) -> Bool {
        guard isValid, let category, let colorFamily else { return false }
        item.displayName = trimmedName
        item.subtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = category
        item.primaryColor = colorFamily
        item.seasons = seasons
        item.isFavorite = isFavorite
        item.notes = notes
        item.touch(now)
        return true
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
                Picker("Category (required)", selection: $fields.category) {
                    Text("Choose a category").tag(nil as GarmentCategory?)
                    ForEach(GarmentCategory.allCases.sorted { $0.displayOrder < $1.displayOrder }) { category in
                        Text(category.displayName).tag(Optional(category))
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
                Text("Primary colour (required)")
            } footer: {
                Text("Choose one colour family. RIG does not guess it from the photo.")
            }

            Section {
                ForEach(Season.allCases) { season in
                    Toggle(season.displayName, isOn: seasonBinding(season))
                }
                Toggle("All year", isOn: allSeasonBinding)
            } header: {
                Text("Seasons (required)")
            } footer: {
                Text("Choose at least one season. All year selects all four. This is not a weather forecast.")
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
            set: { fields.setSeason(season, selected: $0) }
        )
    }

    private var allSeasonBinding: Binding<Bool> {
        Binding(
            get: { fields.seasons == SeasonSet.all },
            set: { fields.setAllYear($0) }
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
