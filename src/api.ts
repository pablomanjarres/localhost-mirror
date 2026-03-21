import { Router } from 'express';
import { nanoid } from 'nanoid';
import httpProxy from 'http-proxy';
import { readState, writeState, type Tunnel } from './store.js';
import { getTailscaleInfo } from './tailscale.js';
import { localOnly } from './auth.js';
import { DASHBOARD_PORT } from './utils/constants.js';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { Socket } from 'node:net';

// In-memory proxy instances (one per tunnel target port)
const proxyCache = new Map<number, httpProxy>();

function getOrCreateProxy(port: number): httpProxy {
  let proxy = proxyCache.get(port);
  if (!proxy) {
    proxy = httpProxy.createProxyServer({
      target: `http://127.0.0.1:${port}`,
      ws: true,
      xfwd: true,
    });
    proxy.on('error', (_err, _req, errRes) => {
      if ('writeHead' in errRes) {
        (errRes as ServerResponse).writeHead(502, { 'Content-Type': 'text/html' });
        (errRes as ServerResponse).end(`<html><body style="font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#111;color:#fff">
          <div style="text-align:center"><h1>502</h1><p>localhost:${port} is not responding</p></div></body></html>`);
      }
    });
    proxyCache.set(port, proxy);
  }
  return proxy;
}

export function getProxyCache(): Map<number, httpProxy> {
  return proxyCache;
}

export function getTunnelsFromState(): Tunnel[] {
  return readState().tunnels;
}

export function updateTunnelStatus(id: string, status: Tunnel['status']): void {
  const state = readState();
  const tunnel = state.tunnels.find((t) => t.id === id);
  if (tunnel) {
    tunnel.status = status;
    writeState(state);
  }
}

function parseCookies(req: IncomingMessage): Record<string, string> {
  const cookies: Record<string, string> = {};
  const header = req.headers.cookie ?? '';
  for (const pair of header.split(';')) {
    const [key, ...val] = pair.trim().split('=');
    if (key) cookies[key] = val.join('=');
  }
  return cookies;
}

function getTunnelPort(req: IncomingMessage): number | null {
  const cookies = parseCookies(req);
  const port = parseInt(cookies['lm_tunnel'] ?? '', 10);
  if (!port || port < 1 || port > 65535) return null;

  const state = readState();
  const tunnel = state.tunnels.find((t) => t.localPort === port);
  return tunnel ? port : null;
}

// Main request handler for the dashboard server (port 19100)
// Handles: /?tunnel=<port> (set cookie), /lm/* (dashboard), /* (proxy via cookie)
export function createMainHandler(): (req: IncomingMessage, res: ServerResponse) => void {
  return (req, res) => {
    const url = new URL(req.url ?? '/', `http://${req.headers.host}`);

    // 1. Set tunnel via ?tunnel=<port> query param
    const tunnelParam = url.searchParams.get('tunnel');
    if (tunnelParam) {
      const port = parseInt(tunnelParam, 10);
      const state = readState();
      const tunnel = state.tunnels.find((t) => t.localPort === port);

      if (!tunnel) {
        res.writeHead(404, { 'Content-Type': 'text/html' });
        res.end(`<html><body style="font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#111;color:#fff">
          <div style="text-align:center"><h1>404</h1><p>No tunnel for port ${port}</p><p><a href="/lm/" style="color:#4ade80">Dashboard</a></p></div></body></html>`);
        return;
      }

      // Check token if required
      if (tunnel.token) {
        const tokenParam = url.searchParams.get('token');
        if (tokenParam !== tunnel.token) {
          res.writeHead(401, { 'Content-Type': 'text/html' });
          res.end(`<html><body style="font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#111;color:#fff">
            <div style="text-align:center"><h1>401</h1><p>Token required: ?tunnel=${port}&token=xxx</p></div></body></html>`);
          return;
        }
      }

      // Set cookie and redirect to /
      res.writeHead(302, {
        'Set-Cookie': `lm_tunnel=${port}; Path=/; SameSite=Lax`,
        'Location': '/',
      });
      res.end();
      return;
    }

    // 2. Clear tunnel: /?clear
    if (url.searchParams.has('clear')) {
      res.writeHead(302, {
        'Set-Cookie': 'lm_tunnel=; Path=/; Max-Age=0',
        'Location': '/lm/',
      });
      res.end();
      return;
    }

    // 3. /lm/* — dashboard and management API (handled by Express, see below)
    if (req.url?.startsWith('/lm')) {
      return; // Let Express handle it
    }

    // 4. Alias route: /<name> → lookup tunnel by name, set cookie, redirect
    const pathname = url.pathname;
    if (pathname !== '/' && !pathname.startsWith('/lm')) {
      const alias = pathname.slice(1).split('/')[0].toLowerCase();
      const state = readState();
      const tunnel = state.tunnels.find(
        (t) => t.name.toLowerCase() === alias
      );

      if (tunnel) {
        // Check token if required
        if (tunnel.token) {
          const tokenParam = url.searchParams.get('token');
          if (tokenParam !== tunnel.token) {
            res.writeHead(401, { 'Content-Type': 'text/html' });
            res.end(`<html><body style="font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#111;color:#fff">
              <div style="text-align:center"><h1>401</h1><p>Token required: /${alias}?token=xxx</p></div></body></html>`);
            return;
          }
        }

        res.writeHead(302, {
          'Set-Cookie': `lm_tunnel=${tunnel.localPort}; Path=/; SameSite=Lax`,
          'Location': '/',
        });
        res.end();
        return;
      }
    }

    // 5. Proxy via cookie
    const tunnelPort = getTunnelPort(req);
    if (tunnelPort) {
      const proxy = getOrCreateProxy(tunnelPort);
      proxy.web(req, res);
      return;
    }

    // 6. No cookie — redirect to dashboard
    res.writeHead(302, { 'Location': '/lm/' });
    res.end();
  };
}

