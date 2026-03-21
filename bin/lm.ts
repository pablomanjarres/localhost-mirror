#!/usr/bin/env npx tsx
import { Command } from 'commander';
import { spawn, execSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import chalk from 'chalk';
import { MGMT_PORT, DAEMON_PID_FILE, DASHBOARD_PORT } from '../src/utils/constants.js';
import { log } from '../src/utils/logger.js';
import { readState } from '../src/store.js';
import { getTailscaleInfo } from '../src/tailscale.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DAEMON_SCRIPT = join(__dirname, '..', 'src', 'daemon.ts');

const program = new Command();
program.name('lm').description('Expose local ports securely over Tailscale').version('1.0.0');

// --- Helpers ---

async function mgmtFetch(path: string, options?: RequestInit): Promise<Response> {
  return fetch(`http://127.0.0.1:${MGMT_PORT}${path}`, options);
}

async function isDaemonRunning(): Promise<boolean> {
  try {
    const res = await mgmtFetch('/api/status');
    const data = await res.json() as { daemon?: boolean };
    return data.daemon === true;
  } catch {
    return false;
  }
}

async function ensureDaemon(): Promise<void> {
  if (await isDaemonRunning()) return;

  log.info('Starting daemon...');

  const child = spawn('npx', ['tsx', DAEMON_SCRIPT], {
    detached: true,
    stdio: 'ignore',
    cwd: join(__dirname, '..'),
  });
  child.unref();

  // Wait for daemon to be ready
  for (let i = 0; i < 30; i++) {
    await new Promise((r) => setTimeout(r, 200));
    if (await isDaemonRunning()) {
      log.success('Daemon started');
      return;
    }
  }

  log.error('Daemon failed to start. Check ~/.localhost-mirror/daemon.log');
  process.exit(1);
}

// --- Commands ---

program
  .command('expose <port>')
  .description('Expose a local port over Tailscale')
  .option('-n, --name <name>', 'Friendly name for the tunnel')
  .option('-a, --as <port>', 'Expose on a different external port', parseInt)
  .option('-t, --token', 'Require auth token for access')
  .action(async (portStr: string, opts) => {
    const localPort = parseInt(portStr, 10);
    if (isNaN(localPort) || localPort < 1 || localPort > 65535) {
      log.error('Invalid port number');
      process.exit(1);
    }

    await ensureDaemon();

    const body: Record<string, unknown> = { localPort };
    if (opts.name) body.name = opts.name;
    if (opts.as) body.remotePort = opts.as;
    if (opts.token) {
      const { nanoid } = await import('nanoid');
      body.token = nanoid(24);
    }

    try {
      const res = await mgmtFetch('/api/tunnels', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

      const data = await res.json() as {
        ok: boolean;
        error?: string;
        url?: string;
        tunnel?: { token?: string; name: string };
      };

      if (!data.ok) {
        log.error(data.error ?? 'Failed to create tunnel');
        process.exit(1);
      }

      log.success(`Exposing localhost:${localPort} → ${chalk.cyan(data.url)}`);
      if (data.tunnel?.token) {
        log.dim(`Token: ${data.tunnel.token}`);
        log.dim(`Full URL: ${data.url}?token=${data.tunnel.token}`);
      }
    } catch (err) {
      log.error(`Failed to connect to daemon: ${(err as Error).message}`);
      process.exit(1);
    }
  });

program
  .command('list')
  .alias('ls')
  .description('List active tunnels')
  .action(async () => {
    if (!(await isDaemonRunning())) {
      log.info('No daemon running. No active tunnels.');
      return;
    }

    try {
      const res = await mgmtFetch('/api/tunnels');
      const data = await res.json() as { tunnels: Array<{
        name: string;
        localPort: number;
        remotePort: number;
        status: string;
        token: string | null;
        createdAt: string;
      }> };

      if (data.tunnels.length === 0) {
        log.info('No active tunnels');
        return;
      }

      const state = readState();
      const host = state.tailscaleHostname || state.tailscaleIp || '?';

      console.log();
      console.log(
        chalk.dim('  NAME'.padEnd(20) + 'LOCAL'.padEnd(10) + 'URL'.padEnd(40) + 'STATUS')
      );
      console.log(chalk.dim('  ' + '─'.repeat(76)));

      for (const t of data.tunnels) {
        const statusColor = t.status === 'active' ? chalk.green : chalk.red;
        const url = `http://${host}:${DASHBOARD_PORT}/?tunnel=${t.localPort}`;
        console.log(
          `  ${t.name.padEnd(18)}` +
          `${chalk.dim(':' + t.localPort.toString().padEnd(8))}` +
          `${chalk.cyan(url.padEnd(38))}` +
          `${statusColor(t.status)}`
        );
      }
      console.log();
    } catch {
      log.error('Could not connect to daemon');
    }
  });

program
  .command('stop <target>')
  .description('Stop a tunnel by port, name, or "all"')
  .action(async (target: string) => {
    if (!(await isDaemonRunning())) {
      log.info('No daemon running');
      return;
    }

    try {
      if (target === 'all') {
        await mgmtFetch('/api/tunnels', { method: 'DELETE' });
        log.success('All tunnels stopped');
      } else {
        const res = await mgmtFetch(`/api/tunnels/${target}`, { method: 'DELETE' });
        const data = await res.json() as { ok: boolean; error?: string; stopped?: string };
        if (data.ok) {
          log.success(`Stopped tunnel: ${data.stopped}`);
        } else {
          log.error(data.error ?? 'Failed to stop tunnel');
        }
      }
    } catch {
      log.error('Could not connect to daemon');
    }
  });

program
  .command('status')
  .description('Show daemon and Tailscale status')
  .action(async () => {
    try {
      const tsInfo = await getTailscaleInfo();
      console.log();
      console.log(`  ${chalk.dim('Tailscale:')} ${tsInfo.isRunning ? chalk.green('connected') : chalk.red('disconnected')}`);
      if (tsInfo.ip) console.log(`  ${chalk.dim('IP:')}        ${tsInfo.ip}`);
      if (tsInfo.hostname) console.log(`  ${chalk.dim('Hostname:')} ${tsInfo.hostname}`);
    } catch (err) {
      console.log(`  ${chalk.dim('Tailscale:')} ${chalk.red('not found')}`);
    }

    const running = await isDaemonRunning();
    console.log(`  ${chalk.dim('Daemon:')}    ${running ? chalk.green('running') : chalk.dim('stopped')}`);

    if (running) {
      const res = await mgmtFetch('/api/status');
      const data = await res.json() as { pid?: number; tunnelCount?: number };
      console.log(`  ${chalk.dim('PID:')}       ${data.pid}`);
      console.log(`  ${chalk.dim('Tunnels:')}   ${data.tunnelCount}`);
    }
    console.log();
  });

program
  .command('dashboard')
  .description('Open the tunnel dashboard in your browser')
  .action(async () => {
    const state = readState();
    const host = state.tailscaleHostname || state.tailscaleIp;
    if (!host) {
      log.error('No Tailscale info found. Run `lm expose` first.');
      process.exit(1);
    }

    const url = `http://${host}:${DASHBOARD_PORT}/lm/`;
    log.info(`Opening ${chalk.cyan(url)}`);

    try {
      execSync(`open "${url}"`);
    } catch {
      log.info(`Open in your browser: ${url}`);
    }
  });

program
  .command('shutdown')
  .description('Stop daemon and all tunnels')
  .action(async () => {
    if (!(await isDaemonRunning())) {
      log.info('No daemon running');
      return;
    }

    try {
      await mgmtFetch('/api/shutdown', { method: 'POST' });
      log.success('Daemon shut down');
    } catch {
      log.error('Could not connect to daemon');
    }
  });

program.parse();
