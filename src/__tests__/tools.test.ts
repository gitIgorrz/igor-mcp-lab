/**
 * Unit tests for MCP tools
 *
 * Testing approach — InMemoryTransport:
 *   Instead of starting a real HTTP server, the MCP SDK provides an
 *   InMemoryTransport that links a server and a client in the same process.
 *   This means tests run fast (no network) and don't need a running container.
 *
 *   The flow is:
 *     1. Create a server and register all tools on it
 *     2. Create a client
 *     3. Link them with a pair of InMemoryTransports (one per direction)
 *     4. Call tools through the client exactly as a real MCP client would
 *     5. Assert the response
 *
 * Test runner:
 *   Uses Node.js built-in test runner (node:test) — no extra test framework
 *   needed. Run with: npm run test:built  (after tsc compiles the source)
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { registerTools } from "../tools/index.js";

/** Creates a linked server+client pair for testing without HTTP. */
async function createTestClient() {
  const server = new McpServer({ name: "test", version: "0.0.0" });
  registerTools(server);
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  const client = new Client({ name: "test-client", version: "0.0.0" });
  await client.connect(clientTransport);
  return { client, server };
}

describe("echo tool", () => {
  it("returns the input text", async () => {
    const { client } = await createTestClient();
    const result = await client.callTool({ name: "echo", arguments: { text: "hello world" } });
    const content = result.content as Array<{ type: string; text: string }>;
    assert.equal(content[0].text, "hello world");
  });
});

describe("add tool", () => {
  it("adds two numbers correctly", async () => {
    const { client } = await createTestClient();
    const result = await client.callTool({ name: "add", arguments: { a: 3, b: 4 } });
    const content = result.content as Array<{ type: string; text: string }>;
    assert.equal(content[0].text, "7");
  });

  it("handles negative numbers", async () => {
    const { client } = await createTestClient();
    const result = await client.callTool({ name: "add", arguments: { a: -5, b: 2 } });
    const content = result.content as Array<{ type: string; text: string }>;
    assert.equal(content[0].text, "-3");
  });
});

describe("server-info tool", () => {
  it("returns parseable JSON with name field", async () => {
    const { client } = await createTestClient();
    const result = await client.callTool({ name: "server-info", arguments: {} });
    const content = result.content as Array<{ type: string; text: string }>;
    const info = JSON.parse(content[0].text) as { name: string };
    assert.equal(info.name, "igor-mcp-lab");
  });
});