// WebSocket upgrade handler
export function handleUpgrade(req: IncomingMessage, socket: Socket, head: Buffer): void {
  const tunnelPort = getTunnelPort(req);
  if (!tunnelPort) { socket.destroy(); return; }

  const proxy = getOrCreateProxy(tunnelPort);
  proxy.ws(req, socket, head);
}

// Express router for /lm/* management API
export function createApiRouter(onTunnelChange: () => void): Router {
  const router = Router();

  router.get('/lm/api/status', async (_req, res) => {
    try {
      const tsInfo = await getTailscaleInfo();
      const state = readState();
      res.json({
        ok: true,
        daemon: true,
        pid: process.pid,
        tunnelCount: state.tunnels.length,
        tailscale: tsInfo,
      });
    } catch (err) {
      res.json({
        ok: true,
        daemon: true,
        pid: process.pid,
        tunnelCount: readState().tunnels.length,
        tailscale: { ip: '', hostname: '', isRunning: false },
        error: (err as Error).message,
      });
    }
  });

  router.get('/lm/api/tunnels', (_req, res) => {
    const state = readState();
    res.json({ ok: true, tunnels: state.tunnels });
  });

  router.post('/lm/api/tunnels', async (req, res) => {
    try {
      const { localPort, name, token } = req.body;
      const state = readState();
      const effectiveName = name ?? `port-${localPort}`;

      const existing = state.tunnels.find((t) => t.localPort === localPort);
      if (existing) {
        res.status(409).json({
          ok: false,
          error: `Port ${localPort} is already exposed (tunnel: ${existing.name})`,
        });
        return;
      }

      const tsInfo = await getTailscaleInfo();
      if (!tsInfo.isRunning) {
        res.status(503).json({
          ok: false,
          error: 'Tailscale is not connected. Start Tailscale and try again.',
        });
        return;
      }

      const id = nanoid(10);
      const tunnel: Tunnel = {
        id,
        name: effectiveName,
        localPort,
        remotePort: localPort,
        token: token ?? null,
        createdAt: new Date().toISOString(),
        status: 'active',
      };

      state.tunnels.push(tunnel);
      state.tailscaleIp = tsInfo.ip;
      state.tailscaleHostname = tsInfo.hostname;
      state.daemonPid = process.pid;
      writeState(state);
      onTunnelChange();

      const host = tsInfo.hostname || tsInfo.ip;
      res.json({
        ok: true,
        tunnel,
        url: `http://${host}:${DASHBOARD_PORT}/${effectiveName}`,
      });
    } catch (err) {
      res.status(500).json({ ok: false, error: (err as Error).message });
    }
  });

  router.delete('/lm/api/tunnels/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const state = readState();

      let tunnel = state.tunnels.find((t) => t.id === id);
      if (!tunnel) {
        const port = parseInt(id, 10);
        tunnel = state.tunnels.find(
          (t) => t.localPort === port || t.name === id
        );
      }

      if (!tunnel) {
        res.status(404).json({ ok: false, error: `Tunnel not found: ${id}` });
        return;
      }

      const proxy = proxyCache.get(tunnel.localPort);
      if (proxy) {
        proxy.close();
        proxyCache.delete(tunnel.localPort);
      }

      state.tunnels = state.tunnels.filter((t) => t.id !== tunnel!.id);
      writeState(state);
      onTunnelChange();

      res.json({ ok: true, stopped: tunnel.name });
    } catch (err) {
      res.status(500).json({ ok: false, error: (err as Error).message });
    }
  });

  router.delete('/lm/api/tunnels', async (_req, res) => {
    try {
      for (const [port, proxy] of proxyCache) {
        proxy.close();
        proxyCache.delete(port);
      }
      const state = readState();
      state.tunnels = [];
      writeState(state);
      onTunnelChange();
      res.json({ ok: true, stopped: 'all' });
    } catch (err) {
      res.status(500).json({ ok: false, error: (err as Error).message });
    }
  });

  router.post('/lm/api/shutdown', (_req, res) => {
    res.json({ ok: true, message: 'Shutting down' });
    setTimeout(() => process.exit(0), 200);
  });

  return router;
}
