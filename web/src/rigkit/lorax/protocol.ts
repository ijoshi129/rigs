/**
 * Puffco's Lorax protocol: a virtual file system over two characteristics,
 * unlocked by a SHA-256 challenge-response. Firmware AG and later.
 */
import { RigKitError, byte, bytes, encF32, encU16, fromHex, leF32, leI32, leU16, leU32, utf8, Temperature } from "../transport";

export const UUIDs = {
  service: "e276967f-ea8a-478a-a92e-d78f5dd15dd5",
  command: "60133d5c-5727-4f2c-9697-d842c5292a3c",
  reply: "8dc5ec05-8f7d-45ad-99db-3fbde65dbd9c",
  event: "43312cd1-7d34-46ce-a7d3-0a98fd9b4cb8",
  version: "05434bca-cc7f-4ef6-bbb3-b1c520b9800c",
  /** Advertised on every firmware; usable as the scan filter. */
  legacyService: "06caf9c0-74d3-454f-9be9-e30cd999c17a",
  /** Reading this needs an encrypted link, which makes the OS pair. */
  pupService: "420b9b40-457d-4abe-a3bf-71609d79581b",
  pupAppVersion: "58b0a7aa-d89f-4bf2-961d-0d892d7439d8",
  deviceInformation: "0000180a-0000-1000-8000-00805f9b34fb",
} as const;

export const optionalServices = [UUIDs.deviceInformation, UUIDs.service, UUIDs.legacyService, UUIDs.pupService];

export const Opcode = {
  getAccessSeed: 0,
  unlockAccess: 1,
  getLimits: 2,
  ackEvents: 3,
  readShort: 16,
  writeShort: 17,
  statShort: 18,
  unlink: 19,
  open: 32,
  read: 33,
  write: 34,
  watch: 35,
  unwatch: 36,
  stat: 37,
  close: 38,
} as const;
export type Opcode = (typeof Opcode)[keyof typeof Opcode];

// ---- Framing --------------------------------------------------------------

/** `[seq_lo, seq_hi, opcode, payload...]` */
export const packCommand = (seq: number, opcode: Opcode, payload: Uint8Array = new Uint8Array()) =>
  bytes(encU16(seq), [opcode], payload);

export interface Reply {
  seq: number;
  status: number;
  payload: Uint8Array;
}

/** `[seq_lo, seq_hi, status, payload...]` */
export function unpackReply(d: Uint8Array): Reply {
  const seq = leU16(d);
  if (d.length < 3 || seq === undefined) throw new RigKitError("malformedPacket");
  return { seq, status: byte(d, 2), payload: d.subarray(3) };
}

/** Payload for READ_SHORT: uint16 offset, uint16 max_len, path. */
export const readShortPayload = (path: string, maxLength = 240) => bytes(encU16(0), encU16(maxLength), utf8(path));

/** Payload for WRITE_SHORT: uint16 offset, uint8 flags, path, 0x00, value. */
export const writeShortPayload = (path: string, value: Uint8Array) => bytes(encU16(0), [0], utf8(path), [0], value);

// ---- Authentication -------------------------------------------------------

/** Base64 ZMZFYlbyb1scoSc3pd1x+w== */
export const masterKey = fromHex("64c6456256f26f5b1ca12737a5dd71fb");

/** SHA256(masterKey ‖ seed[0..16])[0..16] */
export async function authToken(seed: Uint8Array): Promise<Uint8Array> {
  if (seed.length < 16) throw new RigKitError("malformedPacket", "seed too short");
  const input = bytes(masterKey, seed.subarray(0, 16));
  const digest = await crypto.subtle.digest("SHA-256", input.buffer as ArrayBuffer);
  return new Uint8Array(digest).subarray(0, 16);
}

// ---- Paths ----------------------------------------------------------------

