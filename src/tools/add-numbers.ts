/**
 * add tool
 *
 * Adds two numbers and returns the result as a string.
 * Demonstrates that MCP tools can perform computation, not just data lookup.
 *
 * Tool contract:
 *   Input:  { a: number, b: number }
 *   Output: content array with a single text item containing the sum as a string
 *
 * Note: MCP tool responses always return content as an array of typed items
 * (text, image, resource). Even a single number result must be wrapped this way.
 */

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
