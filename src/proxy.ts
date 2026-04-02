import http from 'node:http';
import httpProxy from 'http-proxy';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { Socket } from 'node:net';
import { isTailscaleOrLocal } from './utils/network.js';

export interface ProxyConfig {
  localPort: number;
  remotePort: number;
  listenHost: string;
  tailscaleOnly: boolean;
  token?: string | null;
}

export interface ProxyInstance {
  server: http.Server;
  proxy: httpProxy;
  config: ProxyConfig;
}

function send403(res: ServerResponse): void {
  res.writeHead(403, { 'Content-Type': 'text/html' });
  res.end(`
    <html><body style="font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#111;color:#fff">
      <div style="text-align:center"><h1>403</h1><p>Access restricted to Tailscale network</p></div>
    </body></html>
  `);
}

function checkToken(req: IncomingMessage, token: string): boolean {
  const auth = req.headers['authorization'];
  if (auth === `Bearer ${token}`) return true;

  const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
  if (url.searchParams.get('token') === token) return true;

  const remote = req.socket.remoteAddress ?? '';
  if (remote === '127.0.0.1' || remote === '::1') return true;

  return false;
}

function send401(res: ServerResponse): void {
  res.writeHead(401, { 'Content-Type': 'text/html' });
  res.end(`
    <html><body style="font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#111;color:#fff">
      <div style="text-align:center"><h1>401</h1><p>Token required. Add <code>?token=xxx</code> or <code>Authorization: Bearer xxx</code></p></div>
    </body></html>
  `);
}

function send502(res: ServerResponse, port: number): void {
  res.writeHead(502, { 'Content-Type': 'text/html' });
  res.end(`
    <html><body style="font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#111;color:#fff">
      <div style="text-align:center"><h1>502</h1><p>localhost:${port} is not responding</p></div>
    </body></html>
  `);
}

function checkAccess(req: IncomingMessage, config: ProxyConfig, res?: ServerResponse): boolean {
  // Check Tailscale CIDR
  if (config.tailscaleOnly) {
    const remote = req.socket.remoteAddress ?? '';
    if (!isTailscaleOrLocal(remote)) {
      if (res) send403(res);
      return false;
    }
  }

  // Check token
  if (config.token && !checkToken(req, config.token)) {
    if (res) send401(res);
    return false;
  }

  return true;
}

export function createProxy(config: ProxyConfig): Promise<ProxyInstance> {
  return new Promise((resolve, reject) => {
    const proxy = httpProxy.createProxyServer({
      target: `http://127.0.0.1:${config.localPort}`,
      ws: true,
      xfwd: true,
    });

    proxy.on('error', (_err: Error, _req: IncomingMessage, res: ServerResponse | Socket) => {
      if ('writeHead' in res) {
        send502(res as ServerResponse, config.localPort);
      }
    });

    const server = http.createServer((req, res) => {
      if (!checkAccess(req, config, res)) return;
      proxy.web(req, res);
    });

    server.on('upgrade', (req, socket, head) => {
      if (!checkAccess(req, config)) {
        socket.destroy();
        return;
      }
      proxy.ws(req, socket, head);
    });

    server.on('error', (err: NodeJS.ErrnoException) => {
      if (err.code === 'EADDRINUSE') {
        reject(new Error(
          `Port ${config.remotePort} is already in use. ` +
          `Try: lm expose ${config.localPort} --as ${config.remotePort + 10000}`
        ));
      } else {
        reject(err);
      }
    });

    server.listen(config.remotePort, config.listenHost, () => {
      resolve({ server, proxy, config });
    });
  });
}

export function destroyProxy(instance: ProxyInstance): Promise<void> {
  return new Promise((resolve) => {
    instance.proxy.close();
    instance.server.close(() => resolve());
  });
}
