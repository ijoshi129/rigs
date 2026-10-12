import { useSyncExternalStore } from "react";
import { Switch2, Switch2Device, Switch2Simulator, type Switch2State, activePresetOf } from "../rigkit";
import { WebBluetoothTransport } from "../ble/webBluetoothTransport";
import { settings } from "./settings";

export interface Sample {
  t: number;
  f: number;
}

export interface RigSlot {
  device: Switch2Device;
  state: Switch2State;
  history: Sample[];
  deviceName: string;
  error?: string;
}

/** One logged session, kept in localStorage. */
export interface HistoryEntry {
  id: string;
  start: number;
  end?: number;
  targetF?: number;
  profile?: string;
  holdS?: number;
  peakF: number;
  extended?: boolean;
}

export interface Snapshot {
  bluetoothAvailable: boolean;
  mock: boolean;
  connecting: boolean;
  error?: string;
  rig?: RigSlot;
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

/** Single source of truth for the UI. Holds the rig and talks to the device. */
class RigStore {
  private snap: Snapshot;
  private listeners = new Set<() => void>();
  private simulator?: Switch2Simulator;
  private wasHeating = false;
  private open?: HistoryEntry;

  constructor() {
    const params = new URLSearchParams(location.search);
    const bluetoothAvailable = typeof navigator !== "undefined" && "bluetooth" in navigator;
    const mock = params.has("mock") || (!bluetoothAvailable && params.has("demo"));
    this.snap = { bluetoothAvailable, mock, connecting: false, history: loadLog() };
    if (mock) void this.startMock(params.has("demo"));
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

  // ---- Mock mode --------------------------------------------------------------

  private async startMock(demo: boolean) {
    this.simulator = new Switch2Simulator();
    const dev = new Switch2Device(this.simulator.transport);
    this.attach(dev, "Switch 2");
    await dev.connect();
    if (demo) setTimeout(() => void this.run("Start", () => dev.startSession()), 1000);
  }

  // ---- Real Bluetooth ---------------------------------------------------------

  /**
   * Opens the browser's device picker and connects the Switch 2.
   * `everything` lists every nearby device instead of filtering, for rigs
   * that advertise under an unexpected name or service.
   */
  async connect(everything = false) {
    if (this.snap.connecting) return;
    this.set({ connecting: true, error: undefined });
    try {
      const device = await navigator.bluetooth.requestDevice(
        everything
          ? { acceptAllDevices: true, optionalServices: Switch2.optionalServices }
          : {
              filters: [
                { services: [Switch2.UUIDs.controlService] },
                { services: [Switch2.UUIDs.fallbackService] },
                { namePrefix: "Switch" },
                { namePrefix: "SW2" },
                { namePrefix: "Dr" },
                { namePrefix: "DD" },
              ],
              optionalServices: Switch2.optionalServices,
            },
      );
      await this.connectDevice(device);
      localStorage.setItem(REMEMBERED_KEY, device.id);
    } catch (e) {
      if (!(e instanceof DOMException && e.name === "NotFoundError")) this.set({ error: describe(e) });
    } finally {
      this.set({ connecting: false });
    }
  }

  private async connectDevice(device: BluetoothDevice) {
    const transport = new WebBluetoothTransport(device);
    await transport.open(Switch2.optionalServices);
    const chars = Switch2.characteristicSets.find((c) => transport.has(c.notify) && transport.has(c.write));
    if (!chars) {
      const short = (u: string) => (u.startsWith("0000") && u.endsWith("-0000-1000-8000-00805f9b34fb") ? u.slice(4, 8) : u.slice(0, 8));
      const found = transport.services.map(short).join(", ") || "none we asked for";
      const chars = transport.characteristicUUIDs.map(short).join(", ") || "none";
      await transport.disconnect();
      throw new Error(`"${device.name ?? "that device"}" doesn't expose the Switch 2 control characteristics. Services found: ${found}. Characteristics: ${chars}.`);
    }
    const dev = new Switch2Device(transport, chars);
    this.attach(dev, device.name ?? "Switch 2");
    await dev.connect();
  }

  /** Reconnects the rig used last time, if the browser supports remembered devices. */
  async reconnectRemembered() {
    if (!this.snap.bluetoothAvailable || !("getDevices" in navigator.bluetooth) || this.snap.rig) return;
    const id = localStorage.getItem(REMEMBERED_KEY);
    if (!id) return;
    let devices: BluetoothDevice[];
    try { devices = await navigator.bluetooth.getDevices(); } catch { return; }
    const device = devices.find((d) => d.id === id);
    if (!device) return;
    this.set({ connecting: true });
    try { await this.connectDevice(device); } catch { /* not in range */ }
    this.set({ connecting: false });
  }

  async disconnect() {
    await this.snap.rig?.device.disconnect();
    this.set({ rig: undefined });
    localStorage.removeItem(REMEMBERED_KEY);
    settings.setRigColors(null);
  }

  // ---- The rig ----------------------------------------------------------------

  private attach(device: Switch2Device, deviceName: string) {
    this.set({ rig: { device, state: device.state, history: [], deviceName } });
    device.onUpdate((state) => {
      const slot = this.snap.rig;
      if (!slot || slot.device !== device) return;
      const st = state.status;
      const heating = st?.sessionActive ?? false;
      const f = st ? Switch2.statusF(st) : undefined;
      this.set({ rig: { ...slot, state, history: this.pushSample(slot.history, heating, f) } });
      this.trackSession(heating, f, () => {
        const p = activePresetOf(state);
        return { targetF: p?.fahrenheit, profile: Switch2.profileName(p?.profile) || undefined, holdS: p?.holdSeconds, extended: (st?.sessionExtend ?? 0) > 0 };
      });
      const code = st?.lightMode;
      const pair = code !== undefined ? lightModeColors[code] : undefined;
      settings.setRigColors(pair ? { a: pair[0], b: pair[1], c: pair[1] } : null);
    });
  }

  private pushSample(history: Sample[], heating: boolean, f: number | undefined): Sample[] {
    let h = history;
    if (heating && !this.wasHeating) h = [];
    if (f === undefined) return h;
    const last = h[h.length - 1];
    if (heating || !last || Math.abs(last.f - f) >= 1) {
      h = [...h, { t: Date.now(), f }];
      if (h.length > MAX_HISTORY) h = h.slice(h.length - MAX_HISTORY);
    }
    return h;
  }

  /** Opens a log entry when heating starts and closes it when it stops. */
  private trackSession(heating: boolean, f: number | undefined, details: () => Partial<HistoryEntry>) {
    const was = this.wasHeating;
    this.wasHeating = heating;
    if (heating && !was) {
      this.open = { id: String(Date.now()), start: Date.now(), peakF: f ?? 0, ...details() };
      return;
    }
    if (heating && this.open) {
      if (f !== undefined && f > this.open.peakF) this.open.peakF = Math.round(f);
      if (details().extended) this.open.extended = true;
      return;
    }
    if (!heating && was && this.open) {
      const entry = this.open;
      entry.end = Date.now();
      this.open = undefined;
      // A two-second abort is noise; keep sessions that got warm or ran a while.
      if (entry.peakF >= 200 || entry.end - entry.start > 10_000) {
        const history = [entry, ...this.snap.history].slice(0, 500);
        this.set({ history });
        saveLog(history);
      }
    }
  }

  clearHistory() {
    this.set({ history: [] });
    saveLog([]);
  }

  /** Runs a device command and surfaces any error on screen. */
  async run(label: string, op: () => Promise<void>) {
    try {
      await op();
      const slot = this.snap.rig;
      if (slot?.error) this.set({ rig: { ...slot, error: undefined } });
    } catch (e) {
      const slot = this.snap.rig;
      if (slot) this.set({ rig: { ...slot, error: `${label}: ${(e as Error).message}` } });
    }
  }
}

function loadLog(): HistoryEntry[] {
  try { return JSON.parse(localStorage.getItem(LOG_KEY) ?? "[]"); } catch { return []; }
}
function saveLog(h: HistoryEntry[]) {
  try { localStorage.setItem(LOG_KEY, JSON.stringify(h)); } catch { /* ignore */ }
}

function describe(e: unknown): string {
  if (e instanceof Error) {
    const k = (e as { kind?: string }).kind;
    if (k === "timeout") return "The Switch 2 timed out. Is it on, nearby, and closed in the official app?";
    if (e.name === "NetworkError") return "The Switch 2 dropped the connection during setup. Try again.";
    return `Switch 2: ${e.message}`;
  }
  return "Connection failed";
}

export const store = new RigStore();
export const useRig = () => useSyncExternalStore(store.subscribe, store.getSnapshot);
