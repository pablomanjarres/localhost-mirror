import http from 'node:http';
import { HEALTH_CHECK_INTERVAL_MS } from './utils/constants.js';
import type { Tunnel } from './store.js';

type StatusCallback = (id: string, status: Tunnel['status']) => void;

export function startHealthChecker(
  getTunnels: () => Tunnel[],
  onStatusChange: StatusCallback
): NodeJS.Timeout {
  return setInterval(() => {
    for (const tunnel of getTunnels()) {
      checkPort(tunnel.localPort).then((alive) => {
        const newStatus = alive ? 'active' : 'target-down';
        if (tunnel.status !== newStatus) {
          onStatusChange(tunnel.id, newStatus);
        }
      });
    }
  }, HEALTH_CHECK_INTERVAL_MS);
}

function checkPort(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const req = http.request(
      { hostname: '127.0.0.1', port, method: 'HEAD', timeout: 2000 },
      (res) => {
        res.resume();
        resolve(true);
      }
    );
    req.on('error', () => resolve(false));
    req.on('timeout', () => {
      req.destroy();
      resolve(false);
    });
    req.end();
  });
}
