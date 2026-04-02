import { homedir } from 'node:os';
import { join } from 'node:path';

export const STATE_DIR = join(homedir(), '.localhost-mirror');
export const STATE_FILE = join(STATE_DIR, 'state.json');
export const DAEMON_PID_FILE = join(STATE_DIR, 'daemon.pid');
export const DAEMON_LOG_FILE = join(STATE_DIR, 'daemon.log');

export const MGMT_PORT = parseInt(process.env.LM_MGMT_PORT || '19099', 10);
export const DASHBOARD_PORT = parseInt(process.env.LM_DASHBOARD_PORT || '19100', 10);

export const TAILSCALE_CLI_PATHS = [
  'tailscale',
  '/Applications/Tailscale.app/Contents/MacOS/Tailscale',
  '/usr/bin/tailscale',
  '/usr/local/bin/tailscale',
];

export const HEALTH_CHECK_INTERVAL_MS = 10_000;
export const DAEMON_SHUTDOWN_GRACE_MS = 60_000;
