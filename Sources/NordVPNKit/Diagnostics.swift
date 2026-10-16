import ApplicationServices
import Foundation

public struct DiagnosticCheck: Encodable, Sendable {
    public let name: String
    public let passed: Bool
    public let message: String
}

public enum Diagnostics {
    public static func localChecks() -> [DiagnosticCheck] {
        let app = NordApp.url
        let version = app.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
        let hasLog = AppLog() != nil
        return [
            DiagnosticCheck(name: "app", passed: app != nil,
                            message: app == nil ? "Install NordVPN for macOS." : "NordVPN installed (version \(version ?? "unknown"))."),
            DiagnosticCheck(name: "profile", passed: !VPNService.all().isEmpty,
                            message: "A VPN profile is required. Open NordVPN and connect once if missing."),
            DiagnosticCheck(name: "accessibility", passed: AXIsProcessTrusted(),
                            message: "Required only for disconnect: enable your terminal in System Settings > Privacy & Security > Accessibility."),
            DiagnosticCheck(name: "log", passed: hasLog,
                            message: "Readable app logs allow connection and server-switch confirmation.")
        ]
    }

    public static func apiCheck() async -> DiagnosticCheck {
        do {
            _ = try await NordAPI().insights()
            return DiagnosticCheck(name: "api", passed: true, message: "NordVPN public API is reachable.")
        } catch {
            return DiagnosticCheck(name: "api", passed: false,
                                   message: "Could not verify the public IP. Check network access to api.nordvpn.com.")
        }
    }
}
