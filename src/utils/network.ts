// Tailscale CGNAT range: 100.64.0.0/10 (100.64.0.0 - 100.127.255.255)
export function isTailscaleOrLocal(ip: string): boolean {
  const clean = ip.replace(/^::ffff:/, '');
  if (clean === '127.0.0.1' || clean === '::1') return true;
  const parts = clean.split('.');
  if (parts.length !== 4) return false;
  const first = parseInt(parts[0], 10);
  const second = parseInt(parts[1], 10);
  return first === 100 && second >= 64 && second <= 127;
}
