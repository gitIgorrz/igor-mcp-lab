import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { registerEcho } from "./echo.js";
import { registerGetInfo } from "./get-info.js";
import { registerAddNumbers } from "./add-numbers.js";

export function registerTools(server: McpServer) {
  registerEcho(server);
  registerGetInfo(server);
  registerAddNumbers(server);
}
