/**
 * echo tool
 *
 * The simplest possible MCP tool — it returns exactly what the caller sent.
 * Primary purposes:
 *   - Smoke test: if the server responds correctly to `echo`, the MCP stack
 *     is wired up correctly end-to-end (see deploy.yml smoke tests).
 *   - Development reference: shows the minimal structure a tool needs.
 *
 * Tool contract:
 *   Input:  { text: string }
 *   Output: content array with a single text item containing the same string
 *
 * The "as const" on the type field is a TypeScript requirement — the MCP SDK
 * needs the literal type "text", not the wider type string.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function registerEcho(server: McpServer) {
  server.tool(
    "echo",
    "Echo text back to the caller",
    { text: z.string().describe("Text to echo") },
    async ({ text }) => ({
      content: [{ type: "text" as const, text }],
    })
  );
}
