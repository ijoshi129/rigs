import { useSyncExternalStore } from "react";
import {
  Lorax, PeakProDevice, PeakProSimulator, type PeakProState, Switch2, Switch2Device, Switch2Simulator,
  type Switch2State, activePresetOf, activeProfileOf, isHeating,
} from "../rigkit";
import { WebBluetoothTransport } from "../ble/webBluetoothTransport";
import { settings } from "./settings";

export type RigKind = "switch2" | "peakPro";
export const rigName: Record<RigKind, string> = { switch2: "Switch 2", peakPro: "Peak Pro" };

export interface Sample {
  t: number;
  f: number;
}

export interface Switch2Slot {
  kind: "switch2";
  device: Switch2Device;
  state: Switch2State;
  history: Sample[];
  deviceName: string;
  error?: string;
}
export interface PeakProSlot {
  kind: "peakPro";
  device: PeakProDevice;
  state: PeakProState;
  history: Sample[];
  deviceName: string;
  error?: string;
}
export type Slot = Switch2Slot | PeakProSlot;

/** One logged session, kept in localStorage. */
export interface HistoryEntry {
  id: string;
  rig: RigKind;
  start: number;
  end?: number;
  targetF?: number;
  profile?: string;
  holdS?: number;
  peakF: number;
  extended?: boolean;
  boosted?: boolean;
}

export interface Snapshot {
  bluetoothAvailable: boolean;
  mock: boolean;
  connecting?: RigKind;
  error?: string;
  activeRig: RigKind;
  switch2?: Switch2Slot;
  peakPro?: PeakProSlot;
  history: HistoryEntry[];
}

const MAX_HISTORY = 900;
const REMEMBERED_KEY = "rigs.remembered";
const LOG_KEY = "rigs.history";

/** The Switch 2's LED modes as wallpaper color pairs, used by the "Rig" wallpaper. */
export const lightModeColors: Record<number, [string, string]> = {
  0: ["#3a3f4a", "#1d2430"], 1: ["#d9d4c7", "#8a8577"], 2: ["#8a3ffc", "#4a1d8a"], 3: ["#2f6bff", "#1d2f8a"],
  4: ["#22c7e6", "#0f4d5a"], 5: ["#3ccf6a", "#0f4d3a"], 6: ["#f4d13d", "#8a6b0f"], 7: ["#ff8a2b", "#8a3a0f"],
  8: ["#e8383d", "#6a0f1d"], 9: ["#ff5fb0", "#8a1d5a"], 10: ["#ff8a2b", "#8b2fd6"], 11: ["#5b2cc9", "#c04bff"],
  12: ["#0fa38a", "#6a3be0"], 13: ["#ff2d95", "#22c7e6"], 14: ["#2f6bff", "#9ad5ff"], 15: ["#e8383d", "#ff9bb3"],
  16: ["#ff8a2b", "#3ccf6a"], 17: ["#b7ff3d", "#3ccf6a"], 24: ["#2f6bff", "#f4d13d"], 25: ["#f4d13d", "#ff8a2b"],
  26: ["#8a3ffc", "#3ccf6a"], 27: ["#ff2d95", "#22c7e6"], 28: ["#5b2cc9", "#ff5fb0"], 29: ["#ff8a2b", "#f4d13d"],
  30: ["#e8383d", "#3a0f0f"], 31: ["#d9d4c7", "#3a3f4a"], 32: ["#3ccf6a", "#5b2cc9"], 33: ["#ff8a2b", "#1d0f0a"],
};

/** Single source of truth for the UI. Holds the two rig slots and talks to the devices. */
class RigStore {
  private snap: Snapshot;
  private listeners = new Set<() => void>();
  private simulators: unknown[] = [];
  private wasHeating: Record<RigKind, boolean> = { switch2: false, peakPro: false };
  private open: Partial<Record<RigKind, HistoryEntry>> = {};

  constructor() {
    const params = new URLSearchParams(location.search);
    const bluetoothAvailable = typeof navigator !== "undefined" && "bluetooth" in navigator;
    const mock = params.has("mock") || (!bluetoothAvailable && params.has("demo"));
    this.snap = { bluetoothAvailable, mock, activeRig: "switch2", history: loadLog() };
    if (mock) void this.startMocks(params.has("demo"));
  }

  subscribe = (l: () => void) => {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  };
  getSnapshot = () => this.snap;

  private set(patch: Partial<Snapshot>) {
    this.snap = { ...this.snap, ...patch };
    for (const l of this.listeners) l();
  }

  get activeSlot(): Slot | undefined {
    return this.snap[this.snap.activeRig] ?? this.snap.switch2 ?? this.snap.peakPro;
  }

  setActiveRig(kind: RigKind) {
    this.set({ activeRig: kind });
    this.pushRigColors();
  }

