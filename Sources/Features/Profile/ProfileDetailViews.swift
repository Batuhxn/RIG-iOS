import SwiftUI

/// The three settings destinations.
///
/// Each one is a statement of what RIG actually does, because each replaces a
/// row in the design that promised something RIG does not have. They are read
/// -only on purpose: there is no switch here that would do nothing.

struct StorageDetailView: View {
    let garmentCount: Int
    let cutoutCount: Int

    var body: some View {
        SettingsScaffold(title: "Depolama ve fotoğraflar") {
            SettingsParagraph(
                "Her parçanın fotoğrafları, bu cihazdaki uygulama klasöründe kendi dizininde tutulur. Veritabanı yalnızca dosya yollarını saklar."
            )

            SettingsFacts([
                ("Parça", "\(garmentCount)"),
                ("Arka planı kaldırılan", "\(cutoutCount)"),
                ("Saklanan boyutlar", "1600 · 1200 · 400 px")
            ])

            SettingsParagraph(
                "Orijinal 1600 pikselde tutulur; bu, bir parçayı ileride daha iyi bir arka plan kaldırıcıyla yeniden işlemek için yeterli. Bir parçayı sildiğinde fotoğrafları da silinir."
            )
        }
    }
}

struct PrivacyDetailView: View {
    var body: some View {
        SettingsScaffold(title: "Gizlilik") {
            SettingsParagraph(
                "RIG hiçbir ağ isteği yapmaz. Yükleme yok, hesap yok, analitik yok, çökme raporu yok."
            )

            SettingsParagraph(
                "Bu bir vaat değil, yapının kendisi: projede ağ, bulut, analitik veya konum sembolü geçerse statik denetim derlemeyi düşürür. Fotoğraf seçici de kütüphane izni istemeden, yalnızca seçtiğin fotoğrafın baytlarını verir."
            )

            SettingsParagraph(
                "Arka plan kaldırma tamamen cihazda, Vision ile çalışır."
            )
        }
    }
}

struct AboutDetailView: View {
    var body: some View {
        SettingsScaffold(title: "RIG hakkında") {
            SettingsParagraph(
                "RIG, sahip olduğun kıyafetleri tutan ve onlardan kombin öneren yerel bir dolap uygulamasıdır."
            )

            SettingsParagraph(
                "Öneriler açık kurallarla sıralanır. Arkada kalibre edilmiş bir olasılık olmadığı için sonuçlar yüzde değil, kelimeyle gösterilir — \"Güçlü uyum\", \"%92\" değil."
            )
        }
    }
}

// MARK: - Shared chrome

struct SettingsScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RIGTheme.Spacing.l) {
                content
            }
            .padding(.horizontal, RIGTheme.Spacing.xl)
            .padding(.top, RIGTheme.Spacing.l)
            .padding(.bottom, 120)
        }
        .background(RIGTheme.pageBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsParagraph: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(RIGTheme.text(72))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsFacts: View {
    let rows: [(String, String)]

    init(_ rows: [(String, String)]) {
        self.rows = rows
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .foregroundStyle(RIGTheme.text(55))
                    Spacer(minLength: 8)
                    Text(row.1)
                }
                .font(.system(size: 13))
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)

                RIGFadingRule()
            }
        }
    }
}
