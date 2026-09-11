import SwiftData
import SwiftUI

/// One saved look.
struct LookDetailView: View {
    let look: SavedOutfit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RIGTheme.Spacing.l) {
                VStack(alignment: .leading, spacing: 4) {
                    RIGTheme.kicker(look.source.displayName, size: 11, tracking: 1.1)
                    Text(look.name)
                        .font(.system(size: 28, weight: .medium))
                        .tracking(-0.5)
                }
                .accessibilityElement(children: .combine)

                LookCompositionView(items: look.itemsInDisplayOrder)
                    .padding(RIGTheme.Spacing.l)
                    .background(RIGTheme.cardBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous))
                    .nocturneElevationSmall(radius: RIGTheme.Radius.large)

                if look.hasMissingGarments {
                    Text("Bu kombindeki bazı parçalar artık dolabında değil.")
                        .font(.system(size: 12))
                        .foregroundStyle(RIGTheme.text(55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    RIGErrorBanner(message: errorMessage) {
                        self.errorMessage = nil
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    RIGTheme.kicker("Parçalar", size: 10, tracking: 1.2)
                        .padding(.bottom, 9)

                    ForEach(look.itemsInDisplayOrder) { item in
                        HStack(spacing: RIGTheme.Spacing.m) {
                            Circle()
                                .fill(RIGTheme.swatch(for: item.primaryColor))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(RIGTheme.hairline, lineWidth: 0.5))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.displayName)
                                    .font(.system(size: 14))
                                Text(item.category.displayName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(RIGTheme.text(50))
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)

                        RIGFadingRule()
                    }
                }

                Button("Kombini sil") { isConfirmingDelete = true }
                    .buttonStyle(RIGSecondaryButtonStyle())
                    .padding(.top, RIGTheme.Spacing.s)
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.top, RIGTheme.Spacing.m)
            .padding(.bottom, 120)
        }
        .background(RIGTheme.pageBackground)
        .navigationTitle(look.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Bu kombin silinsin mi?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive, action: delete)
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Parçalar dolabında kalır. Yalnızca kombin silinir.")
        }
    }

    private func delete() {
        modelContext.delete(look)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Bu kombin silinemedi."
        }
    }
}
