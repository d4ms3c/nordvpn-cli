import Foundation

public enum ConnectionOutcome: Equatable, Sendable {
    case verified
    case tunnelUnverified
    case wrongCountry
    case unprotected
    case timedOut
}

public struct ConnectionEvidence {
    public static func outcome(tunnelConnected: Bool, protected: Bool?,
                               expectedCountry: String?, observedCountry: String?) -> ConnectionOutcome {
        guard tunnelConnected else { return .timedOut }
        guard let protected else { return .tunnelUnverified }
        guard protected else { return .unprotected }
        if let expectedCountry,
           observedCountry?.uppercased() != expectedCountry.uppercased() {
            return .wrongCountry
        }
        return .verified
    }
}