export const Path = {
  operatingState: "/p/app/stat/id",
  elapsed: "/p/app/stat/elap",
  total: "/p/app/stat/tott",
  modeCommand: "/p/app/mc",
  chamberTemperature: "/p/app/htr/temp",
  commandedTemperature: "/p/app/htr/tcmd",
  activeProfile: "/p/app/hcs",
  temperatureOverride: "/p/app/tmpo",
  timeOverride: "/p/app/timo",
  chamberType: "/p/htr/chmt",
  batteryLevel: "/p/bat/soc",
  chargeState: "/p/bat/chg/stat",
  chargeTimeToFull: "/p/bat/chg/etf",
  totalDabs: "/p/app/odom/0/nc",
  totalHeatTime: "/p/app/odom/0/tm",
  tripDabs: "/p/app/odom/1/nc",
  dabsPerDay: "/p/app/info/dpd",
  dabsRemaining: "/p/app/info/drem",
  uptime: "/p/sys/uptm",
  lanternCommand: "/p/app/ltrn/cmd",
  lanternColor: "/p/app/ltrn/colr",
  lanternTime: "/p/app/ltrn/time",
  lanternBrightness: "/u/app/ui/lbrt",
  ledBrightness: "/u/app/ui/brt",
  stealthMode: "/u/app/ui/stlm",
  deviceName: "/u/sys/name",
  birthday: "/u/sys/bday",
  modelCode: "/p/sys/hw/mdcd",
  serialNumber: "/p/sys/hw/ser",
  hardwareRevision: "/p/sys/hw/ver",
  firmwareRevision: "/p/sys/fw/ver",
  firmwareGitHash: "/p/sys/fw/gith",
  profileName: (slot: number) => `/u/app/hc/${slot}/name`,
  profileTemperature: (slot: number) => `/u/app/hc/${slot}/temp`,
  profileTime: (slot: number) => `/u/app/hc/${slot}/time`,
  profileColor: (slot: number) => `/u/app/hc/${slot}/colr`,
  profileBoostTemperature: (slot: number) => `/u/app/hc/${slot}/btmp`,
  profileBoostTime: (slot: number) => `/u/app/hc/${slot}/btim`,
} as const;

// ---- Enumerations ---------------------------------------------------------

export const OperatingState = {
  initMemory: 0, initVersion: 1, initBattery: 2, masterOff: 3, sleep: 4, idle: 5, temperatureSelect: 6,
  preheat: 7, active: 8, fade: 9, versionDisplay: 10, batteryDisplay: 11, factoryTest: 12, bonding: 13,
} as const;
export type OperatingState = (typeof OperatingState)[keyof typeof OperatingState];
export const isHeatingState = (s: number) => s === 7 || s === 8 || s === 9;
export const operatingStateName = (s: number) => {
  switch (s) {
    case 7: return "Preheating";
    case 8: return "Ready";
    case 9: return "Cooling";
    case 5: case 0: case 13: return "Idle";
    case 4: return "Asleep";
    case 3: return "Off";
    case 6: return "Selecting";
    default: return "Busy";
  }
};

/** Only start, abort, and boost are used; the rest are listed for decoding. */
export const ModeCommand = {
  masterOff: 0, sleep: 1, idle: 2, temperatureSelectBegin: 3, temperatureSelectStop: 4,
  showBattery: 5, showVersion: 6, heatCycleStart: 7, heatCycleAbort: 8, heatCycleBoost: 9,
  factoryTest: 10, bonding: 11,
} as const;
export type ModeCommand = (typeof ModeCommand)[keyof typeof ModeCommand];

export const chamberTypeName = (t: number | undefined) =>
  ({ 0: "No chamber", 1: "Classic", 2: "Herbal", 3: "3D", 4: "3DXL", 5: "Proxy" } as Record<number, string>)[t ?? -1];

export const ChargeState = { bulk: 0, topUp: 1, full: 2, overTemperature: 3, disconnected: 4 } as const;
export const isCharging = (s: number | undefined) => s === 0 || s === 1;

export const LanternMode = { preserve: 0, static: 1, breathing: 5, rising: 6, circling: 7, circlingSlow: 21 } as const;
export type LanternMode = (typeof LanternMode)[keyof typeof LanternMode];

