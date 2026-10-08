/**
 * A minimal view of one connected BLE peripheral. The app supplies a Web
 * Bluetooth implementation; tests and the simulators supply in-memory ones.
 * Characteristics are addressed by their lowercase 128-bit UUID string.
 */
export interface BLETransport {
  /** Enables notifications and delivers every value to `onValue`. */
  subscribe(characteristic: string, onValue: (data: Uint8Array) => void): Promise<void>;
  /** Writes a value. `withResponse` false maps to "write without response". */
  write(characteristic: string, data: Uint8Array, withResponse?: boolean): Promise<void>;
  /** Reads a characteristic once. */
  read(characteristic: string): Promise<Uint8Array>;
  /** Tears the link down. */
  disconnect(): Promise<void>;
  /** Registers a handler for the link dropping (from either side). */
  onDisconnect(handler: () => void): void;
}

export type RigKitErrorKind =
  | "notConnected"
  | "invalidValue"
  | "timeout"
  | "authenticationFailed"
  | "commandFailed"
  | "malformedPacket"
  | "unsupported";

export class RigKitError extends Error {
  constructor(
    public readonly kind: RigKitErrorKind,
    message?: string,
    public readonly status?: number,
  ) {
    super(message ?? kind);
    this.name = "RigKitError";
  }
}

export const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** Rejects with a timeout error if `promise` has not settled in `ms`. */
export function withTimeout<T>(ms: number, promise: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout>;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new RigKitError("timeout")), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/** Tiny listener set; returns an unsubscribe function. */
export class Emitter<T> {
  private listeners = new Set<(value: T) => void>();
  on(listener: (value: T) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
  emit(value: T) {
    for (const l of this.listeners) l(value);
  }
}

// ---- Byte helpers ---------------------------------------------------------

export const bytes = (...parts: (number[] | Uint8Array)[]): Uint8Array => {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let i = 0;
  for (const p of parts) {
    out.set(p, i);
    i += p.length;
  }
  return out;
};

export const byte = (d: Uint8Array, i: number) => (i < d.length ? d[i]! : 0);
export const be16 = (d: Uint8Array, i: number) => (i + 1 < d.length ? (d[i]! << 8) | d[i + 1]! : 0);
export const be32 = (d: Uint8Array, i: number) => (i + 3 < d.length ? ((be16(d, i) << 16) | be16(d, i + 2)) >>> 0 : 0);
export const hi = (v: number) => (v >> 8) & 0xff;
export const lo = (v: number) => v & 0xff;

const view = (d: Uint8Array) => new DataView(d.buffer, d.byteOffset, d.byteLength);
export const leU16 = (d: Uint8Array) => (d.length >= 2 ? view(d).getUint16(0, true) : undefined);
export const leU32 = (d: Uint8Array) => (d.length >= 4 ? view(d).getUint32(0, true) : undefined);
export const leI32 = (d: Uint8Array) => (d.length >= 4 ? view(d).getInt32(0, true) : undefined);
export const leF32 = (d: Uint8Array) => (d.length >= 4 ? view(d).getFloat32(0, true) : undefined);

export const encU16 = (v: number) => {
  const b = new Uint8Array(2);
  view(b).setUint16(0, v, true);
  return b;
};
export const encU32 = (v: number) => {
  const b = new Uint8Array(4);
  view(b).setUint32(0, v >>> 0, true);
  return b;
};
export const encI32 = (v: number) => {
  const b = new Uint8Array(4);
  view(b).setInt32(0, v, true);
  return b;
};
export const encF32 = (v: number) => {
  const b = new Uint8Array(4);
  view(b).setFloat32(0, v, true);
  return b;
};

/** UTF-8 text with trailing NULs and whitespace removed. */
export const cleanString = (d: Uint8Array) => {
  let end = d.indexOf(0);
  if (end < 0) end = d.length;
  return new TextDecoder().decode(d.subarray(0, end)).trim();
};

export const utf8 = (s: string) => new TextEncoder().encode(s);
export const hex = (d: Uint8Array) => Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
export const fromHex = (h: string) => new Uint8Array(h.match(/.{2}/g)!.map((x) => parseInt(x, 16)));
export const equal = (a: Uint8Array, b: Uint8Array) => a.length === b.length && a.every((v, i) => v === b[i]);

export const Temperature = {
  /** The exact integer conversion the Dr. Dabber app uses. */
  fToCInt: (f: number) => Math.round(((f - 32) * 5) / 9),
  cToFInt: (c: number) => Math.round((c * 9) / 5 + 32),
  fFromC: (c: number) => (c * 9) / 5 + 32,
  cFromF: (f: number) => ((f - 32) * 5) / 9,
};
