/**
 * Dr. Dabber Switch 2 wire protocol.
 * Packets are `[opcode, length, payload..., opcode]`, big-endian, unencrypted.
 * Read from the official web app at drdabber.app.
 */
import { RigKitError, be16, be32, byte, bytes, cleanString, hi, lo, Temperature } from "../transport";

export const UUIDs = {
  controlService: "0000fee7-0000-1000-8000-00805f9b34fb",
  controlWrite: "0000fec1-0000-1000-8000-00805f9b34fb",
  controlNotify: "0000fec2-0000-1000-8000-00805f9b34fb",
  fallbackService: "f56598fa-3ffa-41a7-9726-3fc69baeca1d",
  fallbackWrite: "2c759c29-a73c-45ab-a799-31d6a032f6af",
  fallbackNotify: "744c98ff-83c6-45d5-bd0c-52a50589215b",
  otaService: "e5c7a653-7e52-4b06-af32-960455084ae3",
  deviceInformation: "0000180a-0000-1000-8000-00805f9b34fb",
  modelNumber: "00002a24-0000-1000-8000-00805f9b34fb",
  serialNumber: "00002a25-0000-1000-8000-00805f9b34fb",
  hardwareRevision: "00002a27-0000-1000-8000-00805f9b34fb",
  softwareRevision: "00002a28-0000-1000-8000-00805f9b34fb",
  manufacturer: "00002a29-0000-1000-8000-00805f9b34fb",
  batteryService: "0000180f-0000-1000-8000-00805f9b34fb",
  batteryLevel: "00002a19-0000-1000-8000-00805f9b34fb",
} as const;

/** Services to request on connect. The OTA service is deliberately absent. */
export const optionalServices = [UUIDs.deviceInformation, UUIDs.batteryService, UUIDs.controlService, UUIDs.fallbackService];

export interface Characteristics {
  write: string;
  notify: string;
}
export const CONTROL: Characteristics = { write: UUIDs.controlWrite, notify: UUIDs.controlNotify };
export const FALLBACK: Characteristics = { write: UUIDs.fallbackWrite, notify: UUIDs.fallbackNotify };

// ---- Enumerations ---------------------------------------------------------

export const HeatingProfile = {
  steady: 161,
  ascent: 177,
  descent: 193,
  valley: 209,
  hill: 225,
  custom: 241,
} as const;
export type HeatingProfile = (typeof HeatingProfile)[keyof typeof HeatingProfile];

export const heatingProfiles: { code: HeatingProfile; name: string; summary: string }[] = [
  { code: 161, name: "Steady", summary: "Holds the set temperature regardless of load or inhale." },
  { code: 177, name: "Ascent", summary: "Rises through the hold, like torching while you inhale." },
  { code: 193, name: "Descent", summary: "Cools over the hold, like a banger's natural decay." },
  { code: 209, name: "Valley", summary: "Dips to preserve terpenes, then rises to finish." },
  { code: 225, name: "Hill", summary: "Climbs for vapor, then eases down for a smooth finish." },
  { code: 241, name: "Custom", summary: "Your own curve of up to six points." },
];
export const isHeatingProfile = (v: number): v is HeatingProfile => heatingProfiles.some((p) => p.code === v);
export const profileName = (code: number | undefined) => heatingProfiles.find((p) => p.code === code)?.name ?? "";

export const lightModes: { code: number; name: string }[] = [
  [0, "Stealth"], [1, "Calm"], [2, "Purple"], [3, "Blue"], [4, "Cyan"], [5, "Green"], [6, "Yellow"],
  [7, "Orange"], [8, "Red"], [9, "Pink"], [10, "Cali Sunset"], [11, "Purple Haze"], [12, "Northern Lights"],
  [13, "Vegas Nights"], [14, "Blue Dream"], [15, "Strawberry Cough"], [16, "Florida Groves"], [17, "Lime Light"],
  [24, "Blue Cheese"], [25, "Golden Goat"], [26, "Grape Ape"], [27, "Miami Vice"], [28, "Purple Urkle"],
  [29, "Candy Corn"], [30, "Redrum"], [31, "Skull & Bones"], [32, "Witches Brew"], [33, "Jack-O-Lantern"],
].map(([code, name]) => ({ code: code as number, name: name as string }));
export const lightModeName = (code: number) => lightModes.find((m) => m.code === code)?.name ?? `Mode ${code}`;

export const TempUnit = { fahrenheit: 15, celsius: 12 } as const;
export type TempUnit = (typeof TempUnit)[keyof typeof TempUnit];

/** 170 (0xAA) means on for session, haptic, charging, and cleaning flags. */
export const FLAG_ON = 170;

