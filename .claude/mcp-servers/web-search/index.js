#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const server = new McpServer({
  name: "web-search",
  version: "1.0.0",
});

server.tool(
  "web_search",
  "Search the web using DuckDuckGo (free, no API key). Returns titles, URLs, and snippets.",
  {
    query: z.string().min(1).describe("The search query (non-empty)"),
    count: z.number().optional().default(5).describe("Number of results (1-20, default 5)"),
  },
  async ({ query, count }) => {
    const trimmed = query.trim();
    if (!trimmed) {
      return { content: [{ type: "text", text: "Error: search query cannot be empty." }], isError: true };
    }

    const n = Math.min(Math.max(count || 5, 1), 20);
    // Truncate very long queries to avoid issues
    const safeQuery = trimmed.length > 500 ? trimmed.slice(0, 500) : trimmed;

    const script = `
from ddgs import DDGS
import json, sys
try:
    results = list(DDGS().text(sys.argv[1], max_results=int(sys.argv[2])))
    print(json.dumps(results))
except Exception as e:
    print(json.dumps({"error": str(e)}))
`;
    try {
      const { stdout, stderr } = await execFileAsync("python3", ["-c", script, safeQuery, String(n)], {
        timeout: 30000,
        maxBuffer: 1024 * 1024,
      });

      const output = stdout.trim();
      if (!output) {
        return {
          content: [{ type: "text", text: `Search failed: no output from search backend.${stderr ? " stderr: " + stderr.slice(0, 200) : ""}` }],
          isError: true,
        };
      }

      let data;
      try {
        data = JSON.parse(output);
      } catch {
        return { content: [{ type: "text", text: `Search failed: could not parse results. Raw: ${output.slice(0, 300)}` }], isError: true };
      }

      if (data && data.error) {
        return { content: [{ type: "text", text: `Search error: ${data.error}` }], isError: true };
      }

      if (!Array.isArray(data) || data.length === 0) {
        return { content: [{ type: "text", text: `No results found for: ${safeQuery}` }] };
      }

      const formatted = data
        .map((r, i) => `${i + 1}. **${r.title || "(no title)"}**\n   ${r.href || "(no url)"}\n   ${r.body || ""}`)
        .join("\n\n");

      return {
        content: [{ type: "text", text: `Search results for "${safeQuery}":\n\n${formatted}` }],
      };
    } catch (err) {
      if (err.killed) {
        return { content: [{ type: "text", text: "Search timed out after 30 seconds. Try a simpler query." }], isError: true };
      }
      return { content: [{ type: "text", text: `Search error: ${err.message}` }], isError: true };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
