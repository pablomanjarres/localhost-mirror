import type { Request, Response, NextFunction } from 'express';

// Tailscale CGNAT range: 100.64.0.0/10 (100.64.0.0 - 100.127.255.255)
function isTailscaleOrLocal(ip: string): boolean {
  const clean = ip.replace(/^::ffff:/, '');
  if (clean === '127.0.0.1' || clean === '::1') return true;
  const parts = clean.split('.');
  if (parts.length !== 4) return false;
  const first = parseInt(parts[0], 10);
  const second = parseInt(parts[1], 10);
  return first === 100 && second >= 64 && second <= 127;
}

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
