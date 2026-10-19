import Foundation

/// A place the user picked by hand.
///
/// RIG asks for no location permission. The forecast is for a city the user
/// chose from a short list, so the only thing that leaves the device is that
/// city's public coordinates, rounded to two decimals (about a kilometre).
struct WeatherCity: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    /// A short, deliberately incomplete starting list. Adding a city is a
    /// one-line change; free-text search would need the geocoding API and is
    /// out of scope for the first weather pass.
    static let presets: [WeatherCity] = [
        WeatherCity(id: "istanbul", name: "İstanbul", latitude: 41.01, longitude: 28.98),
        WeatherCity(id: "ankara", name: "Ankara", latitude: 39.93, longitude: 32.86),
        WeatherCity(id: "izmir", name: "İzmir", latitude: 38.42, longitude: 27.14),
        WeatherCity(id: "bursa", name: "Bursa", latitude: 40.19, longitude: 29.06),
        WeatherCity(id: "antalya", name: "Antalya", latitude: 36.90, longitude: 30.70),
        WeatherCity(id: "eskisehir", name: "Eskişehir", latitude: 39.78, longitude: 30.52),
        WeatherCity(id: "trabzon", name: "Trabzon", latitude: 41.00, longitude: 39.72),
        WeatherCity(id: "erzurum", name: "Erzurum", latitude: 39.90, longitude: 41.27)
    ]

    static func preset(id: String) -> WeatherCity? {
        presets.first { $0.id == id }
    }
}
