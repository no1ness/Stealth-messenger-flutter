import http from 'node:http';
import { spawn } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs/promises';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PW_TEST_DIR = resolve(__dirname, '..');

let currentTestProcess = null;

const requestHandler = async (req, res) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'OPTIONS, GET, POST');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === 'GET' && url.pathname === '/') {
    // Serve HTML
    try {
      const htmlPath = resolve(__dirname, 'index.html');
      const html = await fs.readFile(htmlPath, 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(html);
    } catch (err) {
      res.writeHead(500);
      res.end('Error loading dashboard');
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/tests') {
    try {
      const testsDir = resolve(PW_TEST_DIR, 'tests');
      const files = await fs.readdir(testsDir);
      const testFiles = files.filter(f => f.endsWith('.spec.js'));
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ tests: testFiles }));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: error.message }));
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/run') {
    let body = '';
    req.on('data', chunk => body += chunk.toString());
    req.on('end', () => {
      let testFile = null;
      try {
        const payload = JSON.parse(body);
        testFile = payload.testFile;
      } catch (e) {}

      if (currentTestProcess) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Test already running' }));
        return;
      }

      res.writeHead(200, {
        'Content-Type': 'text/plain',
        'Transfer-Encoding': 'chunked'
      });

      const args = ['run', 'test:pw'];
      if (testFile) args.push(`tests/${testFile}`);

      currentTestProcess = spawn('npm', args, { cwd: PW_TEST_DIR });

      currentTestProcess.stdout.on('data', data => {
        res.write(data.toString());
      });

      currentTestProcess.stderr.on('data', data => {
        res.write(data.toString());
      });

      currentTestProcess.on('close', code => {
        currentTestProcess = null;
        res.write(`\n[Process exited with code ${code}]`);
        res.end();
      });
    });
    return;
  }

  res.writeHead(404);
  res.end('Not found');
};

const server = http.createServer(requestHandler);
const PORT = 3001;
server.listen(PORT, () => {
  console.log(`Test Dashboard Server running on http://localhost:${PORT}`);
});
