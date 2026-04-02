import type { Request, Response, NextFunction } from 'express';
import { isTailscaleOrLocal } from './utils/network.js';

// Management API — only allow localhost
export function localOnly(req: Request, res: Response, next: NextFunction): void {
  const remote = req.socket.remoteAddress ?? '';
  const clean = remote.replace(/^::ffff:/, '');
  if (clean === '127.0.0.1' || clean === '::1') {
    next();
    return;
  }
  res.status(403).json({ error: 'Management API is localhost-only' });
}

// Dashboard + tunnels — allow Tailscale network + localhost
export function tailscaleOnly(req: Request, res: Response, next: NextFunction): void {
  const remote = req.socket.remoteAddress ?? '';
  if (isTailscaleOrLocal(remote)) {
    next();
    return;
  }
  res.status(403).json({ error: 'Access restricted to Tailscale network' });
}
