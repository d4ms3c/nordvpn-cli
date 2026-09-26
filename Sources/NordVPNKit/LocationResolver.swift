import Foundation

/// Where a user-typed location ends up. The app's deep link only accepts a country,
/// so a city resolves to its country and the caller is told about it.
public enum ResolvedLocation: Equatable, Sendable {
    case country(Country)
    case city(Country.City, in: Country)

    public var country: Country {
        switch self {
        case let .country(country), let .city(_, country): country
        }
    }
}

public enum LocationError: LocalizedError, Equatable {
    case notFound(String)
    case ambiguous(String, [String])

    public var errorDescription: String? {
        switch self {
        case let .notFound(query):
            "No country or city matches \"\(query)\". Run `nordvpn countries` to see the list."
        case let .ambiguous(query, candidates):
            "\"\(query)\" is ambiguous: \(candidates.prefix(8).joined(separator: ", "))."
        }
    }
}

public enum LocationResolver {
    /// Accepts an ISO code (`pl`, `uk`), a country name (`united states`, `United_States`)
    /// or a city name (`warsaw`), with unique prefixes allowed (`switz`).
    public static func resolve(_ query: String, in countries: [Country]) throws -> ResolvedLocation {
        let key = normalize(query)
        guard !key.isEmpty else { throw LocationError.notFound(query) }

        let aliases = ["uk": "gb"]
        let code = aliases[key] ?? key
        if code.count == 2, let country = countries.first(where: { $0.code.lowercased() == code }) {
            return .country(country)
        }
        if let country = countries.first(where: { normalize($0.name) == key }) {
            return .country(country)
        }
        let cities = countries.flatMap { country in country.cities.map { (city: $0, country: country) } }
        if let match = cities.first(where: { normalize($0.city.name) == key }) {
            return .city(match.city, in: match.country)
        }

        let countryHits = countries.filter { normalize($0.name).hasPrefix(key) }
        let cityHits = cities.filter { normalize($0.city.name).hasPrefix(key) }
        switch (countryHits.count, cityHits.count) {
        case (1, 0): return .country(countryHits[0])
        case (0, 1): return .city(cityHits[0].city, in: cityHits[0].country)
        case (0, 0): throw LocationError.notFound(query)
        default:
            let names = countryHits.map(\.name) + cityHits.map { "\($0.city.name) (\($0.country.code))" }
            throw LocationError.ambiguous(query, names)
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
