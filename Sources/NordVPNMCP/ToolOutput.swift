import Foundation
import NordVPNKit

/// One page of `nordvpn_list_countries`.
struct CountryPage: Encodable {
    let total: Int
    let count: Int
    let offset: Int
    let countries: [Country]
    let hasMore: Bool
    let nextOffset: Int?

    enum CodingKeys: String, CodingKey {
        case total, count, offset, countries
        case hasMore = "has_more"
        case nextOffset = "next_offset"
    }

    init(countries: [Country], total: Int, offset: Int) {
        let end = offset + countries.count
        self.total = total
        self.count = countries.count
        self.offset = offset
        self.countries = countries
        self.hasMore = total > end
        self.nextOffset = total > end ? end : nil
    }

    /// Halves the page until its text fits the character limit, so next_offset points at the first country left out.
    static func fitting(_ countries: [Country], of total: Int, offset: Int, asJSON: Bool) throws -> CountryPage {
        var page = CountryPage(countries: countries, total: total, offset: offset)
        while page.count > 1, try page.rendered(asJSON: asJSON).count > NordVPNTools.characterLimit {
            page = CountryPage(countries: Array(page.countries.prefix((page.count + 1) / 2)), total: total, offset: offset)
        }
        return page
    }

    func rendered(asJSON: Bool) throws -> String {
        if asJSON { return String(decoding: try JSONValue(encoding: self).encoded(pretty: true), as: UTF8.self) }
        var lines = ["# NordVPN countries", "Showing \(count) of \(total).", ""] + countries.map(Self.line)
        if let nextOffset { lines += ["", "More results: call again with offset=\(nextOffset)."] }
        return lines.joined(separator: "\n")
    }

    private static func line(for country: Country) -> String {
        let cities = country.cities.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let cityList = cities.isEmpty ? "none listed" : cities.joined(separator: ", ")
        return "- **\(country.code)** \(country.name): \(country.serverCount) servers; cities: \(cityList)"
    }
}

/// A server without the API fields an agent has no use for.
struct CompactServer: Encodable {
    let name: String
    let hostname: String
    let load: Int
    let country: String?
    let countryCode: String?
    let city: String?
    let groups: [String]

    enum CodingKeys: String, CodingKey {
        case name, hostname, load, country, city, groups
        case countryCode = "country_code"
    }

    init(_ server: Server) {
        let location = server.locations.first?.country
        name = server.name
        hostname = server.hostname
        load = server.load
        country = location?.name
        countryCode = location?.code
        city = location?.city?.name
        groups = server.groups.map(\.identifier)
    }
}

struct ServerList: Encodable {
    let count: Int
    let servers: [CompactServer]
}

struct DoctorReport: Encodable {
    let allPassed: Bool
    let checks: [DiagnosticCheck]

    enum CodingKeys: String, CodingKey {
        case allPassed = "all_passed"
        case checks
    }
}

/// Schemas of the tools that return structured content on every call.
enum OutputSchemas {
    static let status: JSONValue = [
        "type": "object",
        "properties": [
            "vpn": [
                "type": "object",
                "description": "Absent when the app has no VPN profile",
                "properties": [
                    "serviceID": ["type": "string"],
                    "name": ["type": "string"],
                    "state": ["type": "string", "enum": ["invalid", "disconnected", "connecting", "connected", "disconnecting"]],
                    "interface": ["type": "string"],
                    "tunnelAddress": ["type": "string"],
                    "since": ["type": "string", "format": "date-time"],
                    "onDemand": ["type": "boolean"],
                ],
                "required": ["serviceID", "name", "state", "onDemand"],
            ],
            "server": ["type": "string", "description": "Server name, only while connected"],
            "lastTarget": ["type": "string", "description": "Target of the app's last connection, e.g. country:pl:-:-:-"],
            "publicIP": [
                "type": "object",
                "description": "Absent when NordVPN's API could not be reached",
                "properties": [
                    "ip": ["type": "string"],
                    "country": ["type": "string"],
                    "country_code": ["type": "string"],
                    "city": ["type": "string"],
                    "isp": ["type": "string"],
                    "protected": ["type": "boolean"],
                ],
                "required": ["ip", "protected"],
            ],
        ],
    ]

    static let doctor: JSONValue = [
        "type": "object",
        "properties": [
            "all_passed": ["type": "boolean"],
            "checks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": ["name": ["type": "string"], "passed": ["type": "boolean"], "message": ["type": "string"]],
                    "required": ["name", "passed", "message"],
                ],
            ],
        ],
        "required": ["all_passed", "checks"],
    ]
}
