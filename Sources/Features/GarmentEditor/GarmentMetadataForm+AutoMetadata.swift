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
    }

    mutating func discardStaleConfidence() {
        if editedFields.contains(.category) || autoMetadata?.category?.value != category { autoMetadata?.category = nil }
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
        })
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
                    set: { fields.length = $0; fields.editedFields.insert(.length); fields.autoMetadata?.length = nil }
                )) {
                    Text("Not specified").tag(nil as GarmentLength?)
                    ForEach(GarmentLength.allCases, id: \.self) { length in
                        Text(length.rawValue.capitalized).tag(Optional(length))
                    }
                }
            }
        }
        if let metadata = fields.autoMetadata {
            Section("Photo suggestions") {
                if let category = metadata.category { Text("Suggested category: \(category.value.displayName)") }
                if let subtype = metadata.subtype { Text("Suggested kind: \(subtype.value)") }
                if let length = metadata.length { Text("Suggested length: \(length.value.rawValue.capitalized)") }
                if let color = metadata.primaryColor { Text("Suggested colour: \(color.value.displayName)") }
                if let color = metadata.secondaryColor { Text("Suggested secondary colour: \(color.value.displayName)") }
                if metadata.semanticStatus == "unavailable" {
                    Text("Choose the category and kind yourself for this photo.")
                } else if metadata.category == nil || metadata.subtype == nil {
                    Text("Some details could not be identified confidently. Please check the form.")
                }
                Text("Suggestions can be wrong. You can change every field before saving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
