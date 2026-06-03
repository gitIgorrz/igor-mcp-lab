import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function registerAddNumbers(server: McpServer) {
  server.tool(
    "add",
    "Add two numbers and return the result",
    {
      a: z.number().describe("First operand"),
      b: z.number().describe("Second operand"),
    },
    async ({ a, b }) => ({
      content: [{ type: "text" as const, text: String(a + b) }],
    })
  );
}
