import { execFile } from "node:child_process";
import { constants } from "node:fs";
import { access } from "node:fs/promises";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";
import type * as z from "zod/v4";

const MIN_CLI_VERSION = "0.2.0";

/** Hosts launched from the Dock get a minimal PATH, so the usual install locations are searched too. */
const FALLBACK_DIRS = [join(homedir(), ".local", "bin"), "/opt/homebrew/bin", "/usr/local/bin"];

export interface CliResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** An error whose message is written for the model: it says what failed and how to recover. */
export class CliError extends Error {}

async function isExecutable(path: string): Promise<boolean> {
  try {
    await access(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

async function locateBinary(): Promise<string> {
  const configured = process.env.NORDVPN_BIN;
  if (configured) {
    if (await isExecutable(configured)) return configured;
    throw new CliError(`NORDVPN_BIN is set to ${configured}, which is not an executable file. Fix the path in the MCP server configuration.`);
  }
  const dirs = [...(process.env.PATH ?? "").split(delimiter).filter(Boolean), ...FALLBACK_DIRS];
  for (const dir of dirs) {
    const candidate = join(dir, "nordvpn");
    if (await isExecutable(candidate)) return candidate;
  }
  throw new CliError(
    "The nordvpn CLI was not found on PATH, in ~/.local/bin, /opt/homebrew/bin or /usr/local/bin. " +
      "Install it with `make install` in the nordvpn-cli repository, or set NORDVPN_BIN to its absolute path."
  );
}

function parseVersion(text: string): number[] | undefined {
  const match = /(\d+)\.(\d+)\.(\d+)/.exec(text);
  return match ? match.slice(1).map(Number) : undefined;
}

function isSupportedVersion(text: string): boolean {
  const version = parseVersion(text);
  const minimum = parseVersion(MIN_CLI_VERSION) ?? [];
  if (!version) return false;
  for (const [index, part] of version.entries()) {
    const required = minimum[index] ?? 0;
    if (part !== required) return part > required;
  }
  return true;
}

function spawnCli(file: string, args: string[], signal: AbortSignal, timeoutMs: number): Promise<CliResult> {
  const env = { ...process.env, NO_COLOR: "1" };
  return new Promise((resolve, reject) => {
    execFile(file, args, { env, signal, timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (!error) return resolve({ exitCode: 0, stdout, stderr });
      if (typeof error.code === "number") return resolve({ exitCode: error.code, stdout, stderr });
      if (error.name === "AbortError") return reject(error);
      if (error.killed) {
        return reject(new CliError(`nordvpn ${args[0] ?? ""} did not finish within ${Math.round(timeoutMs / 1000)} seconds. Check the NordVPN app, then call nordvpn_get_status.`));
      }
      reject(new CliError(`Could not run ${file}: ${error.message}`));
    });
  });
}

async function resolveBinary(): Promise<string> {
  const file = await locateBinary();
  const { stdout } = await spawnCli(file, ["--version"], new AbortController().signal, 10_000);
  const version = stdout.trim();
  if (!isSupportedVersion(version)) {
    throw new CliError(
      `Found nordvpn ${version || "with an unknown version"} at ${file}, but this MCP server needs ${MIN_CLI_VERSION} or later. ` +
        "Run `make install` in the nordvpn-cli repository, or set NORDVPN_BIN to a newer build."
    );
  }
  return file;
}

let binary: Promise<string> | undefined;

/** Resolved once per server process; a failure is retried on the next call, so installing the CLI needs no restart. */
function cliBinary(): Promise<string> {
  binary ??= resolveBinary().catch((error: unknown) => {
    binary = undefined;
    throw error;
  });
  return binary;
}

export async function runCli(args: string[], signal: AbortSignal, timeoutMs = 30_000): Promise<CliResult> {
  return spawnCli(await cliBinary(), args, signal, timeoutMs);
}

/** Last non-empty stderr line, without the argument parser's "Error: " prefix. */
export function errorText(result: CliResult): string {
  const lines = result.stderr.split("\n").map(line => line.trim()).filter(Boolean);
  const message = lines.find(line => line.startsWith("Error: ")) ?? lines.at(-1);
  return message?.replace(/^Error: /, "") ?? `nordvpn exited with status ${result.exitCode}.`;
}

export function parseJson<T>(schema: z.ZodType<T>, result: CliResult, command: string): T {
  let value: unknown;
  try {
    value = JSON.parse(result.stdout);
  } catch {
    throw new CliError(result.exitCode === 0 ? `nordvpn ${command} returned output that is not JSON.` : errorText(result));
  }
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    throw new CliError(`nordvpn ${command} returned JSON in an unexpected shape. Check that the CLI is version ${MIN_CLI_VERSION} or later.`);
  }
  return parsed.data;
}
