import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { registerTools } from "../tools/index.js";

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
