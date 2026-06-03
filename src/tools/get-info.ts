import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

export function registerGetInfo(server: McpServer) {
  server.tool(
    "server-info",
    "Return deployment metadata for this MCP server",
    {},
    async () => ({
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              name: "igor-mcp-lab",
              version: process.env.IMAGE_TAG ?? "dev",
              environment: process.env.ENVIRONMENT ?? "local",
              deployedAt: process.env.DEPLOYED_AT ?? "unknown",
              node: process.version,
            },
            null,
            2
          ),
        },
      ],
    })
  );
}
