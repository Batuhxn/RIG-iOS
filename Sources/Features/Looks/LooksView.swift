import SwiftData
import SwiftUI

/// "Kombin" — saved looks, and the way into building one.
///
/// The design puts a single highlighted card at the top of this tab, above the
/// list. In the prototype that card reports the weather. RIG makes no network
/// calls at all — the static audit fails the build if `URLSession` or
/// `CoreLocation` appears anywhere in the sources — so the card keeps its
/// shape and its job (one prominent thing to do next) and fills it with the
/// only thing RIG actually knows: whether the wardrobe can support a
/// suggestion yet.
///
/// That readiness check and the two ways into outfit building are what moved
/// here when the home tab went away.
struct LooksView: View {
    @Query(sort: [SortDescriptor(\SavedOutfit.createdAt, order: .reverse)])
    private var looks: [SavedOutfit]

    @Query private var items: [ClothingItem]

    @State private var isPresentingBuilder = false
    @State private var isPresentingImport = false

    private var readiness: WardrobeReadiness {
        WardrobeReadiness.evaluate(items.map(\.snapshot))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                RIGTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        SuggestionPromptCard(
                            readiness: readiness,
                            onAddGarments: { isPresentingImport = true }
                        )
                        .padding(.horizontal, RIGTheme.Spacing.xl)

                        looksList
                    }
                    .padding(.bottom, 130)
                }

                floatingAction
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isPresentingBuilder) {
                NavigationStack {
                    OutfitBuilderView(presentedAsSheet: true)
                }
            }
            .sheet(isPresented: $isPresentingImport) {
                PhotoImportFlow()
            }
        }
    }

    private var header: some View {
        RIGScreenHeading(
            kicker: "Kombinler",
            title: looks.count == 1 ? "1 kombin" : "\(looks.count) kombin"
        )
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.top, RIGTheme.Spacing.m)
        .padding(.bottom, RIGTheme.Spacing.m)
    }

    @ViewBuilder
    private var looksList: some View {
        if looks.isEmpty {
            RIGEmptyState(
                symbol: "square.stack",
                title: "Henüz kombin yok",
                message: "Bir öneriyi kaydet ya da kendin bir tane kur. Kaydettiğin kombinler bu cihazda kalır."
            )
            .frame(maxWidth: .infinity)
            .padding(.top, RIGTheme.Spacing.xl)
        } else {
            LazyVStack(spacing: 9) {
                ForEach(Array(looks.enumerated()), id: \.element.id) { index, look in
                    NavigationLink {
                        LookDetailView(look: look)
                    } label: {
                        LookRow(look: look)
                    }
                    .buttonStyle(.plain)
                    .modifier(RisingItem(index: index))
                }
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.top, RIGTheme.Spacing.l)
        }
    }

    private var floatingAction: some View {
        ZStack(alignment: .bottom) {
            RIGBottomScrim()
            Button {
                isPresentingBuilder = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Kombin oluştur")
                }
            }
            .buttonStyle(RIGPillButtonStyle())
            .padding(.bottom, RIGTheme.Spacing.xl)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

/// The design's highlighted card at the top of the tab.
///
/// Two states, both honest. When the wardrobe can support a suggestion it
/// offers one; when it cannot it says exactly what is missing, in the words
/// `WardrobeReadiness` already produces, and offers the thing that would fix
/// it. There is no third state where it implies a personalisation RIG does
/// not do.
struct SuggestionPromptCard: View {
    let readiness: WardrobeReadiness
    let onAddGarments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                RIGTheme.kicker(readiness.canSuggest ? "Bugün için" : "Henüz hazır değil", size: 11, tracking: 1.1)
            }
            .foregroundStyle(RIGTheme.Accent.a300)

            Text(headline)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(RIGTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            HStack(spacing: 8) {
                if readiness.canSuggest {
                    NavigationLink {
                        SuggestionsView()
                    } label: {
                        Text("Kombin öner")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(RIGTheme.accent)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .overlay(Capsule().strokeBorder(RIGTheme.accent, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        OutfitBuilderView()
                    } label: {
                        Text("Kendin kur")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(RIGTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .overlay(Capsule().strokeBorder(RIGTheme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onAddGarments) {
                        Text("Parça ekle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(RIGTheme.accent)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .overlay(Capsule().strokeBorder(RIGTheme.accent, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.large, style: .continuous))
        .nocturneElevationSmall(radius: RIGTheme.Radius.large)
    }

    private var headline: String {
        readiness.canSuggest
            ? "Dolabındaki parçalardan bir kombin kuralım"
            : readiness.explanation
    }

    /// The design's one permitted saturated field: a diagonal accent wash into
    /// the surface, with a bloom from the top right.
    private var cardBackground: some View {
        ZStack {
            LinearGradient(
                colors: [RIGTheme.Accent.a900, RIGTheme.cardBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [RIGTheme.Accent.a800.opacity(0.8), .clear],
                center: UnitPoint(x: 0.88, y: -0.1),
                startRadius: 0,
                endRadius: 240
            )
        }
    }
}

#Preview {
    LooksView()
        .modelContainer(PreviewData.container())
        .environment(\.rigServices, .preview())
        .nocturneAppearance()
}
