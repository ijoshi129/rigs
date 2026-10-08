import { useSyncExternalStore } from "react";
import {
  Lorax, PeakProDevice, PeakProSimulator, type PeakProState, Switch2, Switch2Device, Switch2Simulator,
  type Switch2State, isHeating,
} from "../rigkit";
import { WebBluetoothTransport } from "../ble/webBluetoothTransport";

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

export interface Snapshot {
  bluetoothAvailable: boolean;
  mock: boolean;
  connecting?: RigKind;
  error?: string;
  switch2?: Switch2Slot;
  peakPro?: PeakProSlot;
}

const MAX_HISTORY = 900;
const REMEMBERED_KEY = "rigs.remembered";

/** Single source of truth for the UI. Holds the two rig slots and talks to the devices. */
class RigStore {
  private snap: Snapshot;
  private listeners = new Set<() => void>();
  private simulators: unknown[] = [];
  private wasHeating: Record<RigKind, boolean> = { switch2: false, peakPro: false };

  constructor() {
    const params = new URLSearchParams(location.search);
    const bluetoothAvailable = typeof navigator !== "undefined" && "bluetooth" in navigator;
    const mock = params.has("mock") || (!bluetoothAvailable && params.has("demo"));
    this.snap = { bluetoothAvailable, mock };
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
    });
  }

  private attachPeakPro(device: PeakProDevice, deviceName: string) {
    this.set({ peakPro: { kind: "peakPro", device, state: device.state, history: [], deviceName } });
    device.onUpdate((state) => {
      const slot = this.snap.peakPro;
      if (!slot || slot.device !== device) return;
      this.set({ peakPro: { ...slot, state, history: this.pushSample("peakPro", slot.history, isHeating(state), state.temperatureFahrenheit) } });
    });
  }

  private pushSample(kind: RigKind, history: Sample[], heating: boolean, f: number | undefined): Sample[] {
    let h = history;
    if (heating && !this.wasHeating[kind]) h = [];
    this.wasHeating[kind] = heating;
    if (f === undefined) return h;
    const last = h[h.length - 1];
    if (heating || !last || Math.abs(last.f - f) >= 1) {
      h = [...h, { t: Date.now(), f }];
      if (h.length > MAX_HISTORY) h = h.slice(h.length - MAX_HISTORY);
    }
    return h;
  }

  /** Runs a device command and surfaces any error on the rig's deck. */
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

function describe(kind: RigKind, e: unknown): string {
  const name = rigName[kind];
  if (e instanceof Error) {
    if ("kind" in e && (e as { kind: string }).kind === "timeout") return `${name} timed out. Is it on, nearby, and closed in the official app?`;
    if ("kind" in e && (e as { kind: string }).kind === "authenticationFailed") return `${name} refused the handshake.`;
    if (e.name === "NetworkError") return `${name} dropped the connection during setup. Try again.`;
    return `${name}: ${e.message}`;
  }
  return `${name}: connection failed`;
}

export const store = new RigStore();
export const useRigs = () => useSyncExternalStore(store.subscribe, store.getSnapshot);
