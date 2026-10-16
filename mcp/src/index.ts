#!/usr/bin/env node
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { createServer, SERVER_VERSION } from "./server.js";

const readOnly = ["1", "true", "yes"].includes((process.env.NORDVPN_MCP_READ_ONLY ?? "").toLowerCase());

serveStdio(() => createServer({ readOnly }));
console.error(`nordvpn-mcp-server ${SERVER_VERSION} running on stdio${readOnly ? " (read-only)" : ""}`);
