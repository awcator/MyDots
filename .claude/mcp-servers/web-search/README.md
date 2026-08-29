# Web Search MCP Server

An MCP (Model Context Protocol) server that provides web search capabilities using DuckDuckGo.

## Features

This server provides three tools:
1. \`web_search\`: Search the web using DuckDuckGo. Returns titles, URLs, and snippets.
2. \`web_news\`: Search DuckDuckGo News for recent articles.
3. \`fetch_webpage\`: Fetch a URL, extract the main content, and return it as Markdown. (Supports Single Page Applications via Puppeteer headless browser).

## Prerequisites

This project requires both Node.js and Python 3.

## Installation

1. Install Node.js dependencies:
   \`\`\`bash
   npm install
   \`\`\`

2. Install Python dependencies:
   \`\`\`bash
   pip3 install -r requirements.txt
   \`\`\`
   *(Note: The Python dependency used is \`duckduckgo_search\`)*

## Usage

To use this with Claude Code or another MCP client, configure it to run:
\`\`\`bash
node index.js
\`\`\`
