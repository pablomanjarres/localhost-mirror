import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { TAILSCALE_CLI_PATHS } from './utils/constants.js';

const execFileAsync = promisify(execFile);

export interface TailscaleInfo {
  ip: string;
  hostname: string;
  isRunning: boolean;
}

async function findTailscaleCli(): Promise<string | null> {
  for (const path of TAILSCALE_CLI_PATHS) {
    try {
      await execFileAsync(path, ['version']);
      return path;
    } catch {
      continue;
    }
  }
  return null;
}

export async function getTailscaleInfo(): Promise<TailscaleInfo> {
  const cli = await findTailscaleCli();
  if (!cli) {
    throw new Error(
      'Tailscale CLI not found. Install Tailscale and make sure it\'s in your PATH.'
    );
  }

  const { stdout } = await execFileAsync(cli, ['status', '--json']);
  const status = JSON.parse(stdout);

  const isRunning = status.BackendState === 'Running';
  const ips: string[] = status.Self?.TailscaleIPs ?? status.TailscaleIPs ?? [];
  const ip = ips.find((addr: string) => addr.includes('.')) ?? '';
  const rawDns: string = status.Self?.DNSName ?? '';
  const hostname = rawDns.replace(/\.$/, '');

  return { ip, hostname, isRunning };
}
