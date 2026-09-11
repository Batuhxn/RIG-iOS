import SwiftData
import SwiftUI

/// "Profil" — the third tab.
///
/// The design's version carries iCloud backup, notifications and an account.
/// RIG has none of those and is not going to pretend otherwise: it stores
/// everything locally, makes no network calls at all, and the static audit
/// fails the build if a networking, cloud or location symbol appears anywhere
/// in the sources. So this screen keeps the design's shape — an identity block,
/// three numbers, a settings list — and fills it only with things RIG can
/// actually do.
///
/// The category breakdown at the bottom is the one piece that moved here from
/// the old home screen, which had nowhere else to go once that tab was removed.
struct ProfileView: View {
    @Query private var items: [ClothingItem]
    @Query private var looks: [SavedOutfit]

    private var favouriteCount: Int { items.filter(\.isFavorite).count }

    private var cutoutCount: Int { items.filter(\.isBackgroundRemoved).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    identity
                    stats
                    breakdown
                    settings
                }
                .padding(.bottom, 120)
            }
            .background(RIGTheme.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Identity

    /// No account, no name, no avatar photograph — RIG has never asked for any
    /// of them. What it can honestly show is the wardrobe itself.
    private var identity: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [RIGTheme.Accent.a700, RIGTheme.Neutral.n900],
                        center: UnitPoint(x: 0.3, y: 0.2),
                        startRadius: 0,
                        endRadius: 62
                    )
                )
                .frame(width: 62, height: 62)
                .overlay(
                    Image(systemName: "tshirt")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(RIGTheme.textPrimary)
                )
                .nocturneElevationSmall(radius: 31)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Dolabın")
                    .font(.system(size: 21, weight: .medium))
                Text("Bu cihazda saklanıyor")
                    .font(.system(size: 12))
                    .foregroundStyle(RIGTheme.text(52))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.top, RIGTheme.Spacing.l)
        .accessibilityElement(children: .combine)
    }

    private var stats: some View {
        HStack(spacing: 10) {
            RIGStatTile(value: "\(items.count)", label: "Parça")
            RIGStatTile(value: "\(looks.count)", label: "Kombin")
            RIGStatTile(value: "\(favouriteCount)", label: "Favori")
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.top, RIGTheme.Spacing.xl)
    }

    // MARK: - Breakdown

    @ViewBuilder
    private var breakdown: some View {
        if !categoriesWithCounts.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                RIGTheme.kicker("Dolabında neler var", size: 10, tracking: 1.2)
                    .padding(.bottom, 2)

                ForEach(categoriesWithCounts, id: \.category) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.category.symbolName)
                            .font(.system(size: 15))
                            .foregroundStyle(RIGTheme.accent)
                            .frame(width: 20)
                        Text(entry.category.displayName)
                            .font(.system(size: 14))
                        Spacer(minLength: 8)
                        Text("\(entry.count)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(RIGTheme.text(70))
                    }
                    .frame(minHeight: 40)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(entry.count) \(entry.category.displayName)")

                    RIGFadingRule()
                }
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.top, RIGTheme.Spacing.xl)
        }
    }

    private var categoriesWithCounts: [(category: GarmentCategory, count: Int)] {
        GarmentCategory.allCases
            .map { category in
                (category: category, count: items.filter { $0.category == category }.count)
            }
            .filter { $0.count > 0 }
            .sorted { $0.category.displayOrder < $1.category.displayOrder }
    }

    // MARK: - Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Dolap ayarları")
                .font(.system(size: 10))
                .tracking(1.2)
                .foregroundStyle(RIGTheme.text(45))
                .textCase(.uppercase)

            VStack(spacing: 7) {
                NavigationLink {
                    StorageDetailView(
                        garmentCount: items.count,
                        cutoutCount: cutoutCount
                    )
                } label: {
                    RIGSettingsRowLabel(symbol: "internaldrive", title: "Depolama ve fotoğraflar")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    PrivacyDetailView()
                } label: {
                    RIGSettingsRowLabel(symbol: "lock", title: "Gizlilik")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AboutDetailView()
                } label: {
                    RIGSettingsRowLabel(symbol: "info.circle", title: "RIG hakkında")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, RIGTheme.Spacing.xl)
        .padding(.top, RIGTheme.Spacing.xl)
    }
}

/// The row's appearance, without the button behaviour — `NavigationLink`
/// supplies that, so the chevron here is decoration rather than a second
/// control.
struct RIGSettingsRowLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(RIGTheme.accent)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(RIGTheme.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(RIGTheme.text(32))
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(RIGTheme.cardBackground, in: RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ProfileView()
        .modelContainer(PreviewData.container())
        .environment(\.rigServices, .preview())
        .nocturneAppearance()
}