export const Limits = {
  fahrenheit: [250, 650],
  celsius: [121, 343],
  holdSeconds: [10, 90],
  autoShutOffMinutes: [0, 60],
  sessionExtend: [0, 9],
  brightness: [0, 100],
  nameLength: [1, 29],
  userPresets: [1, 5],
  curvePoints: 6,
  writeGapMs: 100,
  presetGapMs: 250,
} as const;
const within = (r: readonly [number, number], v: number) => v >= r[0] && v <= r[1];

// ---- Models ---------------------------------------------------------------

export interface CurvePoint {
  seconds: number;
  fahrenheit: number;
  celsius: number;
}
export const curvePoint = (seconds: number, fahrenheit: number, celsius = Temperature.fToCInt(fahrenheit)): CurvePoint => ({
  seconds,
  fahrenheit,
  celsius,
});
export const emptyPoint = (): CurvePoint => ({ seconds: 0, fahrenheit: 0, celsius: 0 });
export const isEmptyPoint = (p: CurvePoint) => p.fahrenheit === 0 && p.celsius === 0;

/** Opcode 185 rewrites every field, so build this from the last Status. */
export interface Settings {
  activePreset: number;
  lightMode: number;
  autoShutOffMinutes: number;
  unit: TempUnit;
  sessionActive: boolean;
  hapticFeedback: boolean;
  sessionExtend: number;
  brightness: number;
}

/** Opcode 169: the live status packet. */
export interface Status {
  activePreset: number;
  lightMode: number;
  sessionActive: boolean;
  autoShutOffMinutes: number;
  autoShutOffRemainingMinutes: number;
  temperature: number;
  unit: TempUnit;
  sessionSecondsRemaining: number;
  hapticFeedback: boolean;
  sessionExtend: number;
  batteryPercent: number;
  charging: boolean;
  brightness: number;
}
export const statusF = (s: Status) => (s.unit === TempUnit.fahrenheit ? s.temperature : Temperature.cToFInt(s.temperature));
export const statusC = (s: Status) => (s.unit === TempUnit.celsius ? s.temperature : Temperature.fToCInt(s.temperature));

export const settingsFromStatus = (s: Status): Settings => ({
  activePreset: within(Limits.userPresets, s.activePreset) ? s.activePreset : 1,
  lightMode: s.lightMode <= 33 ? s.lightMode : 1,
  autoShutOffMinutes: s.autoShutOffMinutes,
  unit: s.unit,
  sessionActive: s.sessionActive,
  hapticFeedback: s.hapticFeedback,
  sessionExtend: s.sessionExtend,
  brightness: within(Limits.brightness, s.brightness) ? s.brightness : 100,
});

export interface Analytics {
  favoriteTempF?: number;
  favoriteTempC?: number;
  totalHeatingCycles?: number;
  mostCyclesInADay?: number;
  totalChargeCycles?: number;
  favoriteHeatingProfile?: number;
  favoriteLightMode?: number;
  totalTime?: number;
  totalOperationTime?: number;
  totalDeviceResets?: number;
  favoriteHoldTime?: number;
  presetCycles?: number[];
}

export interface HardwareStatus {
  activeChamber: number;
  chamberStatus: number;
  pcbStatus: number;
  batteryStatus: number;
}

// ---- Commands (app → device) ---------------------------------------------

const packet = (opcode: number, payload: number[]) => bytes([opcode, payload.length + 3], payload, [opcode]);

const checkPreset = (p: number, allowZero = false) => {
  const min = allowZero ? 0 : 1;
  if (!Number.isInteger(p) || p < min || p > 5) throw new RigKitError("invalidValue", `preset ${p}`);
};

