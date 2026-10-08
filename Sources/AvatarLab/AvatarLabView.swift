import SwiftData
import SwiftUI
import UIKit

/// RiG Avatar Lab (experimental): a body silhouette the user shapes, wearing
/// garments from their own wardrobe. Everything stays on the device.
struct AvatarLabView: View {
    @Environment(\.rigServices) private var services
    @Query(sort: [SortDescriptor(\ClothingItem.createdAt, order: .reverse)])
    private var items: [ClothingItem]

    @State private var model: AvatarLabModel?
    @State private var isOnboarding = false
    @State private var section: Section = .body
    @State private var isConfirmingDelete = false

    private enum Section: String, CaseIterable, Identifiable {
        case body = "Body"
        case outfit = "Outfit"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    switch model.phase {
                    case .loading:
                        ProgressView("Preparing your avatar…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case let .failed(message):
                        RIGEmptyState(symbol: "exclamationmark.triangle", title: "Avatar unavailable", message: message)
                    case .ready:
                        if isOnboarding {
                            AvatarOnboardingView(model: model) { isOnboarding = false }
                        } else {
                            editor(model)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .background(RIGTheme.pageBackground)
            .navigationTitle("Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let model, model.phase == .ready, !isOnboarding {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Save avatar", systemImage: "square.and.arrow.down") { model.saveProfile() }
                            Button("Start over", systemImage: "arrow.counterclockwise") {
                                model.resetBody()
                                isOnboarding = true
                            }
                            Button("Delete avatar", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                        } label: {
                            Label("Avatar options", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Delete your avatar?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete avatar", role: .destructive) {
                    model?.deleteProfile()
                    isOnboarding = true
                }
            } message: {
                Text("This removes the body shape and saved outfits from this device. Your wardrobe is not affected.")
            }
        }
        .task {
            if model == nil {
                let created = AvatarLabModel(store: try? AvatarProfileStore.applicationSupport(), imageStore: services.imageStore)
                model = created
                await created.load()
                isOnboarding = !created.hasSavedProfile
            }
        }
    }

    @ViewBuilder
    private func editor(_ model: AvatarLabModel) -> some View {
        VStack(spacing: 0) {
            AvatarStage(model: model)
                .frame(maxWidth: .infinity)
                .frame(height: 380)
            Picker("Preview", selection: Binding(get: { model.mode }, set: { model.mode = $0 })) {
                ForEach(AvatarPreviewMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, RIGTheme.Spacing.m)
            Text(model.mode == .flat2D
                 ? "Approximate preview, not a size or fit guide."
                 : "Experimental 3D: garments are stretched at the sides and do not drape. Not a fit guide.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, RIGTheme.Spacing.s)
            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(RIGTheme.Spacing.m)
            ScrollView {
                switch section {
                case .body: AvatarBodyControls(model: model)
                case .outfit: AvatarOutfitPicker(model: model, items: items)
                }
            }
        }
    }
}

/// The 3D stage, or in 2D mode the front view with garment photos laid over it.
private struct AvatarStage: View {
    let model: AvatarLabModel

    var body: some View {
        GeometryReader { proxy in
            let projection = AvatarFrontProjection(viewWidth: proxy.size.width, viewHeight: proxy.size.height, visibleHeight: 1.95, centreY: 0.9)
            ZStack(alignment: .topLeading) {
                AvatarStageView(content: model.content, mode: model.mode, flatProjection: model.mode == .flat2D ? projection : nil)
                if model.mode == .flat2D, let content = model.content {
                    ForEach(content.garments) { layer in
                        if let photo = layer.photo, let bands = projection.warpBands(for: layer.mesh) {
                            AvatarWarpedPhoto(photo: photo, bands: bands, size: proxy.size)
                        }
                    }
                }
                if model.content == nil {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Avatar preview")
        .accessibilityHint(model.mode == .flat2D ? "Front view" : "Drag to turn the avatar")
    }
}

private struct AvatarBodyControls: View {
    let model: AvatarLabModel
    @State private var showsRefinements = false

    var body: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.m) {
            ForEach(AvatarControl.primary, id: \.self) { slider($0) }
            DisclosureGroup("Refine", isExpanded: $showsRefinements) {
                VStack(spacing: RIGTheme.Spacing.m) {
                    ForEach(AvatarControl.refinements, id: \.self) { slider($0) }
                }
                .padding(.top, RIGTheme.Spacing.s)
            }
            Button("Back to the starting shape", systemImage: "arrow.uturn.backward") { model.resetBody() }
                .font(.subheadline)
            Text("No measurements needed. Your avatar is stored only on this phone, and you can change or delete it at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, RIGTheme.Spacing.m)
        .padding(.bottom, RIGTheme.Spacing.l)
    }

    private func slider(_ control: AvatarControl) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(control.title).font(.subheadline.weight(.medium))
            HStack {
                Text(control.endLabels.low).font(.caption2).foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.profile.shape[control] }, set: { model.setValue($0, for: control) }),
                       in: control.range)
                    .accessibilityLabel(control.title)
                Text(control.endLabels.high).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AvatarOutfitPicker: View {
    let model: AvatarLabModel
    let items: [ClothingItem]

    var body: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.l) {
            ForEach(AvatarSlot.allCases) { slot in
                let choices = items.filter { slot.categories.contains($0.category) }
                VStack(alignment: .leading, spacing: RIGTheme.Spacing.s) {
                    Text(slot.title).font(.subheadline.weight(.medium))
                    if choices.isEmpty {
                        Text("Nothing in your wardrobe for this yet.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: RIGTheme.Spacing.s) {
                                chip(selected: model.worn[slot] == nil) {
                                    Image(systemName: "xmark").frame(width: 64, height: 64)
                                } action: { model.wear(nil, in: slot) }
                                    .accessibilityLabel("No \(slot.title.lowercased())")
                                ForEach(choices) { item in
                                    chip(selected: model.worn[slot]?.id == item.id) {
                                        GarmentImageView(relativePath: item.displayImageRelativePath, symbolName: item.category.symbolName)
                                            .frame(width: 64, height: 64)
                                    } action: { model.wear(item, in: slot) }
                                        .accessibilityLabel(item.displayName)
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Button("Save outfit", systemImage: "heart") { model.saveCurrentOutfit() }
                    .disabled(model.worn.isEmpty)
            }
            if !model.profile.savedOutfits.isEmpty {
                Text("Saved on the avatar").font(.subheadline.weight(.medium))
                ForEach(Array(model.profile.savedOutfits.enumerated()), id: \.offset) { index, outfit in
                    HStack {
                        Button("Outfit \(index + 1)") { model.restore(outfit, from: items) }
                        Spacer()
                        Button(role: .destructive) { model.removeSavedOutfit(outfit) } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove outfit \(index + 1)")
                    }
                }
            }
            Text("Garments are drawn from their photos on a simple body-hugging shape. Fit, size and drape are not simulated.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, RIGTheme.Spacing.m)
        .padding(.bottom, RIGTheme.Spacing.l)
    }

    private func chip<Label: View>(selected: Bool, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .background(RIGTheme.pageBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// First run: "Make it feel like you." Pick a starting silhouette, then adjust.
private struct AvatarOnboardingView: View {
    let model: AvatarLabModel
    let onDone: () -> Void
    @State private var selected = AvatarStartingSilhouette.all[0].id

    var body: some View {
        VStack(spacing: RIGTheme.Spacing.m) {
            VStack(spacing: RIGTheme.Spacing.s) {
                Text("Make it feel like you").font(.title2.weight(.semibold))
                Text("Pick a starting point. You can adjust every part afterwards, and nothing here leaves your phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            AvatarStage(model: model).frame(height: 300)
            HStack(spacing: RIGTheme.Spacing.m) {
                ForEach(AvatarStartingSilhouette.all) { silhouette in
                    Button {
                        selected = silhouette.id
                    } label: {
                        VStack(spacing: RIGTheme.Spacing.xs) {
                            Group {
                                if let preview = model.silhouettePreviews[silhouette.id] {
                                    Image(uiImage: preview).resizable().scaledToFit()
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(width: 70, height: 120)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(selected == silhouette.id ? Color.accentColor : Color.secondary.opacity(0.3),
                                        lineWidth: selected == silhouette.id ? 3 : 1))
                            Text(silhouette.title).font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(silhouette.title)
                    .accessibilityAddTraits(selected == silhouette.id ? .isSelected : [])
                }
            }
            .onChange(of: selected, initial: true) { _, id in
                if let silhouette = AvatarStartingSilhouette.all.first(where: { $0.id == id }) {
                    model.applyStartingSilhouette(silhouette)
                }
            }
            Button {
                model.saveProfile()
                onDone()
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, RIGTheme.Spacing.m)
            Spacer(minLength: 0)
        }
        .padding(.top, RIGTheme.Spacing.m)
    }
}

/// The 2D overlay: a garment photo drawn strip by strip into `bands`, so it
/// follows the avatar's outline while keeping the photo's own pixels.
private struct AvatarWarpedPhoto: View {
    let photo: UIImage
    let bands: [CGRect]
    let size: CGSize

    var body: some View {
        Image(uiImage: UIGraphicsImageRenderer(size: size).image { _ in
            AvatarGarmentTexture.drawWarped(photo, into: bands)
        })
        .allowsHitTesting(false)
    }
}
