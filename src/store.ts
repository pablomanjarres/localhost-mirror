import { mkdirSync, readFileSync, writeFileSync, renameSync } from 'node:fs';
import { join } from 'node:path';
import { STATE_DIR, STATE_FILE } from './utils/constants.js';

export interface Tunnel {
  id: string;
  name: string;
  localPort: number;
  remotePort: number;
  token: string | null;
  createdAt: string;
  status: 'active' | 'target-down' | 'error';
}

export interface State {
  tunnels: Tunnel[];
  daemonPid: number | null;
  tailscaleIp: string;
  tailscaleHostname: string;
}

function defaultState(): State {
  return {
    tunnels: [],
    daemonPid: null,
    tailscaleIp: '',
    tailscaleHostname: '',
  };
}

export function ensureStateDir(): void {
  mkdirSync(STATE_DIR, { recursive: true });
}

export function readState(): State {
  try {
    const raw = readFileSync(STATE_FILE, 'utf-8');
    return { ...defaultState(), ...JSON.parse(raw) };
  } catch {
    return defaultState();
  }
}

export function writeState(state: State): void {
  ensureStateDir();
  const tmp = join(STATE_DIR, 'state.tmp.json');
  writeFileSync(tmp, JSON.stringify(state, null, 2));
  renameSync(tmp, STATE_FILE);
}

export function addTunnel(tunnel: Tunnel): State {
  const state = readState();
  state.tunnels.push(tunnel);
  writeState(state);
  return state;
}

export function removeTunnel(id: string): State {
  const state = readState();
  state.tunnels = state.tunnels.filter((t) => t.id !== id);
  writeState(state);
  return state;
}

export function updateTunnel(id: string, updates: Partial<Tunnel>): State {
  const state = readState();
  const tunnel = state.tunnels.find((t) => t.id === id);
  if (tunnel) {
    Object.assign(tunnel, updates);
    writeState(state);
  }
  return state;
}

export function findTunnel(portOrName: string): Tunnel | undefined {
  const state = readState();
  const port = parseInt(portOrName, 10);
  return state.tunnels.find(
    (t) => t.localPort === port || t.remotePort === port || t.name === portOrName || t.id === portOrName
  );
}
