// Stand-in for the nordvpn CLI: answers like version 0.2.0 and records its arguments, without touching the VPN.
import { appendFileSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";

const args = process.argv.slice(2);
const log = entry => process.env.FAKE_NORDVPN_LOG && appendFileSync(process.env.FAKE_NORDVPN_LOG, `${JSON.stringify(entry)}\n`);
const print = value => process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
const positional = () => (args.includes("--") ? args.slice(args.indexOf("--") + 1) : []);

function fail(message, code = 1) {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(code);
}

const countries = [
  { id: 106, name: "Italy", code: "IT", serverCount: 64, cities: [{ id: 1, name: "Rome", serverCount: 20 }, { id: 2, name: "Milan", serverCount: 44 }] },
  { id: 81, name: "Germany", code: "DE", serverCount: 300, cities: [{ id: 3, name: "Frankfurt", serverCount: 200 }, { id: 4, name: "Berlin", serverCount: 100 }] },
  { id: 227, name: "United Kingdom", code: "GB", serverCount: 400, cities: [{ id: 5, name: "London", serverCount: 400 }] }
];

const server = index => ({
  name: `Italy #${450 + index}`,
  hostname: `it${450 + index}.nordvpn.com`,
  station: "198.51.100.1",
  load: 5 + index,
  locations: [{ country: { name: "Italy", code: "IT", city: { name: "Milan" } } }],
  groups: [{ identifier: "legacy_standard" }, { identifier: "legacy_p2p" }]
});

log(args);
switch (args[0]) {
  case "--version":
    console.log(process.env.FAKE_NORDVPN_VERSION ?? "0.2.0");
    break;
  case "status":
    print({
      vpn: { serviceID: "ABC", name: "NordLynx", state: "connected", interface: "utun4", since: "2026-10-16T12:00:00Z", onDemand: true, futureField: 1 },
      server: "Italy #456",
      publicIP: { ip: "192.0.2.10", country: "Italy", country_code: "IT", city: "Milan", isp: "Example ISP", protected: true }
    });
    break;
  case "countries": {
    const filter = positional()[0]?.toLowerCase();
    print(filter ? countries.filter(c => c.name.toLowerCase().includes(filter) || c.code.toLowerCase() === filter) : countries);
    break;
  }
  case "servers": {
    const limit = Number(args[args.indexOf("--limit") + 1]);
    print(Array.from({ length: limit }, (_, index) => server(index)));
    break;
  }
  case "doctor":
    print([
      { name: "app", passed: true, message: "NordVPN installed (version 10.12.0)." },
      { name: "accessibility", passed: false, message: "Required only for disconnect." }
    ]);
    process.exitCode = 1;
    break;
  case "connect": {
    const place = positional().join(" ");
    if (place === "atlantis") fail('No country or city matches "atlantis". Run `nordvpn countries` to see the list.');
    await sleep(Number(process.env.FAKE_NORDVPN_DELAY_MS ?? 0));
    if (place === "rome") process.stderr.write("The app cannot pick a city: connecting to the fastest server in Italy, not specifically Rome.\n");
    console.log(`Connecting to ${place ? "Italy" : "the fastest server"}…`);
    if (!args.includes("--no-wait")) console.log("Connected to Italy #456 · 192.0.2.10");
    log(["done", "connect"]);
    break;
  }
  case "disconnect":
    if (process.env.FAKE_NORDVPN_ACCESSIBILITY === "denied") {
      fail('The app has no deep link for disconnecting, so the CLI clicks "Disconnect" in its menu and needs Accessibility access for your terminal.');
    }
    console.log("Disconnected");
    log(["done", "disconnect"]);
    break;
  default:
    fail(`Unexpected arguments: ${args.join(" ")}`, 64);
}