export const Command = {
  /** Opcode 177. Sent once after subscribing; the device answers with its full state. */
  syncClock(date = new Date()): Uint8Array {
    const y = date.getUTCFullYear();
    return packet(177, [hi(y), lo(y), date.getUTCMonth() + 1, date.getUTCDate(), date.getUTCHours(), date.getUTCMinutes()]);
  },

  /** Opcode 178. The device replies with opcode 162 packets. */
  requestAnalytics: () => packet(178, [255]),

  /** Opcode 179. Preset 0 is accepted as well as 1–5. */
  setPresetTemperature(preset: number, fahrenheit: number): Uint8Array {
    checkPreset(preset, true);
    if (!within(Limits.fahrenheit, fahrenheit)) throw new RigKitError("invalidValue", `temperature ${fahrenheit}°F`);
    const c = Temperature.fToCInt(fahrenheit);
    return packet(179, [preset, hi(fahrenheit), lo(fahrenheit), hi(c), lo(c)]);
  },

  /** Opcode 181. */
  setHeatingProfile(preset: number, profile: HeatingProfile): Uint8Array {
    checkPreset(preset);
    if (!isHeatingProfile(profile)) throw new RigKitError("invalidValue", `profile ${profile}`);
    return packet(181, [preset, profile]);
  },

  /** Opcode 183. */
  setHoldTime(preset: number, seconds: number): Uint8Array {
    checkPreset(preset);
    if (!within(Limits.holdSeconds, seconds)) throw new RigKitError("invalidValue", `hold ${seconds}s`);
    return packet(183, [preset, hi(seconds), lo(seconds)]);
  },

  /** Opcodes 186 and 187. Set the profile to Custom first; 250 ms between packets. */
  setCustomCurve(preset: number, points: CurvePoint[]): [Uint8Array, Uint8Array] {
    checkPreset(preset);
    if (points.length > Limits.curvePoints) throw new RigKitError("invalidValue", "too many curve points");
    const sorted = points.filter((p) => !isEmptyPoint(p)).sort((a, b) => a.seconds - b.seconds);
    const pt = (i: number) => {
      const p = sorted[i];
      if (!p) return [0, 0, 0, 0, 0];
      return [hi(p.fahrenheit), lo(p.fahrenheit), hi(p.celsius), lo(p.celsius), Math.min(255, Math.max(0, p.seconds))];
    };
    return [packet(186, [preset, ...pt(0), ...pt(1), ...pt(2)]), packet(187, [preset, ...pt(3), ...pt(4), ...pt(5)])];
  },

  /** Opcode 198. Heats the insert to 100 °F for 30 s to ease cleaning. */
  cleaningAssist: (on: boolean) => packet(198, [on ? FLAG_ON : 0]),

  /** Opcodes 209 and 210. Send the second 100 ms after the first. */
  setDeviceName(name: string): [Uint8Array, Uint8Array] {
    const ascii = Array.from(name, (ch) => ch.charCodeAt(0));
    if (!within(Limits.nameLength, ascii.length) || !ascii.every((c) => c >= 0x20 && c <= 0x7e)) {
      throw new RigKitError("invalidValue", "name must be 1 to 29 printable ASCII characters");
    }
    const at = (i: number) => ascii[i] ?? 0;
    const first = packet(209, Array.from({ length: 17 }, (_, i) => at(i)));
    const second = packet(210, Array.from({ length: 12 }, (_, i) => at(17 + i)));
    return [first, second];
  },

  /** Opcode 185. Rewrites every setting at once. */
  settings(s: Settings): Uint8Array {
    if (!within(Limits.userPresets, s.activePreset)) throw new RigKitError("invalidValue", `preset ${s.activePreset}`);
    if (s.lightMode < 0 || s.lightMode > 33) throw new RigKitError("invalidValue", `light mode ${s.lightMode}`);
    if (!within(Limits.autoShutOffMinutes, s.autoShutOffMinutes)) throw new RigKitError("invalidValue", `auto shut-off ${s.autoShutOffMinutes}`);
    if (!within(Limits.sessionExtend, s.sessionExtend)) throw new RigKitError("invalidValue", `extend ${s.sessionExtend}`);
    if (!within(Limits.brightness, s.brightness)) throw new RigKitError("invalidValue", `brightness ${s.brightness}`);
    return packet(185, [
      0, s.activePreset, 0, 0, s.lightMode, 0,
      s.autoShutOffMinutes, s.unit,
      s.sessionActive ? FLAG_ON : 0, s.hapticFeedback ? FLAG_ON : 0,
      s.sessionExtend, s.brightness,
      0, 0, 0, 0, 0,
    ]);
  },

  /** Opcode 184. Destructive; never exposed in the UI. */
  factoryReset: () => packet(184, [255]),
};

// ---- Messages (device → app) ---------------------------------------------

export type Message =
  | { type: "clock"; year: number; month: number; day: number; hour: number; minute: number }
  | { type: "analytics"; analytics: Analytics }
  | { type: "presetTemperature"; preset: number; fahrenheit: number; celsius: number }
  | { type: "presetProfile"; preset: number; profile?: HeatingProfile }
  | { type: "presetHoldTime"; preset: number; seconds: number }
  | { type: "activePreset"; preset: number }
  | { type: "status"; status: Status }
  /** startIndex 0 for points 1–3, 3 for 4–6, 6 for opcode 172. */
  | { type: "customCurve"; preset: number; startIndex: number; points: CurvePoint[] }
  | { type: "nameChunk"; final: boolean; data: Uint8Array }
  | { type: "firmwareVersion"; version: string }
  | { type: "secondaryVersion"; version: string }
  | { type: "hardware"; hardware: HardwareStatus }
  | { type: "maintenance"; cleaningActive: boolean; factoryResetStatus: number }
  | { type: "unknown"; opcode: number; data: Uint8Array };

