#!/usr/bin/env node
// ErrandHer AI-Ops MCP server — Phase 0.
//
// Wraps the Laravel AI-Ops API (routes/ai-ops.php, app/Http/Controllers/
// Api/AiOps/) as MCP tools Claude Code can call directly. Holds the
// AI-Ops credential (AI_OPS_TOKEN) — the desktop app and the agent's
// own prompt never see it.
//
// NOT YET TESTED — this sandbox has no Flutter/Node runtime connected to a
// live Laravel server. Written against the MCP TypeScript/JS SDK's
// documented stdio-server pattern; verify `npm install && npm start`
// actually connects once this is on your machine, before relying on it.
//
// Config (environment variables, set in .env — see .env.example):
//   AI_OPS_BASE_URL   e.g. https://errandher.ng  (or your local dev URL)
//   AI_OPS_TOKEN       plaintext token from `php artisan ai-ops:token:create`

import { config as loadEnv } from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';

// Load mcp-server/.env explicitly by path — don't rely on whatever
// directory Claude Code happens to spawn this process from.
const __dirname = dirname(fileURLToPath(import.meta.url));
loadEnv({ path: join(__dirname, '..', '.env') });

const BASE_URL = process.env.AI_OPS_BASE_URL;
const TOKEN = process.env.AI_OPS_TOKEN;

const server = new McpServer({
  name: 'errandher-ai-ops',
  version: '0.1.0',
});

async function callAiOps(path, init = {}) {
  if (!BASE_URL || !TOKEN) {
    throw new Error('AI_OPS_BASE_URL or AI_OPS_TOKEN is not set — check your .env file.');
  }
  const res = await fetch(`${BASE_URL}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      Accept: 'application/json',
      ...(init.headers || {}),
    },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`AI-Ops API ${res.status}: ${JSON.stringify(body)}`);
  }
  return body;
}

server.registerTool(
  'ai_ops_ping',
  {
    title: 'AI-Ops health check',
    description:
      "Confirms the AI-Ops API is reachable and this agent's credential is valid. " +
      'Phase 0 proof-of-concept tool — the first thing to call to verify the whole pipeline works.',
    inputSchema: {},
  },
  async () => {
    try {
      const result = await callAiOps('/api/ai-ops/ping');
      return { content: [{ type: 'text', text: JSON.stringify(result) }] };
    } catch (err) {
      return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
