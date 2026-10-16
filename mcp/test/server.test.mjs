// Drives the built server over stdio against a fake nordvpn CLI, so no test changes the VPN.
import { strict as assert } from "node:assert";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/client";
import { getDefaultEnvironment, StdioClientTransport } from "@modelcontextprotocol/client/stdio";

const here = fileURLToPath(new URL(".", import.meta.url));
const FAKE_CLI = join(here, "fixtures", "nordvpn");
const SERVER = join(here, "..", "dist", "index.js");
const scratch = mkdtempSync(join(tmpdir(), "nordvpn-mcp-test-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

let logCount = 0;

async function startServer(env = {}) {
  const logFile = join(scratch, `calls-${++logCount}.jsonl`);
  const client = new Client({ name: "nordvpn-mcp-test", version: "1.0.0" });
  await client.connect(
    new StdioClientTransport({
      command: process.execPath,
      args: [SERVER],
      env: { ...getDefaultEnvironment(), NORDVPN_BIN: FAKE_CLI, FAKE_NORDVPN_LOG: logFile, ...env },
      stderr: "ignore"
    })
  );
  const calls = () => (existsSync(logFile) ? readFileSync(logFile, "utf8").trim().split("\n").map(line => JSON.parse(line)) : []);
  return { client, calls };
}

async function withServer(env, run) {
  const { client, calls } = await startServer(env);
  try {
    await run(client, calls);
  } finally {
    await client.close();
  }
}

const textOf = result => result.content.map(block => block.text).join("\n");

test("lists read-only and network-changing tools with matching annotations", () =>
  withServer({}, async client => {
    const { tools } = await client.listTools();
    const byName = Object.fromEntries(tools.map(tool => [tool.name, tool.annotations]));
    assert.deepEqual(Object.keys(byName).sort(), [
      "nordvpn_connect",
      "nordvpn_disconnect",
      "nordvpn_get_status",
      "nordvpn_list_countries",
      "nordvpn_list_servers",
      "nordvpn_run_doctor"
    ]);
    for (const name of ["nordvpn_get_status", "nordvpn_list_countries", "nordvpn_list_servers", "nordvpn_run_doctor"]) {
      assert.equal(byName[name].readOnlyHint, true, name);
    }
    for (const name of ["nordvpn_connect", "nordvpn_disconnect"]) {
      assert.equal(byName[name].readOnlyHint, false, name);
      assert.equal(byName[name].destructiveHint, true, name);
    }
  }));

test("read-only mode hides connect and disconnect", () =>
  withServer({ NORDVPN_MCP_READ_ONLY: "1" }, async client => {
    const { tools } = await client.listTools();
    assert.ok(tools.every(tool => tool.annotations.readOnlyHint), tools.map(tool => tool.name).join(", "));
    assert.equal(tools.length, 4);
  }));

test("status validates the CLI JSON and drops unknown fields", () =>
  withServer({}, async client => {
    const result = await client.callTool({ name: "nordvpn_get_status", arguments: {} });
    assert.ok(!result.isError, textOf(result));
    assert.equal(result.structuredContent.vpn.state, "connected");
    assert.equal(result.structuredContent.publicIP.protected, true);
    assert.equal("futureField" in result.structuredContent.vpn, false);
    assert.deepEqual(JSON.parse(textOf(result)), result.structuredContent);
  }));

test("doctor returns failed checks as data, not as a tool error", () =>
  withServer({}, async (client, calls) => {
    const result = await client.callTool({ name: "nordvpn_run_doctor", arguments: { offline: true } });
    assert.ok(!result.isError, textOf(result));
    assert.equal(result.structuredContent.all_passed, false);
    assert.equal(result.structuredContent.checks.length, 2);
    assert.deepEqual(calls().at(-1), ["doctor", "--json", "--offline"]);
  }));

test("countries paginate, filter and show cities", () =>
  withServer({}, async (client, calls) => {
    const page = await client.callTool({ name: "nordvpn_list_countries", arguments: { limit: 2, response_format: "json" } });
    assert.deepEqual(
      { total: page.structuredContent.total, count: page.structuredContent.count, next: page.structuredContent.next_offset },
      { total: 3, count: 2, next: 2 }
    );

    const filtered = await client.callTool({ name: "nordvpn_list_countries", arguments: { filter: "germany" } });
    assert.match(textOf(filtered), /\*\*DE\*\* Germany: 300 servers; cities: Berlin, Frankfurt/);
    assert.deepEqual(calls().at(-1), ["countries", "--json", "--", "germany"]);

    const none = await client.callTool({ name: "nordvpn_list_countries", arguments: { filter: "narnia" } });
    assert.match(textOf(none), /No country matches "narnia"/);
  }));

test("servers come back compact, with the group and location passed through", () =>
  withServer({}, async (client, calls) => {
    const result = await client.callTool({
      name: "nordvpn_list_servers",
      arguments: { location: "italy", group: "p2p", limit: 3, response_format: "json" }
    });
    assert.ok(!result.isError, textOf(result));
    assert.equal(result.structuredContent.count, 3);
    assert.deepEqual(Object.keys(result.structuredContent.servers[0]).sort(), ["city", "country", "country_code", "groups", "hostname", "load", "name"]);
    assert.deepEqual(calls().at(-1), ["servers", "--json", "--limit", "3", "--group", "p2p", "--", "italy"]);
  }));

test("connect passes the location after -- and reports the CLI's warnings", () =>
  withServer({}, async (client, calls) => {
    const result = await client.callTool({ name: "nordvpn_connect", arguments: { location: "rome", timeout_seconds: 20 } });
    assert.ok(!result.isError, textOf(result));
    assert.match(textOf(result), /Connected to Italy #456/);
    assert.match(textOf(result), /Warning: The app cannot pick a city/);
    assert.deepEqual(calls().at(-2), ["connect", "--timeout", "20", "--", "rome"]);
  }));

test("a failed connect is a tool error with next steps", () =>
  withServer({}, async client => {
    const result = await client.callTool({ name: "nordvpn_connect", arguments: { location: "atlantis" } });
    assert.equal(result.isError, true);
    assert.match(textOf(result), /^No country or city matches "atlantis"/);
    assert.match(textOf(result), /nordvpn_get_status/);
  }));

test("invalid arguments never reach the CLI", () =>
  withServer({}, async (client, calls) => {
    for (const args of [{ location: "--no-wait" }, { location: "it; rm -rf ~" }, { timeout_seconds: 0 }, { timeout_seconds: 600 }]) {
      const result = await client.callTool({ name: "nordvpn_connect", arguments: args });
      assert.equal(result.isError, true, JSON.stringify(args));
    }
    assert.equal(calls().some(call => call[0] === "connect"), false);
  }));

test("a disconnect blocked by Accessibility names the host application", () =>
  withServer({ FAKE_NORDVPN_ACCESSIBILITY: "denied" }, async client => {
    const result = await client.callTool({ name: "nordvpn_disconnect", arguments: {} });
    assert.equal(result.isError, true);
    assert.match(textOf(result), /application that runs this MCP server/);
  }));

test("connect and disconnect run one at a time", () =>
  withServer({ FAKE_NORDVPN_DELAY_MS: "400" }, async (client, calls) => {
    await Promise.all([
      client.callTool({ name: "nordvpn_connect", arguments: {} }),
      client.callTool({ name: "nordvpn_disconnect", arguments: {} })
    ]);
    const order = calls().filter(call => call[0] !== "--version").map(call => call.slice(0, 2).join(" "));
    assert.deepEqual(order, ["connect --timeout", "done connect", "disconnect --timeout", "done disconnect"]);
  }));

test("an outdated CLI is rejected with upgrade instructions", () =>
  withServer({ FAKE_NORDVPN_VERSION: "0.1.0" }, async client => {
    const result = await client.callTool({ name: "nordvpn_get_status", arguments: {} });
    assert.equal(result.isError, true);
    assert.match(textOf(result), /Found nordvpn 0\.1\.0 .* needs 0\.2\.0 or later/);
  }));

test("a wrong NORDVPN_BIN path is reported", () =>
  withServer({ NORDVPN_BIN: join(scratch, "missing") }, async client => {
    const result = await client.callTool({ name: "nordvpn_get_status", arguments: {} });
    assert.equal(result.isError, true);
    assert.match(textOf(result), /NORDVPN_BIN is set to .*not an executable file/);
  }));