export function parseMessage(d: Uint8Array): Message | undefined {
  if (d.length < 2) return undefined;
  const op = byte(d, 0);
  switch (op) {
    case 161:
      return { type: "clock", year: be16(d, 2), month: byte(d, 4), day: byte(d, 5), hour: byte(d, 6), minute: byte(d, 7) };
    case 162:
      return { type: "analytics", analytics: parseAnalytics(d) };
    case 163:
      return { type: "presetTemperature", preset: byte(d, 2), fahrenheit: be16(d, 3), celsius: be16(d, 5) };
    case 165: {
      const p = byte(d, 3);
      return { type: "presetProfile", preset: byte(d, 2), profile: isHeatingProfile(p) ? p : undefined };
    }
    case 167:
      return { type: "presetHoldTime", preset: byte(d, 2), seconds: be16(d, 3) };
    case 168:
      return { type: "activePreset", preset: byte(d, 2) };
    case 169: {
      if (d.length < 19) return undefined;
      const unit = byte(d, 12) === TempUnit.celsius ? TempUnit.celsius : TempUnit.fahrenheit;
      return {
        type: "status",
        status: {
          activePreset: byte(d, 3),
          lightMode: byte(d, 6),
          sessionActive: byte(d, 7) === FLAG_ON,
          autoShutOffMinutes: byte(d, 8),
          autoShutOffRemainingMinutes: byte(d, 9),
          temperature: be16(d, 10),
          unit,
          sessionSecondsRemaining: byte(d, 13),
          hapticFeedback: byte(d, 14) === FLAG_ON,
          sessionExtend: byte(d, 15),
          batteryPercent: byte(d, 16),
          charging: byte(d, 17) === FLAG_ON,
          brightness: byte(d, 18),
        },
      };
    }
    case 170:
    case 171:
    case 172: {
      const startIndex = op === 170 ? 0 : op === 171 ? 3 : 6;
      const points: CurvePoint[] = [];
      for (let i = 0; i < 3; i++) {
        const b = 3 + i * 5;
        points.push({ seconds: byte(d, b + 4), fahrenheit: be16(d, b), celsius: be16(d, b + 2) });
      }
      return { type: "customCurve", preset: byte(d, 2), startIndex, points };
    }
    case 193:
    case 194:
      return { type: "nameChunk", final: op === 194, data: d.length > 3 ? d.subarray(2, d.length - 1) : new Uint8Array() };
    case 195: {
      const len = byte(d, 2) === 71 ? 9 : 8;
      return { type: "firmwareVersion", version: cleanString(d.subarray(2, 2 + len)) };
    }
    case 196:
      return { type: "secondaryVersion", version: cleanString(d.subarray(2, 10)) };
    case 225:
      return { type: "hardware", hardware: { activeChamber: byte(d, 2), chamberStatus: byte(d, 3), pcbStatus: byte(d, 4), batteryStatus: byte(d, 5) } };
    case 241:
      return { type: "maintenance", cleaningActive: byte(d, 2) === FLAG_ON, factoryResetStatus: byte(d, 3) };
    default:
      return { type: "unknown", opcode: op, data: d };
  }
}

function parseAnalytics(d: Uint8Array): Analytics {
  const a: Analytics = {};
  switch (byte(d, 1)) {
    case 20:
      a.favoriteTempF = be16(d, 2); a.favoriteTempC = be16(d, 4);
      a.totalHeatingCycles = be16(d, 6); a.mostCyclesInADay = be16(d, 8); a.totalChargeCycles = be16(d, 10);
      a.favoriteHeatingProfile = byte(d, 12); a.favoriteLightMode = byte(d, 13);
      a.totalTime = be16(d, 14); a.totalDeviceResets = be16(d, 16);
      break;
    case 17:
    case 19:
      a.favoriteTempF = be16(d, 2); a.favoriteTempC = be16(d, 4);
      a.totalHeatingCycles = be16(d, 6); a.mostCyclesInADay = be16(d, 8); a.totalChargeCycles = be16(d, 10);
      a.favoriteHeatingProfile = byte(d, 12); a.favoriteLightMode = byte(d, 13);
      a.totalDeviceResets = be16(d, 14);
      if (byte(d, 1) === 19) a.favoriteHoldTime = be16(d, 16);
      break;
    case 7:
      a.totalTime = be32(d, 2);
      break;
    case 11:
      a.totalTime = be32(d, 2); a.totalOperationTime = be32(d, 6);
      break;
    case 13:
      a.presetCycles = [0, 1, 2, 3, 4].map((i) => be16(d, 2 + i * 2));
      break;
  }
  return a;
}
