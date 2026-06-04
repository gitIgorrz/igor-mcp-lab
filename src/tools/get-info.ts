/**
 * server-info tool
 *
 * Returns deployment metadata about the running server instance.
 * Useful for quickly answering "which version is deployed and when?" without
 * needing to check logs or the Azure portal.
 *
 * The values come from environment variables injected at deploy time:
 *   IMAGE_TAG   — the git SHA of the Docker image (set by Terraform via image_tag variable)
 *   ENVIRONMENT — "azure" in production, absent in local dev
 *   DEPLOYED_AT — ISO-8601 timestamp of the last Terraform apply (set by Terraform)
 *
 * Tool contract:
 *   Input:  none
 *   Output: JSON string with { name, version, environment, deployedAt, node }
 */

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
