import express from 'express';
import http from 'node:http';
import { writeFileSync, unlinkSync } from 'node:fs';
import { createApiRouter, createMainHandler, handleUpgrade, getTunnelsFromState, updateTunnelStatus, getProxyCache } from './api.js';
import { tailscaleOnly } from './auth.js';
import { createDashboardRouter } from './dashboard/server.js';
import { startHealthChecker } from './health.js';
import { readState, writeState, ensureStateDir } from './store.js';
import { getTailscaleInfo } from './tailscale.js';
import { MGMT_PORT, DASHBOARD_PORT, DAEMON_PID_FILE, DAEMON_SHUTDOWN_GRACE_MS } from './utils/constants.js';

let shutdownTimer: NodeJS.Timeout | null = null;

function scheduleAutoShutdown(): void {
  if (shutdownTimer) clearTimeout(shutdownTimer);
  const state = readState();
  if (state.tunnels.length === 0) {
    shutdownTimer = setTimeout(() => {
      console.log('[daemon] No active tunnels, shutting down');
      cleanup();
      process.exit(0);
    }, DAEMON_SHUTDOWN_GRACE_MS);
  }
}

function cancelAutoShutdown(): void {
  if (shutdownTimer) {
    clearTimeout(shutdownTimer);
    shutdownTimer = null;
  }
}

function onTunnelChange(): void {
  const state = readState();
  if (state.tunnels.length === 0) {
    scheduleAutoShutdown();
  } else {
    cancelAutoShutdown();
  }
}

function cleanup(): void {
  try { unlinkSync(DAEMON_PID_FILE); } catch {}
  const state = readState();
  state.tunnels = [];
  state.daemonPid = null;
  writeState(state);
}

async function main(): Promise<void> {
  ensureStateDir();

  writeFileSync(DAEMON_PID_FILE, String(process.pid));

  const state = readState();
  state.tunnels = [];
  state.daemonPid = process.pid;
  writeState(state);

  // Management API (localhost only, for CLI)
  const mgmtApp = express();
  mgmtApp.use(express.json());

  // CLI uses /api/* paths (without /lm prefix)
  const mgmtRouter = createApiRouter(onTunnelChange);
  // Alias /api/* to /lm/api/* for the CLI
  mgmtApp.use('/api', (req, res, next) => {
    req.url = '/lm/api' + req.url;
    mgmtRouter(req, res, next);
  });
  mgmtApp.use(mgmtRouter);

  mgmtApp.listen(MGMT_PORT, '127.0.0.1', () => {
    console.log(`[daemon] Management API on http://127.0.0.1:${MGMT_PORT}`);
  });

  // Main server on 0.0.0.0:19100
  try {
    const tsInfo = await getTailscaleInfo();

    // Express app handles /lm/* (dashboard + API)
    const app = express();
    app.use(tailscaleOnly);
    app.use('/lm', createDashboardRouter());
    app.use(express.json());
    app.use(createApiRouter(onTunnelChange));

    // Main handler: cookie-based proxy + tunnel switching
    const mainHandler = createMainHandler();

    // Raw HTTP server so we can intercept before Express
    const server = http.createServer((req, res) => {
      // Tailscale CIDR check
      const remote = (req.socket.remoteAddress ?? '').replace(/^::ffff:/, '');
      const isLocal = remote === '127.0.0.1' || remote === '::1';
      const parts = remote.split('.');
      const isTailscale = parts.length === 4 &&
        parseInt(parts[0], 10) === 100 &&
        parseInt(parts[1], 10) >= 64 &&
        parseInt(parts[1], 10) <= 127;

      if (!isLocal && !isTailscale) {
        res.writeHead(403, { 'Content-Type': 'text/plain' });
        res.end('Tailscale access only');
        return;
      }

      // Try main handler first (cookie proxy, ?tunnel=, ?clear)
      // If it doesn't handle it (returns without ending response), fall through to Express
      const url = req.url ?? '/';

      // Routes that go to Express (/lm/*)
      if (url.startsWith('/lm')) {
        app(req, res);
        return;
      }

      // Everything else: main handler (proxy via cookie, or redirect to /lm/)
      mainHandler(req, res);
    });

    // WebSocket upgrade
    server.on('upgrade', (req, socket, head) => {
      const remote = (req.socket.remoteAddress ?? '').replace(/^::ffff:/, '');
      const isLocal = remote === '127.0.0.1' || remote === '::1';
      const parts = remote.split('.');
      const isTailscale = parts.length === 4 &&
        parseInt(parts[0], 10) === 100 &&
        parseInt(parts[1], 10) >= 64 &&
        parseInt(parts[1], 10) <= 127;

      if (!isLocal && !isTailscale) {
        socket.destroy();
        return;
      }

      handleUpgrade(req, socket, head);
    });

    server.listen(DASHBOARD_PORT, '0.0.0.0', () => {
      const host = tsInfo.hostname || tsInfo.ip || 'localhost';
      console.log(`[daemon] Server on http://${host}:${DASHBOARD_PORT}`);
      console.log(`[daemon] Dashboard: http://${host}:${DASHBOARD_PORT}/lm/`);
    });

    state.tailscaleIp = tsInfo.ip;
    state.tailscaleHostname = tsInfo.hostname;
    writeState(state);
  } catch (err) {
    console.log(`[daemon] Could not start server: ${(err as Error).message}`);
  }

  startHealthChecker(getTunnelsFromState, updateTunnelStatus);
  scheduleAutoShutdown();

  const onSignal = async () => {
    console.log('[daemon] Shutting down...');
    for (const [, p] of getProxyCache()) {
      p.close();
    }
    cleanup();
    process.exit(0);
  };

  process.on('SIGTERM', onSignal);
  process.on('SIGINT', onSignal);

  console.log(`[daemon] PID ${process.pid} ready`);
}

main().catch((err) => {
  console.error('[daemon] Fatal:', err);
  process.exit(1);
});
