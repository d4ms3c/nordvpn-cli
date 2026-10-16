import { McpServer } from "@modelcontextprotocol/server";
import * as z from "zod/v4";
import { CliError, errorText, parseJson, runCli, type CliResult } from "./cli.js";

export const SERVER_VERSION = "0.1.0";
const CHARACTER_LIMIT = 25_000;
/** Codex and other clients stop waiting for a tool after 60 seconds by default. */
const MAX_WAIT_SECONDS = 55;

const READ_ONLY = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true } as const;
const CHANGES_NETWORK = { readOnlyHint: false, destructiveHint: true, openWorldHint: true } as const;
const NEXT_STEPS = "Next: call nordvpn_get_status to see the current state, or nordvpn_run_doctor to diagnose the setup.";
const LOCATION_HINT = "nordvpn_list_countries lists valid locations.";

enum ResponseFormat {
  MARKDOWN = "markdown",
  JSON = "json"
}

const responseFormatSchema = z
  .enum(ResponseFormat)
  .default(ResponseFormat.MARKDOWN)
  .describe("'markdown' for readable text, 'json' for structured data");

const locationSchema = z
  .string()
  .trim()
  .min(2)
  .max(60)
  .refine(value => /^\p{L}[\p{L}\p{M} .'’-]*$/u.test(value), "Start with a letter; use letters, spaces, hyphens or apostrophes only")
  .describe("Country code (it, us, uk), country name (Italy, United States) or city (Warsaw)");

const waitSecondsSchema = (fallback: number) =>
  z
    .number()
    .int()
    .min(1)
    .max(MAX_WAIT_SECONDS)
    .default(fallback)
    .describe(`Seconds to wait for confirmation (1-${MAX_WAIT_SECONDS})`);

const StatusSchema = z.object({
  vpn: z
    .object({
      serviceID: z.string(),
      name: z.string(),
      state: z.enum(["invalid", "disconnected", "connecting", "connected", "disconnecting"]),
      interface: z.string().optional(),
      tunnelAddress: z.string().optional(),
      since: z.string().optional(),
      onDemand: z.boolean()
    })
    .optional()
    .describe("Absent when the app has no VPN profile"),
  server: z.string().optional().describe("Server name, only while connected"),
  lastTarget: z.string().optional(),
  publicIP: z
    .object({
      ip: z.string(),
      country: z.string().optional(),
      country_code: z.string().optional(),
      city: z.string().optional(),
      isp: z.string().optional(),
      protected: z.boolean()
    })
    .optional()
    .describe("Absent when NordVPN's API could not be reached")
});

const CountrySchema = z.object({
  id: z.number(),
  name: z.string(),
  code: z.string(),
  serverCount: z.number(),
  cities: z.array(z.object({ id: z.number(), name: z.string(), serverCount: z.number() }))
});
type Country = z.infer<typeof CountrySchema>;

const ApiServerSchema = z.object({
  name: z.string(),
  hostname: z.string(),
  load: z.number(),
  locations: z.array(
    z.object({ country: z.object({ name: z.string(), code: z.string(), city: z.object({ name: z.string() }).optional() }) })
  ),
  groups: z.array(z.object({ identifier: z.string() }))
});
type ApiServer = z.infer<typeof ApiServerSchema>;

const CheckSchema = z.object({ name: z.string(), passed: z.boolean(), message: z.string() });
const DoctorSchema = z.object({ all_passed: z.boolean(), checks: z.array(CheckSchema) });

const SERVER_GROUPS = ["standard", "p2p", "double", "onion", "obfuscated", "dedicated"] as const;

function text(value: string) {
  return { content: [{ type: "text" as const, text: value }] };
}

function json<T extends Record<string, unknown>>(value: T) {
  return { ...text(JSON.stringify(value, null, 2)), structuredContent: value };
}

function failure(result: CliResult, hint: string) {
  return { ...text(`${errorText(result)}\n\n${hint}`), isError: true };
}

function requireSuccess(result: CliResult, command: string, hint = ""): void {
  if (result.exitCode !== 0) throw new CliError(`nordvpn ${command} failed: ${errorText(result)}${hint && ` ${hint}`}`);
}

/** Stdout plus any warnings the CLI printed on stderr, such as a city resolving to its country. */
function report(result: CliResult): string {
  const warnings = result.stderr.trim();
  return [result.stdout.trim(), warnings && `Warning: ${warnings}`].filter(Boolean).join("\n");
}

/** Connect and disconnect drive one app, so they never run concurrently. */
let pendingChange: Promise<unknown> = Promise.resolve();

function serialized<T>(task: () => Promise<T>): Promise<T> {
  const run = pendingChange.then(task, task);
  pendingChange = run.catch(() => undefined);
  return run;
}

/** Halves the page until the rendered text fits, so next_offset points at the first item left out. */
function fitToLimit<T>(items: T[], render: (page: T[]) => string): { items: T[]; text: string } {
  let page = items;
  let rendered = render(page);
  while (page.length > 1 && rendered.length > CHARACTER_LIMIT) {
    page = page.slice(0, Math.ceil(page.length / 2));
    rendered = render(page);
  }
  return { items: page, text: rendered };
}

function formatCountry(country: Country): string {
  const cities = country.cities.map(city => city.name).sort((a, b) => a.localeCompare(b));
  return `- **${country.code}** ${country.name}: ${country.serverCount} servers; cities: ${cities.join(", ") || "none listed"}`;
}

function compactServer(server: ApiServer) {
  const where = server.locations[0]?.country;
  return {
    name: server.name,
    hostname: server.hostname,
    load: server.load,
    country: where?.name ?? null,
    country_code: where?.code ?? null,
    city: where?.city?.name ?? null,
    groups: server.groups.map(entry => entry.identifier)
  };
}

function registerStatus(server: McpServer): void {
  server.registerTool(
    "nordvpn_get_status",
    {
      title: "Get VPN status",
      description: `Report the NordVPN tunnel state, the connected server, and the public IP with whether NordVPN considers it protected.

Use it before and after nordvpn_connect or nordvpn_disconnect, and to answer "am I on the VPN?".
A successful call does not mean the VPN is connected: check vpn.state and publicIP.protected.`,
      outputSchema: StatusSchema,
      annotations: READ_ONLY
    },
    async ctx => {
      const result = await runCli(["status", "--json"], ctx.mcpReq.signal);
      requireSuccess(result, "status");
      return json(parseJson(StatusSchema, result, "status"));
    }
  );
}

function registerCountries(server: McpServer): void {
  server.registerTool(
    "nordvpn_list_countries",
    {
      title: "List VPN countries",
      description: `List the countries with NordVPN servers, with server counts and city names.

Use it to find a valid location for nordvpn_connect or nordvpn_list_servers.
Examples:
  - "Which cities can I use in Germany?" -> filter="germany"
  - "Countries starting with United" -> filter="united"`,
      inputSchema: z.strictObject({
        filter: z.string().trim().min(1).max(60).optional().describe("Keep countries whose name contains this text or whose code equals it"),
        limit: z.number().int().min(1).max(200).default(50).describe("Maximum number of countries to return"),
        offset: z.number().int().min(0).default(0).describe("Number of countries to skip, for pagination"),
        response_format: responseFormatSchema
      }),
      annotations: READ_ONLY
    },
    async ({ filter, limit, offset, response_format }, ctx) => {
      const result = await runCli(["countries", "--json", ...(filter ? ["--", filter] : [])], ctx.mcpReq.signal);
      requireSuccess(result, "countries");
      const countries = parseJson(z.array(CountrySchema), result, "countries");
      if (countries.length === 0) {
        return text(filter ? `No country matches "${filter}". Call again without a filter to see every country.` : "NordVPN returned no countries.");
      }

      const pageOf = (items: Country[]) => {
        const nextOffset = offset + items.length;
        const hasMore = countries.length > nextOffset;
        return { total: countries.length, count: items.length, offset, countries: items, has_more: hasMore, ...(hasMore ? { next_offset: nextOffset } : {}) };
      };
      const render = (items: Country[]) => {
        const page = pageOf(items);
        if (response_format === ResponseFormat.JSON) return JSON.stringify(page, null, 2);
        const lines = ["# NordVPN countries", `Showing ${page.count} of ${page.total}.`, "", ...items.map(formatCountry)];
        if (page.has_more) lines.push("", `More results: call again with offset=${page.next_offset}.`);
        return lines.join("\n");
      };
      const fitted = fitToLimit(countries.slice(offset, offset + limit), render);
      if (fitted.items.length === 0) return text(`Offset ${offset} is past the last of ${countries.length} countries.`);
      if (response_format === ResponseFormat.JSON) return { ...text(fitted.text), structuredContent: pageOf(fitted.items) };
      return text(fitted.text);
    }
  );
}

function registerServers(server: McpServer): void {
  server.registerTool(
    "nordvpn_list_servers",
    {
      title: "List least loaded servers",
      description: `Show NordVPN's recommended (least loaded) servers, optionally in one country and server group.

Informational only: the app picks the actual server, and nordvpn_connect cannot target a specific server or group.
Examples:
  - "Least loaded P2P servers in the US" -> location="us", group="p2p"
  - "How busy are servers in Italy?" -> location="italy"`,
      inputSchema: z.strictObject({
        location: locationSchema.optional(),
        group: z.enum(SERVER_GROUPS).optional().describe("Server group"),
        limit: z.number().int().min(1).max(50).default(10).describe("Number of servers"),
        response_format: responseFormatSchema
      }),
      annotations: READ_ONLY
    },
    async ({ location, group, limit, response_format }, ctx) => {
      const args = ["servers", "--json", "--limit", String(limit), ...(group ? ["--group", group] : []), ...(location ? ["--", location] : [])];
      const result = await runCli(args, ctx.mcpReq.signal);
      requireSuccess(result, "servers", LOCATION_HINT);
      const servers = parseJson(z.array(ApiServerSchema), result, "servers").map(compactServer);
      if (servers.length === 0) return text("No servers found. Try another group or location.");
      if (response_format === ResponseFormat.JSON) return json({ count: servers.length, servers });
      const lines = servers.map(entry => `- **${entry.name}**: load ${entry.load}%, ${[entry.city, entry.hostname].filter(Boolean).join(" · ")}`);
      return text(["# Least loaded NordVPN servers", "", ...lines].join("\n"));
    }
  );
}

function registerDoctor(server: McpServer): void {
  server.registerTool(
    "nordvpn_run_doctor",
    {
      title: "Diagnose NordVPN setup",
      description: `Check the NordVPN app installation, VPN profiles, Accessibility permission, app logs and API access, without changing the connection.

Use it when another nordvpn tool fails. The "accessibility" check concerns the application that runs this MCP server (your terminal, Cursor, Claude, Codex…) and matters only for nordvpn_disconnect.
The report contains no IP addresses, server names, account data or local paths.`,
      inputSchema: z.strictObject({
        offline: z.boolean().default(false).describe("Skip the check that contacts NordVPN's API")
      }),
      outputSchema: DoctorSchema,
      annotations: READ_ONLY
    },
    async ({ offline }, ctx) => {
      // Exit status 1 only means a check failed; the report is still on stdout.
      const result = await runCli(["doctor", "--json", ...(offline ? ["--offline"] : [])], ctx.mcpReq.signal);
      const checks = parseJson(z.array(CheckSchema), result, "doctor");
      return json({ all_passed: checks.every(check => check.passed), checks });
    }
  );
}

function registerConnect(server: McpServer): void {
  server.registerTool(
    "nordvpn_connect",
    {
      title: "Connect the VPN",
      description: `Ask the NordVPN app to connect, to the fastest server or to a country, and wait until the tunnel and public IP are verified.

Changes the Mac's network: an existing VPN connection is replaced. Only a country can be targeted; a city connects to the fastest server of its country.
Use nordvpn_list_countries to find valid locations.
Examples:
  - "Connect me to the VPN" -> no arguments
  - "Put me in Italy" -> location="italy"`,
      inputSchema: z.strictObject({
        location: locationSchema.optional().describe("Country code, country name or city; omit for the fastest server"),
        timeout_seconds: waitSecondsSchema(30),
        wait: z.boolean().default(true).describe("false returns right after the request is sent, without confirming the connection")
      }),
      annotations: { ...CHANGES_NETWORK, idempotentHint: false }
    },
    async ({ location, timeout_seconds, wait }, ctx) => {
      const args = ["connect", "--timeout", String(timeout_seconds), ...(wait ? [] : ["--no-wait"]), ...(location ? ["--", location] : [])];
      const result = await serialized(() => runCli(args, ctx.mcpReq.signal, (timeout_seconds + 20) * 1000));
      if (result.exitCode !== 0) return failure(result, `${LOCATION_HINT} The connection request may still be in progress. ${NEXT_STEPS}`);
      return text(report(result));
    }
  );
}

function registerDisconnect(server: McpServer): void {
  server.registerTool(
    "nordvpn_disconnect",
    {
      title: "Disconnect the VPN",
      description: `Disconnect the NordVPN tunnel and wait until it closes. Traffic is no longer protected afterwards.

The app has no disconnect deep link, so this presses "Disconnect" in its menu through the macOS Accessibility API: the application running this MCP server needs Accessibility access. Already disconnected is reported as success.`,
      inputSchema: z.strictObject({ timeout_seconds: waitSecondsSchema(15) }),
      annotations: { ...CHANGES_NETWORK, idempotentHint: true }
    },
    async ({ timeout_seconds }, ctx) => {
      const args = ["disconnect", "--timeout", String(timeout_seconds)];
      const result = await serialized(() => runCli(args, ctx.mcpReq.signal, (timeout_seconds + 10) * 1000));
      if (result.exitCode === 0) return text(report(result));
      const accessibility = /accessibility/i.test(result.stderr)
        ? "macOS checks the application that runs this MCP server (your terminal, Cursor, Claude, Codex…): enable that app in System Settings > Privacy & Security > Accessibility, then restart it. "
        : "";
      return failure(result, accessibility + NEXT_STEPS);
    }
  );
}

export interface ServerOptions {
  /** Hides nordvpn_connect and nordvpn_disconnect. */
  readOnly: boolean;
}

export function createServer({ readOnly }: ServerOptions): McpServer {
  const server = new McpServer({ name: "nordvpn-mcp-server", version: SERVER_VERSION });
  registerStatus(server);
  registerCountries(server);
  registerServers(server);
  registerDoctor(server);
  if (!readOnly) {
    registerConnect(server);
    registerDisconnect(server);
  }
  return server;
}