  // ---- Mock mode --------------------------------------------------------------

  private async startMocks(demo: boolean) {
    const s = new Switch2Simulator();
    const p = new PeakProSimulator();
    this.simulators.push(s, p);
    const sDev = new Switch2Device(s.transport);
    const pDev = new PeakProDevice(p.transport);
    this.attachSwitch2(sDev, "Switch 2");
    this.attachPeakPro(pDev, "Peak Pro");
    await sDev.connect();
    await pDev.connect();
    pDev.startPolling();
    if (demo) {
      setTimeout(() => {
        void this.run("switch2", "Start", () => sDev.startSession());
        void this.run("peakPro", "Start", () => pDev.startSession());
      }, 1000);
    }
  }

  // ---- Real Bluetooth ---------------------------------------------------------

  /** Opens the browser's device picker for one kind of rig and connects it. */
  async connect(kind: RigKind) {
    if (this.snap.connecting) return;
    this.set({ connecting: kind, error: undefined });
    try {
      const device = await navigator.bluetooth.requestDevice(
        kind === "switch2"
          ? { filters: [{ services: [Switch2.UUIDs.controlService] }], optionalServices: Switch2.optionalServices }
          : {
              filters: [{ services: [Lorax.UUIDs.legacyService] }, { services: [Lorax.UUIDs.service] }, { namePrefix: "Peak" }],
              optionalServices: Lorax.optionalServices,
            },
      );
      await this.connectDevice(kind, device);
      this.remember(kind, device.id);
      this.set({ activeRig: kind });
    } catch (e) {
      if (!(e instanceof DOMException && e.name === "NotFoundError")) this.set({ error: describe(kind, e) });
    } finally {
      this.set({ connecting: undefined });
    }
  }

  private async connectDevice(kind: RigKind, device: BluetoothDevice) {
    const transport = new WebBluetoothTransport(device);
    const name = device.name ?? rigName[kind];
    if (kind === "switch2") {
      await transport.open(Switch2.optionalServices);
      const chars = transport.has(Switch2.UUIDs.controlNotify) ? Switch2.CONTROL : Switch2.FALLBACK;
      const dev = new Switch2Device(transport, chars);
      this.attachSwitch2(dev, name);
      await dev.connect();
    } else {
      await transport.open(Lorax.optionalServices);
      const dev = new PeakProDevice(transport);
      this.attachPeakPro(dev, name);
      await dev.connect();
      dev.startPolling();
    }
  }

  /** Reconnects rigs used before, if the browser supports remembered devices. */
  async reconnectRemembered() {
    if (!this.snap.bluetoothAvailable || !("getDevices" in navigator.bluetooth)) return;
    let devices: BluetoothDevice[];
    try { devices = await navigator.bluetooth.getDevices(); } catch { return; }
    for (const [kind, id] of Object.entries(this.remembered()) as [RigKind, string][]) {
      const device = devices.find((d) => d.id === id);
      if (!device || this.snap[kind]) continue;
      this.set({ connecting: kind });
      try { await this.connectDevice(kind, device); } catch { /* not in range */ }
      this.set({ connecting: undefined });
    }
  }

  async disconnect(kind: RigKind) {
    const slot = this.snap[kind];
    if (slot) await slot.device.disconnect();
    this.set({ [kind]: undefined });
    const r = this.remembered();
    delete r[kind];
    localStorage.setItem(REMEMBERED_KEY, JSON.stringify(r));
  }

  private remembered(): Partial<Record<RigKind, string>> {
    try { return JSON.parse(localStorage.getItem(REMEMBERED_KEY) ?? "{}"); } catch { return {}; }
  }
  private remember(kind: RigKind, id: string) {
    localStorage.setItem(REMEMBERED_KEY, JSON.stringify({ ...this.remembered(), [kind]: id }));
  }

  // ---- Slots ------------------------------------------------------------------

  private attachSwitch2(device: Switch2Device, deviceName: string) {
    this.set({ switch2: { kind: "switch2", device, state: device.state, history: [], deviceName } });
    device.onUpdate((state) => {
      const slot = this.snap.switch2;
      if (!slot || slot.device !== device) return;
      const st = state.status;
      const heating = st?.sessionActive ?? false;
      const f = st ? Switch2.statusF(st) : undefined;
      this.set({ switch2: { ...slot, state, history: this.pushSample("switch2", slot.history, heating, f) } });
      this.trackSession("switch2", heating, f, () => {
        const p = activePresetOf(state);
        return { targetF: p?.fahrenheit, profile: Switch2.profileName(p?.profile) || undefined, holdS: p?.holdSeconds, extended: (st?.sessionExtend ?? 0) > 0 };
      });
      this.pushRigColors();
    });
  }

