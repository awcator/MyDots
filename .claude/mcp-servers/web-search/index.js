#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { Readability } from "@mozilla/readability";
import { JSDOM } from "jsdom";
import TurndownService from "turndown";
import puppeteer from "puppeteer";

const execFileAsync = promisify(execFile);

const server = new McpServer({
  name: "web-search",
  version: "1.1.0",
});

server.tool(
  "web_search",
  "Search the web using DuckDuckGo. Returns titles, URLs, and snippets.",
  {
    query: z.string().min(1).describe("The search query"),
    count: z.number().optional().default(5).describe("Number of results (1-20, default 5)"),
    time_limit: z.enum(["d", "w", "m", "y"]).optional().describe("Time limit: 'd' (day), 'w' (week), 'm' (month), 'y' (year)"),
  },
  async ({ query, count, time_limit }) => {
    const trimmed = query.trim();
    if (!trimmed) {
      return { content: [{ type: "text", text: "Error: search query cannot be empty." }], isError: true };
    }

    const n = Math.min(Math.max(count || 5, 1), 20);
    const safeQuery = trimmed.length > 500 ? trimmed.slice(0, 500) : trimmed;

    const script = `
from ddgs import DDGS
import json, sys

try:
    kwargs = {"max_results": int(sys.argv[2])}
    if sys.argv[3] != "None":
        kwargs["timelimit"] = sys.argv[3]

    results = list(DDGS().text(sys.argv[1], **kwargs))
    print(json.dumps(results))
except Exception as e:
    print(json.dumps({"error": str(e)}))
`;
    try {
      const { stdout, stderr } = await execFileAsync("python3", ["-c", script, safeQuery, String(n), time_limit || "None"], {
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

server.tool(
  "web_news",
  "Search DuckDuckGo News for recent articles. Returns dates, titles, URLs, and snippets.",
  {
    query: z.string().min(1).describe("The news search query"),
    count: z.number().optional().default(5).describe("Number of news results (1-20, default 5)"),
    time_limit: z.enum(["d", "w", "m", "y"]).optional().describe("Time limit: 'd' (day), 'w' (week), 'm' (month), 'y' (year)"),
  },
  async ({ query, count, time_limit }) => {
    const trimmed = query.trim();
    if (!trimmed) {
      return { content: [{ type: "text", text: "Error: search query cannot be empty." }], isError: true };
    }

    const n = Math.min(Math.max(count || 5, 1), 20);
    const safeQuery = trimmed.length > 500 ? trimmed.slice(0, 500) : trimmed;

    const script = `
from ddgs import DDGS
import json, sys

try:
    kwargs = {"max_results": int(sys.argv[2])}
    if sys.argv[3] != "None":
        kwargs["timelimit"] = sys.argv[3]

    results = list(DDGS().news(sys.argv[1], **kwargs))
    print(json.dumps(results))
except Exception as e:
    print(json.dumps({"error": str(e)}))
`;
    try {
      const { stdout, stderr } = await execFileAsync("python3", ["-c", script, safeQuery, String(n), time_limit || "None"], {
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
        return { content: [{ type: "text", text: `No news found for: ${safeQuery}` }] };
      }

      const formatted = data
        .map((r, i) => `${i + 1}. **${r.title || "(no title)"}** (${r.date || "no date"})\n   Source: ${r.source || "unknown"}\n   ${r.url || "(no url)"}\n   ${r.body || ""}`)
        .join("\n\n");

      return {
        content: [{ type: "text", text: `News results for "${safeQuery}":\n\n${formatted}` }],
      };
    } catch (err) {
      if (err.killed) {
        return { content: [{ type: "text", text: "News search timed out after 30 seconds." }], isError: true };
      }
      return { content: [{ type: "text", text: `News search error: ${err.message}` }], isError: true };
    }
  }
);

server.tool(
  "fetch_webpage",
  "Fetch a URL, extract the main content (removing navigation, ads, etc.), and return it as Markdown. Best for reading full articles and documentation.",
  {
    url: z.string().url().describe("The URL of the webpage to fetch"),
  },
  async ({ url }) => {
    let browser = null;
    try {
      browser = await puppeteer.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox']
      });
      const page = await browser.newPage();

      // Set a 15-second timeout for navigation
      page.setDefaultNavigationTimeout(15000);

      // Navigate to URL and wait for network idle to ensure SPAs load
      const response = await page.goto(url, { waitUntil: 'networkidle2' });

      if (!response || !response.ok()) {
        await browser.close();
        return {
          content: [{ type: "text", text: `Failed to fetch URL. Status code: ${response ? response.status() : 'Unknown'} ${response ? response.statusText() : ''}` }],
          isError: true,
        };
      }

      const contentType = response.headers()['content-type'];
      if (contentType && !contentType.includes("text/html") && !contentType.includes("text/plain") && !contentType.includes("application/xhtml+xml")) {
         await browser.close();
         return {
          content: [{ type: "text", text: `Error: Content is not HTML (found ${contentType}). Cannot parse.` }],
          isError: true,
        };
      }

      // Get the full HTML after JS has executed
      const html = await page.content();
      await browser.close();

      const doc = new JSDOM(html, { url });
      const reader = new Readability(doc.window.document);
      const article = reader.parse();

      if (!article) {
        return {
          content: [{ type: "text", text: "Failed to parse the main content from the webpage." }],
          isError: true,
        };
      }

      const turndownService = new TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced' });
      let markdown = turndownService.turndown(article.content);

      if (markdown.length > 50000) {
        markdown = markdown.substring(0, 50000) + "\n\n...[Content truncated due to length]...";
      }

      let resText = `# ${article.title}\n\n`;
      if (article.byline) resText += `**Byline:** ${article.byline}\n`;
      if (article.siteName) resText += `**Site:** ${article.siteName}\n`;
      resText += `\n${markdown}`;

      return {
        content: [{ type: "text", text: resText }],
      };
    } catch (err) {
      if (browser) await browser.close().catch(() => {});
      if (err.message.includes('Timeout')) {
         return { content: [{ type: "text", text: "Error: fetching the webpage timed out after 15 seconds." }], isError: true };
      }
      return { content: [{ type: "text", text: `Error fetching webpage: ${err.message}` }], isError: true };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
