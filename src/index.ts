/**
 * MCP Server — HTTP entry point
 *
 * Model Context Protocol (MCP) is an open standard that lets AI assistants
 * (like Claude) communicate with external tools and data sources over a
 * defined JSON-RPC protocol. This file starts an HTTP server that speaks MCP,
 * so any MCP-compatible client can call the tools defined in src/tools/.
 *
 * Transport choice — Streamable HTTP:
 *   MCP supports two transports: stdio (one process per session) and
 *   Streamable HTTP (a single long-running server handling many sessions).
 *   We use Streamable HTTP because the server runs inside a container in
 *   Azure Container Instances; clients reach it over the network.
 *
 * Stateless mode:
 *   Each POST /mcp request creates a short-lived McpServer + transport pair,
 *   handles the request, then disposes both. This keeps the server simple
 *   (no session management) at the cost of a small per-request overhead —
 *   acceptable for a lab workload.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import express from "express";
import { registerTools } from "./tools/index.js";

const PORT = parseInt(process.env.PORT ?? "3000", 10);

/**
 * Creates a fresh McpServer for each request.
 * Tools are re-registered on every call — cheap because they're just
 * function registrations with no persistent state.
 */
function createServer(): McpServer {
  const server = new McpServer({
    name: "igor-mcp-lab",
    version: process.env.IMAGE_TAG ?? "dev",
  });
  registerTools(server);
  return server;
}

const app = express();
app.use(express.json());

/**
 * Health check endpoint.
 * Used by:
 *   - Azure Container Instances liveness + readiness probes (infra/main.tf)
 *   - GitHub Actions smoke tests (.github/workflows/deploy.yml)
 */
app.get("/health", (_req, res) => {
  res.json({ status: "ok", name: "igor-mcp-lab" });
});

/**
 * MCP protocol endpoint.
 *
 * Clients must send:
 *   POST /mcp
 *   Content-Type: application/json
 *   Accept: application/json, text/event-stream   ← required by Streamable HTTP
 *
 * The body is a JSON-RPC 2.0 message (e.g. tools/list or tools/call).
 * The response may be plain JSON or a Server-Sent Events stream depending
 * on whether the operation produces multiple events.
 */
app.post("/mcp", async (req, res) => {
  // sessionIdGenerator: undefined → stateless mode (no persistent sessions)
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
  });
  const server = createServer();
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
  // Clean up after the response is sent to free memory
  res.on("finish", () => {
    server.close().catch(() => {});
  });
});

app.listen(PORT, () => {
  console.log(`igor-mcp-lab listening on :${PORT}`);
});
