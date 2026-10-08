import { bytes, cleanString } from "../transport";
import { type Analytics, type CurvePoint, type HardwareStatus, type HeatingProfile, type Message, type Status, emptyPoint, isEmptyPoint } from "./protocol";

export interface Preset {
  /** 0–5 as the device numbers them. 1–5 are the buttons; 0 is the live slot. */
  index: number;
  fahrenheit?: number;
  celsius?: number;
  holdSeconds?: number;
  profile?: HeatingProfile;
  curve: CurvePoint[];
}
export const curvePoints = (p: Preset) => p.curve.filter((pt) => !isEmptyPoint(pt));

/** Everything known about one Switch 2, built up from its packets. */
export interface Switch2State {
  status?: Status;
  presets: Preset[];
  activePreset?: number;
  analytics: Analytics;
  firmwareVersion?: string;
  secondaryVersion?: string;
  name?: string;
  hardware?: HardwareStatus;
  cleaningActive: boolean;
  factoryResetStatus: number;
  deviceClock?: { year: number; month: number; day: number; hour: number; minute: number };
  packetsReceived: number;
  connected: boolean;
  nameBuffer: Uint8Array;
}

export const initialSwitch2State = (): Switch2State => ({
  presets: Array.from({ length: 6 }, (_, index) => ({ index, curve: Array.from({ length: 6 }, emptyPoint) })),
  analytics: {},
  cleaningActive: false,
  factoryResetStatus: 0,
  packetsReceived: 0,
  connected: false,
  nameBuffer: new Uint8Array(),
});

/** The official app treats the post-clock-sync dump as done after 13 packets. */
export const initialDumpComplete = (s: Switch2State) => s.packetsReceived >= 13;

export const activePresetOf = (s: Switch2State): Preset | undefined => {
  const i = s.activePreset ?? s.status?.activePreset;
  return i === undefined ? undefined : s.presets[i];
};

/** Returns a new state with the message applied (state is treated as immutable). */
export function applyMessage(s: Switch2State, m: Message): Switch2State {
  const n: Switch2State = { ...s, packetsReceived: s.packetsReceived + 1, presets: s.presets.map((p) => ({ ...p, curve: [...p.curve] })) };
  const preset = (i: number) => n.presets[i];
  switch (m.type) {
    case "clock":
      n.deviceClock = { year: m.year, month: m.month, day: m.day, hour: m.hour, minute: m.minute };
      break;
    case "analytics":
      n.analytics = { ...n.analytics, ...Object.fromEntries(Object.entries(m.analytics).filter(([, v]) => v !== undefined)) };
      break;
    case "presetTemperature": {
      const p = preset(m.preset);
      if (p) { p.fahrenheit = m.fahrenheit; p.celsius = m.celsius; }
      break;
    }
    case "presetProfile": {
      const p = preset(m.preset);
      if (p) p.profile = m.profile;
      break;
    }
    case "presetHoldTime": {
      const p = preset(m.preset);
      if (p) p.holdSeconds = m.seconds;
      break;
    }
    case "activePreset":
      n.activePreset = m.preset;
      break;
    case "status":
      n.status = m.status;
      n.activePreset = m.status.activePreset;
      break;
    case "customCurve": {
      const p = preset(m.preset);
      if (p) m.points.forEach((pt, i) => { if (m.startIndex + i < 6) p.curve[m.startIndex + i] = pt; });
      break;
    }
    case "nameChunk":
      if (m.final) {
        n.name = cleanString(bytes(n.nameBuffer, m.data));
        n.nameBuffer = new Uint8Array();
      } else {
        n.nameBuffer = m.data;
      }
      break;
    case "firmwareVersion":
      n.firmwareVersion = m.version;
      break;
    case "secondaryVersion":
      n.secondaryVersion = m.version;
      break;
    case "hardware":
      n.hardware = m.hardware;
      break;
    case "maintenance":
      n.cleaningActive = m.cleaningActive;
      n.factoryResetStatus = m.factoryResetStatus;
      break;
    case "unknown":
      break;
  }
  return n;
}
