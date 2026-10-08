import SwiftUI

extension GarmentMetadataFields {
    mutating func fillEmptyFields(from result: AutoMetadataResult) {
        if category == nil, !editedFields.contains(.category) { category = result.category?.value }
        if subtype.isEmpty, !editedFields.contains(.subtype), category == result.category?.value { subtype = result.subtype?.value ?? "" }
        if length == nil, !editedFields.contains(.length), category == result.category?.value, subtype == result.subtype?.value,
           GarmentLength.applies(category: category, subtype: subtype) { length = result.length?.value }
        if colorFamily == nil, !editedFields.contains(.primaryColor) { colorFamily = result.primaryColor?.value }
        if secondaryColor == nil, !editedFields.contains(.secondaryColor), colorFamily == result.primaryColor?.value {
            secondaryColor = result.secondaryColor?.value
        }
        autoMetadata = result
        discardStaleConfidence()
        refreshSuggestedName()
    }

    /// "Black mini skirt", built only from what is on the form right now.
    var suggestedName: String? {
        let kind = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let noun = kind.isEmpty ? category?.displayName : kind else { return nil }
        var words: [String] = []
        if let colorFamily { words.append(colorFamily.displayName) }
        if let length, GarmentLength.applies(category: category, subtype: subtype) { words.append(length.rawValue) }
        words.append(noun)
        let phrase = words.joined(separator: " ").lowercased()
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    /// Keeps a RIG-written name in step with the fields. A name the user typed, or
    /// deliberately cleared, is never touched.
    mutating func refreshSuggestedName() {
        guard !editedFields.contains(.name), trimmedName.isEmpty || displayName == generatedName,
              let name = suggestedName else { return }
        displayName = name
        generatedName = name
    }

    /// One tap on a likely kind, offered when the photo did not settle it.
    mutating func chooseSubtype(_ value: String) {
        subtype = value
        editedFields.formUnion([.subtype, .length])
        autoMetadata?.subtype = nil
        autoMetadata?.subtypeAlternatives = nil
        refreshSuggestedName()
    }

    /// "Skirt · Mini · Black". Values come from the form, so the line follows any edit.
    var summaryLine: String {
        let kind = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !kind.isEmpty { parts.append(kind.prefix(1).uppercased() + kind.dropFirst()) }
        else if let category { parts.append(category.displayName) }
        if let length, GarmentLength.applies(category: category, subtype: subtype) { parts.append(length.rawValue.capitalized) }
        if let colorFamily { parts.append(colorFamily.displayName) }
        if let secondaryColor { parts.append(secondaryColor.displayName) }
        return parts.joined(separator: " · ")
    }

    mutating func discardStaleConfidence() {
        if editedFields.contains(.category) || autoMetadata?.category?.value != category {
            autoMetadata?.category = nil
            autoMetadata?.subtypeAlternatives = nil
        }
        if editedFields.contains(.subtype) || !subtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            autoMetadata?.subtypeAlternatives = nil
        }
        if editedFields.contains(.subtype) || autoMetadata?.subtype?.value != subtype { autoMetadata?.subtype = nil }
        if editedFields.contains(.length) || autoMetadata?.length?.value != length { autoMetadata?.length = nil }
        if editedFields.contains(.primaryColor) || autoMetadata?.primaryColor?.value != colorFamily { autoMetadata?.primaryColor = nil }
        if editedFields.contains(.secondaryColor) || autoMetadata?.secondaryColor?.value != secondaryColor { autoMetadata?.secondaryColor = nil }
    }

    func applyAutoMetadata(to item: ClothingItem) {
        item.secondaryColorRaw = secondaryColor != colorFamily ? secondaryColor?.rawValue : nil
        item.lengthRaw = GarmentLength.applies(category: category, subtype: subtype) ? length?.rawValue : nil
        var clean = self
        if item.lengthRaw == nil { clean.length = nil }
        if item.secondaryColorRaw == nil { clean.secondaryColor = nil }
        clean.discardStaleConfidence()
        item.autoMetadataJSON = clean.autoMetadata.flatMap { try? JSONEncoder().encode($0) }
    }
}

extension GarmentMetadataForm {
    var categoryBinding: Binding<GarmentCategory?> {
        Binding(get: { fields.category }, set: { value in
            guard fields.category != value else { return }
            fields.category = value
            fields.editedFields.formUnion([.category, .subtype, .length])
            fields.subtype = ""
            fields.length = nil
            fields.autoMetadata?.category = nil
            fields.autoMetadata?.subtype = nil
            fields.autoMetadata?.length = nil
            fields.autoMetadata?.subtypeAlternatives = nil
            fields.refreshSuggestedName()
        })
    }

    var nameBinding: Binding<String> {
        Binding(get: { fields.displayName }, set: { value in
            guard value != fields.displayName else { return }
            fields.displayName = value
            fields.editedFields.insert(.name)
        })
    }

    var subtypeBinding: Binding<String> {
        Binding(get: { fields.subtype }, set: { value in
            fields.subtype = value
            fields.editedFields.formUnion([.subtype, .length])
            fields.autoMetadata?.subtype = nil
            if !GarmentLength.applies(category: fields.category, subtype: value) {
                fields.length = nil
                fields.autoMetadata?.length = nil
            }
            fields.refreshSuggestedName()
        })
    }

    /// The first thing on the form: what RIG saw, in one line, and nothing about models.
    /// Shown only when the photo actually contributed something.
    @ViewBuilder
    var suggestionSummary: some View {
        if let metadata = fields.autoMetadata,
           metadata.semanticStatus == "suggested" || metadata.primaryColor != nil || metadata.subtypeAlternatives != nil {
            Section {
                if !fields.summaryLine.isEmpty {
                    Text(fields.summaryLine)
                        .font(.headline)
                        .accessibilityLabel("From the photo: \(fields.summaryLine)")
                }
                if let alternatives = metadata.subtypeAlternatives, fields.subtype.isEmpty,
                   metadata.category?.value == fields.category, metadata.category != nil,
                   !fields.editedFields.contains(.subtype) {
                    HStack(spacing: RIGTheme.Spacing.s) {
                        Text("Is it")
                            .foregroundStyle(.secondary)
                        ForEach(alternatives, id: \.self) { kind in
                            Button(kind.prefix(1).uppercased() + kind.dropFirst()) { fields.chooseSubtype(kind) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            } footer: {
                Text("Tap any field below to change it.")
            }
        }
    }

    @ViewBuilder
    var autoMetadataFields: some View {
        Section("More details") {
            Picker("Secondary colour", selection: Binding(
                get: { fields.secondaryColor },
                set: { fields.secondaryColor = $0; fields.editedFields.insert(.secondaryColor); fields.autoMetadata?.secondaryColor = nil }
            )) {
                Text("None").tag(nil as ColorFamily?)
                ForEach(ColorFamily.allCases.filter { $0 != fields.colorFamily }) { family in
                    Text(family.displayName).tag(Optional(family))
                }
            }
            if GarmentLength.applies(category: fields.category, subtype: fields.subtype) {
                Picker("Length", selection: Binding(
                    get: { fields.length },
                    set: {
                        fields.length = $0
                        fields.editedFields.insert(.length)
                        fields.autoMetadata?.length = nil
                        fields.refreshSuggestedName()
                    }
                )) {
                    Text("Not specified").tag(nil as GarmentLength?)
                    ForEach(GarmentLength.allCases, id: \.self) { length in
                        Text(length.rawValue.capitalized).tag(Optional(length))
                    }
                }
            }
        }
    }
}
