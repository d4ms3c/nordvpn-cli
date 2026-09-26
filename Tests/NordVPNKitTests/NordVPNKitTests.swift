import Testing
@testable import NordVPNKit

private let countries = [
    Country(id: 174, name: "Poland", code: "PL", serverCount: 90,
            cities: [.init(id: 1, name: "Warsaw", serverCount: 90)]),
    Country(id: 227, name: "United Kingdom", code: "GB", serverCount: 400,
            cities: [.init(id: 2, name: "London", serverCount: 300), .init(id: 3, name: "Manchester", serverCount: 100)]),
    Country(id: 228, name: "United States", code: "US", serverCount: 2000,
            cities: [.init(id: 4, name: "New York", serverCount: 300)]),
    Country(id: 209, name: "Switzerland", code: "CH", serverCount: 100,
            cities: [.init(id: 5, name: "Zürich", serverCount: 100)]),
]

@Test(arguments: [("pl", "PL"), ("PL", "PL"), ("uk", "GB"), ("gb", "GB"), ("poland", "PL"),
                  ("United_States", "US"), ("united  states", "US"), ("switz", "CH")])
func resolvesCountries(query: String, code: String) throws {
    #expect(try LocationResolver.resolve(query, in: countries) == .country(countries.first { $0.code == code }!))
}

@Test func resolvesCityToItsCountry() throws {
    let resolved = try LocationResolver.resolve("zurich", in: countries)
    #expect(resolved.country.code == "CH")
    guard case let .city(city, _) = resolved else { Issue.record("expected a city"); return }
    #expect(city.name == "Zürich")
    #expect(try LocationResolver.resolve("new york", in: countries).country.code == "US")
}

@Test func reportsAmbiguousPrefix() {
    #expect(throws: LocationError.ambiguous("united", ["United Kingdom", "United States"])) {
        try LocationResolver.resolve("united", in: countries)
    }
}

@Test func reportsUnknownLocation() {
    #expect(throws: LocationError.notFound("atlantis")) { try LocationResolver.resolve("atlantis", in: countries) }
    #expect(throws: LocationError.notFound("  ")) { try LocationResolver.resolve("  ", in: countries) }
}

@Test func buildsConnectDeepLinks() {
    #expect(NordApp.connectURL(countryCode: nil).absoluteString == "nordvpn://connect")
    #expect(NordApp.connectURL(countryCode: "PL").absoluteString == "nordvpn://connect?country=pl")
}

@Test func parsesAppLogLines() {
    var state: AppLog.State?, server: String?
    let lines = [
        "2026-01-01 12:00:00.000 +0000 1000 [Info] [main] > App state changed to initiating",
        "2026-01-01 12:00:00.100 +0000 1000 [Info] com.apple.root.user-initiated-qos.cooperative > Connecting to the Italy #100",
        "2026-01-01 12:00:00.200 +0000 1000 [Info] process_app_state_queue > AppState changed from [connecting] to [connected]. Reason: [user]",
        "2026-01-01 12:00:00.300 +0000 1000 [Info] [main] > App state changed to connected",
    ]
    for line in lines.prefix(2) { AppLog.parse(line, into: &state, server: &server) }
    #expect(state == .initiating)
    #expect(server == "Italy #100")
    for line in lines.dropFirst(2) { AppLog.parse(line, into: &state, server: &server) }
    #expect(state == .connected)
}
