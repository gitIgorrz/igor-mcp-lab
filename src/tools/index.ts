/**
 * Tool registration barrel
 *
 * An MCP "tool" is a named function that an AI assistant can invoke.
 * The assistant sees each tool's name, description, and input schema —
 * it uses these to decide when and how to call a tool.
 *
 * This file is the single place that wires all tools into a server instance.
 * Adding a new tool means: (1) create a file in src/tools/, (2) import and
 * call its register function here.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { registerEcho } from "./echo.js";
import { registerGetInfo } from "./get-info.js";
import { registerAddNumbers } from "./add-numbers.js";

export function registerTools(server: McpServer) {
  registerEcho(server);
  registerGetInfo(server);
  registerAddNumbers(server);
}
