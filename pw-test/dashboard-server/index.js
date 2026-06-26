import http from 'node:http';
import https from 'node:https';
import { spawn } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs/promises';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PW_TEST_DIR = resolve(__dirname, '..');
const CLIENT_DIR = resolve(__dirname, '..', '..', 'client');

// PocketBase URL — same as pw-test/config.mjs
const POCKETBASE_URL = process.env.STEALTH_POCKETBASE_URL || 'http://127.0.0.1:8090';

let currentTestProcess = null;

// ── Helpers ──────────────────────────────────────────────────────────

function jsonResponse(res, code, data) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

/** Fetch JSON from PocketBase (or any URL). Returns parsed object or null. */
function fetchJSON(url) {
  return new Promise((resolve) => {
    const mod = url.startsWith('https') ? https : http;
    const req = mod.get(url, { timeout: 5000 }, (resp) => {
      let body = '';
      resp.on('data', (c) => (body += c));
      resp.on('end', () => {
        try { resolve(JSON.parse(body)); } catch { resolve(null); }
      });
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
  });
}

// ── Route handlers ──────────────────────────────────────────────────

async function serveHTML(res) {
  try {
    const html = await fs.readFile(resolve(__dirname, 'index.html'), 'utf8');
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(html);
  } catch {
    res.writeHead(500);
    res.end('Error loading dashboard');
  }
}

async function handleGetTests(res) {
  try {
    const testsDir = resolve(PW_TEST_DIR, 'tests');
    const files = await fs.readdir(testsDir);
    const testFiles = files.filter((f) => f.endsWith('.spec.js'));
    jsonResponse(res, 200, { tests: testFiles });
  } catch (error) {
    jsonResponse(res, 500, { error: error.message });
  }
}

function handleRunTest(req, res) {
  let body = '';
  req.on('data', (chunk) => (body += chunk.toString()));
  req.on('end', () => {
    let testFile = null;
    try {
      const payload = JSON.parse(body);
      testFile = payload.testFile;
    } catch {}

    if (currentTestProcess) {
      jsonResponse(res, 400, { error: 'Test already running' });
      return;
    }

    res.writeHead(200, { 'Content-Type': 'text/plain', 'Transfer-Encoding': 'chunked' });

    const args = ['run', 'test:pw'];
    if (testFile) args.push('--', `tests/${testFile}`);

    currentTestProcess = spawn('npm', args, { cwd: PW_TEST_DIR });

    currentTestProcess.stdout.on('data', (d) => res.write(d.toString()));
    currentTestProcess.stderr.on('data', (d) => res.write(d.toString()));
    currentTestProcess.on('close', (code) => {
      currentTestProcess = null;
      res.write(`\n[Process exited with code ${code}]`);
      res.end();
    });
  });
}

async function handleGetResults(res) {
  try {
    const resultsPath = resolve(PW_TEST_DIR, 'test-results.json');
    const raw = await fs.readFile(resultsPath, 'utf8');
    jsonResponse(res, 200, JSON.parse(raw));
  } catch {
    jsonResponse(res, 404, { error: 'No test-results.json found' });
  }
}

async function handleGetStats(res) {
  // Fetch aggregated stats from PocketBase app_stats collection
  const pbData = await fetchJSON(
    `${POCKETBASE_URL}/api/collections/app_stats/records?sort=-created&perPage=500`,
  );

  if (!pbData || !pbData.items) {
    jsonResponse(res, 200, {
      source: 'unavailable',
      totalUsers: 0,
      totalChats: 0,
      totalMessages: 0,
      totalCalls: 0,
      totalContacts: 0,
      platforms: {},
      records: [],
    });
    return;
  }

  const items = pbData.items;
  const userSet = new Set();
  const platforms = {};
  let totalChats = 0, totalMessages = 0, totalCalls = 0, totalContacts = 0;

  for (const r of items) {
    userSet.add(r.userId);
    totalChats += r.chatCount || 0;
    totalMessages += r.messageCount || 0;
    totalCalls += r.callCount || 0;
    totalContacts += r.contactCount || 0;
    const p = r.platformType || 'unknown';
    platforms[p] = (platforms[p] || 0) + 1;
  }

  jsonResponse(res, 200, {
    source: 'pocketbase',
    totalUsers: userSet.size,
    totalChats,
    totalMessages,
    totalCalls,
    totalContacts,
    platforms,
    recentRecords: items.slice(0, 20).map((r) => ({
      userId: (r.userId || '').substring(0, 8),
      platform: r.platformType,
      device: r.deviceModel,
      appVersion: r.appVersion,
      chats: r.chatCount,
      messages: r.messageCount,
      created: r.created,
    })),
  });
}

async function handleGetPerf(res) {
  // Read local performance benchmark results
  const results = {};

  // 1) Try reading FPS benchmark output
  try {
    const fpsPath = resolve(CLIENT_DIR, 'test', 'performance', 'fps_benchmark_test.dart');
    await fs.access(fpsPath);
    results.fpsBenchmarkExists = true;
  } catch {
    results.fpsBenchmarkExists = false;
  }

  // 2) Try reading bundle size
  try {
    const jsPath = resolve(CLIENT_DIR, 'build', 'web', 'main.dart.js');
    const stat = await fs.stat(jsPath);
    results.webBundleSize = stat.size;
    results.webBundleSizeKB = Math.round(stat.size / 1024);
  } catch {
    results.webBundleSize = null;
  }

  // 3) Try reading APK sizes
  try {
    const apkDir = resolve(CLIENT_DIR, 'build', 'app', 'outputs', 'flutter-apk');
    const files = await fs.readdir(apkDir);
    const apks = [];
    for (const f of files) {
      if (f.endsWith('.apk')) {
        const s = await fs.stat(resolve(apkDir, f));
        apks.push({ name: f, sizeBytes: s.size, sizeMB: (s.size / 1048576).toFixed(1) });
      }
    }
    results.apks = apks;
  } catch {
    results.apks = [];
  }

  jsonResponse(res, 200, results);
}

// ── Router ───────────────────────────────────────────────────────────

const requestHandler = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'OPTIONS, GET, POST');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  const url = new URL(req.url, `http://${req.headers.host}`);
  const path = url.pathname;

  if (req.method === 'GET' && path === '/')            return serveHTML(res);
  if (req.method === 'GET' && path === '/api/tests')   return handleGetTests(res);
  if (req.method === 'GET' && path === '/api/results') return handleGetResults(res);
  if (req.method === 'GET' && path === '/api/stats')   return handleGetStats(res);
  if (req.method === 'GET' && path === '/api/perf')    return handleGetPerf(res);
  if (req.method === 'POST' && path === '/api/run')    return handleRunTest(req, res);

  res.writeHead(404);
  res.end('Not found');
};

const server = http.createServer(requestHandler);
const PORT = process.env.DASHBOARD_PORT || 3001;
server.listen(PORT, () => {
  console.log(`Stealth Dashboard running on http://localhost:${PORT}`);
  console.log(`PocketBase URL: ${POCKETBASE_URL}`);
});
