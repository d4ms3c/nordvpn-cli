import Foundation

public struct Country: Codable, Sendable, Equatable {
    public struct City: Codable, Sendable, Equatable {
        public let id: Int
        public let name: String
        public let serverCount: Int
    }

    public let id: Int
    public let name: String
    public let code: String
    public let serverCount: Int
    public let cities: [City]

    /// Whether the name contains `filter` or the code equals it, ignoring case.
    public func matches(_ filter: String) -> Bool {
        let filter = filter.lowercased()
        return name.lowercased().contains(filter) || code.lowercased() == filter
    }
}

/// Server groups by their command-line name, with the identifier the API filters on.
public enum ServerGroup: String, CaseIterable, Sendable {
    case standard, p2p, double, onion, obfuscated, dedicated

    public var identifier: String {
        switch self {
        case .standard: "legacy_standard"
        case .p2p: "legacy_p2p"
        case .double: "legacy_double_vpn"
        case .onion: "legacy_onion_over_vpn"
        case .obfuscated: "legacy_obfuscated_servers"
        case .dedicated: "legacy_dedicated_ip"
        }
    }
}

public struct IPInsights: Codable, Sendable {
    public let ip: String
    public let country: String?
    public let countryCode: String?
    public let city: String?
    public let isp: String?
    public let protected: Bool

    enum CodingKeys: String, CodingKey {
        case ip, country, city, isp, protected
        case countryCode = "country_code"
    }
}

public struct Server: Codable, Sendable {
    public struct Location: Codable, Sendable {
        public struct CountryRef: Codable, Sendable {
            public struct CityRef: Codable, Sendable { public let name: String }
            public let name: String
            public let code: String
            public let city: CityRef?
        }
        public let country: CountryRef
    }

    public struct Group: Codable, Sendable { public let identifier: String }

    public let name: String
    public let hostname: String
    public let station: String
    public let load: Int
    public let locations: [Location]
    public let groups: [Group]

    public var cityName: String? { locations.first?.country.city?.name }
}

public enum NordAPIError: LocalizedError {
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .http(code, path): "NordVPN API returned HTTP \(code) for \(path)"
        }
    }
}

/// Public, unauthenticated endpoints of api.nordvpn.com.
public struct NordAPI: Sendable {
    public static let base = URL(string: "https://api.nordvpn.com")!
    static let countriesTTL: TimeInterval = 24 * 3600

    public init() {}

    public func insights(timeout: TimeInterval = 10) async throws -> IPInsights {
        try JSONDecoder().decode(IPInsights.self, from: await fetch("/v1/helpers/ips/insights", timeout: timeout))
    }

    /// Countries with their cities; cached on disk for a day because the list rarely changes.
    public func countries(refresh: Bool = false) async throws -> [Country] {
        let cache = Self.cacheDirectory.appendingPathComponent("countries.json")
        if !refresh,
           let attrs = try? FileManager.default.attributesOfItem(atPath: cache.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Self.countriesTTL,
           let data = try? Data(contentsOf: cache),
           let countries = try? JSONDecoder().decode([Country].self, from: data) {
            return countries
        }
        let data = try await fetch("/v1/servers/countries")
        let countries = try JSONDecoder().decode([Country].self, from: data)
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cache)
        return countries
    }

    /// Least loaded servers, optionally restricted to a country and a server group (e.g. `legacy_p2p`).
    public func recommendations(countryID: Int?, group: String?, limit: Int) async throws -> [Server] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let countryID {
            query.append(URLQueryItem(name: "filters[country_id]", value: String(countryID)))
        }
        if let group {
            query.append(URLQueryItem(name: "filters[servers_groups][identifier]", value: group))
        }
        return try await get("/v1/servers/recommendations", query: query)
    }

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nordvpn-cli", isDirectory: true)
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await fetch(path, query: query))
    }

    private func fetch(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval = 10) async throws -> Data {
        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NordAPIError.http(status, path) }
        return data
    }
}
