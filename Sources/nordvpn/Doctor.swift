import ArgumentParser
import Foundation
import NordVPNKit

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check installation, permissions, logs and API access without changing the VPN.",
        discussion: "The report omits IP addresses, server names, account details and local paths. Exit status is 1 if any check fails."
    )

    @Flag(help: "Print a shareable JSON diagnostic report.") var json = false
    @Flag(help: "Skip the network check.") var offline = false

    func run() async throws {
        let checks = await Diagnostics.run(offline: offline)
        if json {
            try printJSON(checks)
        } else {
            for check in checks {
                let label = check.passed ? Style.green("PASS") : Style.yellow("CHECK")
                print("\(label)  \(check.name): \(check.message)")
            }
        }
        if checks.contains(where: { !$0.passed }) { throw ExitCode.failure }
    }
}