  private attachPeakPro(device: PeakProDevice, deviceName: string) {
    this.set({ peakPro: { kind: "peakPro", device, state: device.state, history: [], deviceName } });
    device.onUpdate((state) => {
      const slot = this.snap.peakPro;
      if (!slot || slot.device !== device) return;
      const heating = isHeating(state);
      this.set({ peakPro: { ...slot, state, history: this.pushSample("peakPro", slot.history, heating, state.temperatureFahrenheit) } });
      this.trackSession("peakPro", heating, state.temperatureFahrenheit, () => {
        const p = activeProfileOf(state);
        return { targetF: p.fahrenheit !== undefined ? Math.round(p.fahrenheit) : undefined, profile: p.name || undefined, holdS: p.seconds !== undefined ? Math.round(p.seconds) : undefined };
      });
      this.pushRigColors();
    });
  }

  private pushSample(kind: RigKind, history: Sample[], heating: boolean, f: number | undefined): Sample[] {
    let h = history;
    if (heating && !this.wasHeating[kind]) h = [];
    if (f === undefined) return h;
    const last = h[h.length - 1];
    if (heating || !last || Math.abs(last.f - f) >= 1) {
      h = [...h, { t: Date.now(), f }];
      if (h.length > MAX_HISTORY) h = h.slice(h.length - MAX_HISTORY);
    }
    return h;
  }

  /** Opens a log entry when heating starts and closes it when it stops. */
  private trackSession(kind: RigKind, heating: boolean, f: number | undefined, details: () => Partial<HistoryEntry>) {
    const was = this.wasHeating[kind];
    this.wasHeating[kind] = heating;
    const open = this.open[kind];
    if (heating && !was) {
      this.open[kind] = { id: `${Date.now()}-${kind}`, rig: kind, start: Date.now(), peakF: f ?? 0, ...details() };
      return;
    }
    if (heating && open) {
      if (f !== undefined && f > open.peakF) open.peakF = Math.round(f);
      const d = details();
      if (d.extended) open.extended = true;
      return;
    }
    if (!heating && was && open) {
      open.end = Date.now();
      delete this.open[kind];
      // Only keep sessions that actually got warm; a 2-second abort is noise.
      if (open.peakF >= 200 || open.end - open.start > 10_000) {
        const history = [open, ...this.snap.history].slice(0, 500);
        this.set({ history });
        saveLog(history);
      }
    }
  }

  noteBoost(kind: RigKind) {
    const open = this.open[kind];
    if (open) open.boosted = true;
  }

  clearHistory() {
    this.set({ history: [] });
    saveLog([]);
  }

  /** Feeds the active rig's lighting into the "Rig" wallpaper. */
  private pushRigColors() {
    const slot = this.activeSlot;
    if (!slot) { settings.setRigColors(null); return; }
    if (slot.kind === "switch2") {
      const code = slot.state.status?.lightMode;
      const pair = code !== undefined ? lightModeColors[code] : undefined;
      settings.setRigColors(pair ? { a: pair[0], b: pair[1], c: pair[1] } : null);
    } else {
      const c = activeProfileOf(slot.state).color ?? slot.state.lanternColor;
      if (!c) { settings.setRigColors(null); return; }
      const hex = `#${[c.red, c.green, c.blue].map((v) => v.toString(16).padStart(2, "0")).join("")}`;
      settings.setRigColors({ a: hex, b: "#1d2f4a", c: "#2a1d4a" });
    }
  }

  /** Runs a device command and surfaces any error on the rig's screen. */
  async run(kind: RigKind, label: string, op: () => Promise<void>) {
    try {
      await op();
      const slot = this.snap[kind];
      if (slot?.error) this.set({ [kind]: { ...slot, error: undefined } });
    } catch (e) {
      const slot = this.snap[kind];
      if (slot) this.set({ [kind]: { ...slot, error: `${label}: ${(e as Error).message}` } });
    }
  }
}

function loadLog(): HistoryEntry[] {
  try { return JSON.parse(localStorage.getItem(LOG_KEY) ?? "[]"); } catch { return []; }
}
function saveLog(h: HistoryEntry[]) {
  try { localStorage.setItem(LOG_KEY, JSON.stringify(h)); } catch { /* ignore */ }
}

function describe(kind: RigKind, e: unknown): string {
  const name = rigName[kind];
  if (e instanceof Error) {
    const k = (e as { kind?: string }).kind;
    if (k === "timeout") return `${name} timed out. Is it on, nearby, and closed in the official app?`;
    if (k === "authenticationFailed") return `${name} refused the handshake.`;
    if (e.name === "NetworkError") return `${name} dropped the connection during setup. Try again.`;
    return `${name}: ${e.message}`;
  }
  return `${name}: connection failed`;
}

export const store = new RigStore();
export const useRigs = () => useSyncExternalStore(store.subscribe, store.getSnapshot);
