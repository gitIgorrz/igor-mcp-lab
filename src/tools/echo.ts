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
