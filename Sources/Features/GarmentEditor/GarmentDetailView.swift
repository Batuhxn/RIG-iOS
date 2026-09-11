import SwiftData
import SwiftUI

/// One garment, full screen.
///
/// The design gives this screen a tall hero that the content rises into: the
/// photograph fills the top 430pt, a gradient takes it down into the ground,
/// and the title block overlaps the bottom of it. The effect is that the
/// garment is the page rather than an illustration on it.
struct GarmentDetailView: View {
    let item: ClothingItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.rigServices) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var isPresentingEditor = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                details
            }
        }
        .background(RIGTheme.pageBackground)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { heroControls }
        .sheet(isPresented: $isPresentingEditor) {
            GarmentEditorView(item: item)
        }
        .confirmationDialog(
            "Bu parça silinsin mi?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive, action: delete)
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Fotoğrafları bu cihazdan kaldırılır. Onu kullanan kombinlerde bir parçanın eksik olduğu yazar.")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottom) {
            RadialGradient(
                colors: [RIGTheme.Neutral.n700, RIGTheme.Neutral.n900],
                center: UnitPoint(x: 0.5, y: 0.18),
                startRadius: 0,
                endRadius: 340
            )

            GarmentImageView(
                relativePath: item.preferredImageRelativePath,
                symbolName: item.category.symbolName
            )
            .padding(.horizontal, 44)
            .padding(.top, 72)
            .padding(.bottom, 40)

            LinearGradient(
                stops: [
                    .init(color: RIGTheme.pageBackground, location: 0),
                    .init(color: .clear, location: 0.48)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .allowsHitTesting(false)
        }
        .frame(height: 430)
        .clipped()
    }

    private var heroControls: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.left")
            }
            .buttonStyle(RIGIconButtonStyle(background: Color(nocturne: 0x05060C).opacity(0.45)))
            .accessibilityLabel("Geri")

            Spacer(minLength: 0)

            Button {
                toggleFavorite()
            } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
            }
            .buttonStyle(RIGIconButtonStyle(background: Color(nocturne: 0x05060C).opacity(0.45)))
            .accessibilityLabel(item.isFavorite ? "Favorilerden çıkar" : "Favorilere ekle")

            Button {
                isPresentingEditor = true
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(RIGIconButtonStyle(background: Color(nocturne: 0x05060C).opacity(0.45)))
            .accessibilityLabel("Düzenle")
        }
        .padding(.horizontal, RIGTheme.Spacing.l)
        .padding(.top, RIGTheme.Spacing.s)
    }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                RIGTheme.kicker(item.category.displayName, size: 11, tracking: 1.1)
                Text(item.displayName)
                    .font(.system(size: 28, weight: .medium))
                    .tracking(-0.5)
            }
            .accessibilityElement(children: .combine)

            tags

            if !item.isBackgroundRemoved {
                Text("RIG bu parçayı ayıramadı, bu yüzden orijinal fotoğraf kullanılıyor.")
                    .font(.system(size: 12))
                    .foregroundStyle(RIGTheme.text(55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                RIGErrorBanner(message: errorMessage) {
                    self.errorMessage = nil
                }
            }

            metaRows

            if !item.notes.isEmpty {
                VStack(alignment: .leading, spacing: RIGTheme.Spacing.xs) {
                    RIGSectionHeader(title: "Notlar")
                    Text(item.notes)
                        .font(.system(size: 14))
                }
                .padding(.top, RIGTheme.Spacing.s)
            }

            Button("Düzenle") { isPresentingEditor = true }
                .buttonStyle(RIGSecondaryButtonStyle())
                .padding(.top, RIGTheme.Spacing.s)

            Button("Parçayı sil") { isConfirmingDelete = true }
                .buttonStyle(RIGQuietButtonStyle())
                .foregroundStyle(RIGTheme.Neutral.n400)
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.bottom, 120)
        // Lifts the title block into the bottom of the hero, as the design does.
        .padding(.top, -34)
    }

    private var tags: some View {
        FlowLayout(spacing: 7) {
            RIGTag(text: item.primaryColor.displayName)
            ForEach(item.seasons.normalized.seasons) { season in
                RIGTag(text: season.displayName)
            }
            if !item.subtype.isEmpty {
                RIGTag(text: item.subtype)
            }
            if item.isFavorite {
                RIGTag(text: "Favori", kind: .outline)
            }
        }
    }

    private var metaRows: some View {
        VStack(spacing: 0) {
            DetailRow(label: "Kategori", value: item.category.displayName)
            DetailRow(label: "Renk", value: item.primaryColor.displayName, swatch: item.primaryColor)
            DetailRow(label: "Sezon", value: item.seasons.displayName)
            DetailRow(label: "Kaynak", value: item.isBackgroundRemoved ? "Fotoğraf · arka plan kaldırıldı" : "Fotoğraf")
        }
    }

    // MARK: - Actions

    private func toggleFavorite() {
        item.isFavorite.toggle()
        item.touch()
        save()
    }

    /// Row first, then files. If the file sweep fails the orphan pass on next
    /// launch collects it; the reverse order could leave a garment pointing at
    /// images that no longer exist.
    private func delete() {
        let id = item.id
        modelContext.delete(item)
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Bu parça silinemedi. Hiçbir şey değişmedi."
            return
        }
        try? services.imageStore.removeAll(for: id)
        dismiss()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Bu değişiklik kaydedilemedi."
        }
    }
}

/// One line of the meta list: a dimmed label, a value, and a rule beneath that
/// fades out at both ends.
struct DetailRow: View {
    let label: String
    let value: String
    var swatch: ColorFamily? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .foregroundStyle(RIGTheme.text(55))
                Spacer(minLength: 8)
                if let swatch {
                    Circle()
                        .fill(RIGTheme.swatch(for: swatch))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(RIGTheme.hairline, lineWidth: 0.5))
                        .accessibilityHidden(true)
                }
                Text(value)
                    .foregroundStyle(RIGTheme.textPrimary)
            }
            .font(.system(size: 13))
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)

            RIGFadingRule()
        }
    }
}
