import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import express from "express";
import { registerTools } from "./tools/index.js";

const PORT = parseInt(process.env.PORT ?? "3000", 10);

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

app.get("/health", (_req, res) => {
  res.json({ status: "ok", name: "igor-mcp-lab" });
});

app.post("/mcp", async (req, res) => {
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
  });
  const server = createServer();
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
  res.on("finish", () => {
    server.close().catch(() => {});
  });
});

app.listen(PORT, () => {
  console.log(`igor-mcp-lab listening on :${PORT}`);
});