export interface Color {
  red: number;
  green: number;
  blue: number;
  mode: LanternMode;
}
/** `[r, g, b, 0, mode, 0, 0, 0]` */
export const encodeColor = (c: Color) => new Uint8Array([c.red, c.green, c.blue, 0, c.mode, 0, 0, 0]);
export const decodeColor = (d: Uint8Array): Color | undefined =>
  d.length >= 3 ? { red: byte(d, 0), green: byte(d, 1), blue: byte(d, 2), mode: (byte(d, 4) || 1) as LanternMode } : undefined;
/** Puffco's built-in animations ignore the RGB bytes. */
export const LanternAnimation = {
  disco: new Uint8Array([255, 255, 0, 0, 1, 0, 0, 0]),
  pulsing: new Uint8Array([255, 255, 0, 0, 5, 0, 0, 0]),
  rotating: new Uint8Array([255, 255, 0, 0, 21, 0, 0, 0]),
} as const;
export const LANTERN_SECONDS = 7200;

// ---- Codecs ---------------------------------------------------------------

export const Codec = {
  /** °F from a path value. Peak Pro sends float32 °C; Proxy sends int32 tenths of °C. */
  fahrenheit(d: Uint8Array): number | undefined {
    if (d.length < 4) return undefined;
    const f = leF32(d);
    if (f !== undefined && Number.isFinite(f) && f >= 5 && f <= 450) return Temperature.fFromC(f);
    const i = leI32(d);
    if (i !== undefined) {
      if (i >= 50 && i <= 4500) return Temperature.fFromC(i / 10);
      if (i >= 5 && i <= 450) return Temperature.fFromC(i);
    }
    return undefined;
  },
  encodeCelsius: (c: number) => encF32(c),

  /** Percent 0–100 from 1-byte, uint32, or float32. */
  battery(d: Uint8Array): number | undefined {
    if (d.length === 1) return Math.min(100, byte(d, 0));
    const u = leU32(d);
    if (u === undefined) return undefined;
    if (u <= 100) return u;
    if (u <= 10_000) return Math.min(100, Math.round(u / 100));
    const f = leF32(d);
    if (f !== undefined && Number.isFinite(f) && f >= 0 && f <= 100) return Math.round(f);
    return undefined;
  },

  /** A count stored as uint32 or as an integral float32. */
  count(d: Uint8Array): number | undefined {
    if (d.length === 1) return byte(d, 0);
    if (d.length === 2) return leU16(d);
    const u = leU32(d);
    if (u === undefined) return undefined;
    const f = leF32(d);
    if (f !== undefined && Number.isFinite(f) && f >= 1 && f < 1_000_000 && Number.isInteger(f)) return f;
    return u;
  },

  /** Seconds stored as uint32 or float32; values above `millisecondsAbove` are taken as ms. */
  seconds(d: Uint8Array, millisecondsAbove?: number): number | undefined {
    const u = leU32(d);
    if (u === undefined) return undefined;
    let v: number;
    if (u <= 100_000) v = u;
    else {
      const f = leF32(d);
      if (f === undefined || !Number.isFinite(f) || f < 0) return undefined;
      v = f;
    }
    if (millisecondsAbove !== undefined && v > millisecondsAbove) v /= 1000;
    return v;
  },

  /** Firmware integer → letter code, 21-letter alphabet, 1-indexed. */
  firmwareLetters(rev: number): string {
    const chars = "ABCDEFGHJKMNPRTUVWXYZ";
    if (rev <= 0) return "X*";
    let i = rev - 1;
    let out = "";
    while (i >= 0) {
      out = chars[i % chars.length] + out;
      i = Math.floor(i / chars.length) - 1;
    }
    return out;
  },

  modelNames: {
    "0": "Peak Pro", "21": "Peak Pro", "51": "Peak Pro", "4294967295": "Peak Pro",
    "1": "Opal Peak Pro", "22": "Opal Peak Pro", "2": "Indiglow Peak Pro",
    "4": "Guardian Peak Pro", "25": "Guardian Peak Pro", "26": "Guardian Peak Pro",
    "12": "Peach White Peak Pro", "72": "Peach White Peak Pro",
    "13": "Peach Black Peak Pro", "71": "Peach Black Peak Pro",
    "15": "Peach Desert Peak Pro", "74": "Peach Desert Peak Pro",
  } as Record<string, string>,
};
