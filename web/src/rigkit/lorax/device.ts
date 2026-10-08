import { type BLETransport, Emitter, RigKitError, cleanString, encF32, leU16, sleep, utf8, Temperature } from "../transport";
import {
  Codec, type Color, LANTERN_SECONDS, ModeCommand, type Opcode, Opcode as Op, Path, type Reply, UUIDs,
  authToken, decodeColor, encodeColor, packCommand, readShortPayload, unpackReply, writeShortPayload,
} from "./protocol";
import { type PeakProState, type Profile, initialPeakProState, isHeating } from "./state";

interface Pending {
  resolve: (r: Reply) => void;
  reject: (e: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

/**
 * One connected Peak Pro over Lorax. Handles the handshake, matches replies
 * to commands by sequence number, and polls the paths a dashboard needs.
 */
export class PeakProDevice {
  private _state = initialPeakProState();
  private updates = new Emitter<PeakProState>();
  private seq = 0;
  private pending = new Map<number, Pending>();
  private pollTimer?: ReturnType<typeof setTimeout>;
  private pollTick = 0;
  protocolVersion?: number;
  maxPayload = 240;

  constructor(private readonly transport: BLETransport) {
    transport.onDisconnect(() => this.linkDropped());
  }

  get state() {
    return this._state;
  }
  onUpdate(listener: (s: PeakProState) => void) {
    return this.updates.on(listener);
  }

  // ---- Connection -----------------------------------------------------------

  /** Subscribe, read version, nudge pairing, get limits, authenticate, load state. */
  async connect() {
    await this.transport.subscribe(UUIDs.reply, (d) => this.handleReply(d));
    try { await this.transport.subscribe(UUIDs.event, () => {}); } catch { /* optional */ }
    this.patch({ connected: true });

    try {
      const v = leU16(await this.transport.read(UUIDs.version));
      if (v !== undefined) {
        this.protocolVersion = v;
        if (v > 255) throw new RigKitError("unsupported", `Lorax protocol version ${v}`);
      }
    } catch (e) {
      if (e instanceof RigKitError && e.kind === "unsupported") throw e;
    }

    // Reading an encrypted characteristic makes the OS pair the link.
    try { await this.transport.read(UUIDs.pupAppVersion); } catch { /* best effort */ }

    try {
      const limits = await this.send(Op.getLimits, undefined, 3000);
      const p = leU16(limits.payload);
      if (limits.status === 0 && p !== undefined && p >= 20 && p <= 512) this.maxPayload = p;
    } catch { /* keep default */ }

    await this.authenticate();
    await this.refreshIdentity();
    await this.refreshSlow();
    await this.refreshFast();
  }

  async disconnect() {
    this.stopPolling();
    await this.transport.disconnect();
    this.linkDropped();
  }

  private linkDropped() {
    this.stopPolling();
    for (const [, p] of this.pending) { clearTimeout(p.timer); p.reject(new RigKitError("notConnected")); }
    this.pending.clear();
    if (this._state.connected) this.patch({ connected: false, authenticated: false });
  }

  private patch(p: Partial<PeakProState>) {
    this._state = { ...this._state, ...p };
    this.updates.emit(this._state);
  }

  private async authenticate() {
    const seedReply = await this.send(Op.getAccessSeed, undefined, 10_000);
    if (seedReply.status !== 0 || seedReply.payload.length < 16) {
      throw new RigKitError("authenticationFailed", "no access seed", seedReply.status);
    }
    const token = await authToken(seedReply.payload);
    const unlock = await this.send(Op.unlockAccess, token, 5000);
    if (unlock.status !== 0) throw new RigKitError("authenticationFailed", "unlock refused", unlock.status);
    this.patch({ authenticated: true });
  }

  // ---- Lorax transport ------------------------------------------------------

  private handleReply(d: Uint8Array) {
    let r: Reply;
    try { r = unpackReply(d); } catch { return; }
    const p = this.pending.get(r.seq);
    if (p) {
      this.pending.delete(r.seq);
      clearTimeout(p.timer);
      p.resolve(r);
    }
  }

  private send(opcode: Opcode, payload?: Uint8Array, timeoutMs = 1500): Promise<Reply> {
    if (!this._state.connected) return Promise.reject(new RigKitError("notConnected"));
    this.seq = (this.seq + 1) & 0xffff;
    if (this.seq === 0) this.seq = 1;
    const seq = this.seq;
    const packet = packCommand(seq, opcode, payload);
    return new Promise<Reply>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(seq);
        reject(new RigKitError("timeout", `opcode ${opcode} seq ${seq}`));
      }, timeoutMs);
      this.pending.set(seq, { resolve, reject, timer });
      this.transport.write(UUIDs.command, packet, false).catch((e) => {
        this.pending.delete(seq);
        clearTimeout(timer);
        reject(e);
      });
    });
  }

  /** Reads a path. Returns undefined on any failure, so polling never throws. */
  async read(path: string): Promise<Uint8Array | undefined> {
    try {
      const r = await this.send(Op.readShort, readShortPayload(path, this.maxPayload));
      return r.status === 0 ? r.payload : undefined;
    } catch {
      return undefined;
    }
  }

  async write(path: string, value: Uint8Array) {
    const r = await this.send(Op.writeShort, writeShortPayload(path, value));
    if (r.status !== 0) throw new RigKitError("commandFailed", `write ${path}`, r.status);
  }

  private async readString(path: string) {
    const d = await this.read(path);
    if (!d) return undefined;
    const s = cleanString(d);
    return s || undefined;
  }

  // ---- Refresh --------------------------------------------------------------

  private async refreshIdentity() {
    const name = await this.readString(Path.deviceName);
    const serial = await this.readString(Path.serialNumber);
    const hardwareRevision = await this.readString(Path.hardwareRevision);
    const m = await this.readString(Path.modelCode);
    const model = m ? (Codec.modelNames[m] ?? `Peak Pro (${m})`) : undefined;
    const fw = await this.read(Path.firmwareRevision);
    const rev = fw && Codec.count(fw);
    this.patch({ name, serial, hardwareRevision, model, firmware: rev !== undefined ? Codec.firmwareLetters(rev) : undefined });
  }

  /** State and temperature. Cheap; call often while heating. */
  async refreshFast() {
    const p: Partial<PeakProState> = {};
    const st = await this.read(Path.operatingState);
    if (st && st.length) p.operatingState = st[0]!;
    const t = await this.read(Path.chamberTemperature);
    const f = t && Codec.fahrenheit(t);
    if (f !== undefined) p.temperatureFahrenheit = f;
    const heating = isHeating({ ...this._state, ...p });
    if (heating) {
      const c = await this.read(Path.commandedTemperature);
      const cf = c && Codec.fahrenheit(c);
      if (cf !== undefined) p.commandedFahrenheit = cf;
      const e = await this.read(Path.elapsed);
      const tot = await this.read(Path.total);
      p.elapsedSeconds = e && Codec.seconds(e, 300);
      p.totalSeconds = tot && Codec.seconds(tot, 300);
    } else {
      p.elapsedSeconds = undefined;
      p.totalSeconds = undefined;
    }
    this.patch(p);
  }

  /** Battery, chamber, odometers, profiles, lighting. Every ~10 s is plenty. */
  async refreshSlow() {
    const p: Partial<PeakProState> = {};
    const b = await this.read(Path.batteryLevel);
    if (b) p.batteryPercent = Codec.battery(b);
    const cs = await this.read(Path.chargeState);
    if (cs) p.chargeState = cs[0];
    const ct = await this.read(Path.chamberType);
    if (ct) p.chamberType = ct[0];
    const td = await this.read(Path.totalDabs);
    if (td) p.totalDabs = Codec.count(td);
    const tr = await this.read(Path.tripDabs);
    if (tr) p.tripDabs = Codec.count(tr);
    const dr = await this.read(Path.dabsRemaining);
    if (dr) p.dabsRemaining = Codec.count(dr);
    const ap = await this.read(Path.activeProfile);
    if (ap) p.activeProfile = ap[0] ?? 0;
    const sm = await this.read(Path.stealthMode);
    if (sm) p.stealthMode = sm[0] !== 0;
    const lc = await this.read(Path.lanternCommand);
    if (lc) p.lanternOn = lc[0] !== 0;
    const col = await this.read(Path.lanternColor);
    if (col) p.lanternColor = decodeColor(col);
    const profiles: Profile[] = [];
    for (let slot = 0; slot < 4; slot++) profiles.push(await this.readProfile(slot));
    p.profiles = profiles;
    this.patch(p);
  }

  private async readProfile(slot: number): Promise<Profile> {
    const prev = this._state.profiles[slot] ?? { slot, name: "" };
    const p: Profile = { ...prev };
    const n = await this.readString(Path.profileName(slot));
    if (n) p.name = n;
    const t = await this.read(Path.profileTemperature(slot));
    if (t) p.fahrenheit = Codec.fahrenheit(t);
    const s = await this.read(Path.profileTime(slot));
    if (s) p.seconds = Codec.seconds(s);
    const c = await this.read(Path.profileColor(slot));
    if (c) p.color = decodeColor(c);
    const bt = await this.read(Path.profileBoostTemperature(slot));
    if (bt) p.boostFahrenheit = Codec.fahrenheit(bt);
    const bs = await this.read(Path.profileBoostTime(slot));
    if (bs) p.boostSeconds = Codec.seconds(bs);
    return p;
  }

  /** Polls fast paths at 250 ms while heating, 1 s idle; slow paths every 10 ticks. */
  startPolling() {
    this.stopPolling();
    const tick = async () => {
      if (!this._state.connected) return;
      try { await this.refreshFast(); } catch { /* keep polling */ }
      if (this.pollTick++ % 10 === 0) { try { await this.refreshSlow(); } catch { /* keep polling */ } }
      this.pollTimer = setTimeout(tick, isHeating(this._state) ? 250 : 1000);
    };
    this.pollTimer = setTimeout(tick, 0);
  }

  stopPolling() {
    if (this.pollTimer) clearTimeout(this.pollTimer);
    this.pollTimer = undefined;
  }

  // ---- Session --------------------------------------------------------------

  private async mode(c: ModeCommand) {
    await this.write(Path.modeCommand, new Uint8Array([c]));
    await this.refreshFast();
  }
  startSession() { return this.mode(ModeCommand.heatCycleStart); }
  stopSession() { return this.mode(ModeCommand.heatCycleAbort); }
  boost() { return this.mode(ModeCommand.heatCycleBoost); }

  private checkSlot(slot: number) {
    if (!Number.isInteger(slot) || slot < 0 || slot > 3) throw new RigKitError("invalidValue", `profile ${slot}`);
  }

  async setActiveProfile(slot: number) {
    this.checkSlot(slot);
    await this.write(Path.activeProfile, new Uint8Array([slot]));
    this.patch({ activeProfile: slot });
  }

  // ---- Profiles -------------------------------------------------------------

  private patchProfile(slot: number, p: Partial<Profile>) {
    this.patch({ profiles: this._state.profiles.map((x) => (x.slot === slot ? { ...x, ...p } : x)) });
  }

  async setProfileTemperature(slot: number, fahrenheit: number) {
    this.checkSlot(slot);
    await this.write(Path.profileTemperature(slot), Codec.encodeCelsius(Temperature.cFromF(fahrenheit)));
    this.patchProfile(slot, { fahrenheit });
  }

  /** 15–180 s. Written as float32, matching the official app. */
  async setProfileDuration(slot: number, seconds: number) {
    this.checkSlot(slot);
    if (seconds < 15 || seconds > 180) throw new RigKitError("invalidValue", `duration ${seconds}s`);
    await this.write(Path.profileTime(slot), encF32(seconds));
    this.patchProfile(slot, { seconds });
  }

  async setProfileName(slot: number, name: string) {
    this.checkSlot(slot);
    await this.write(Path.profileName(slot), utf8(name).subarray(0, 32));
    this.patchProfile(slot, { name });
  }

  async setProfileColor(slot: number, color: Color) {
    this.checkSlot(slot);
    await this.write(Path.profileColor(slot), encodeColor(color));
    this.patchProfile(slot, { color });
  }

  async setBoost(slot: number, opts: { fahrenheit?: number; seconds?: number }) {
    this.checkSlot(slot);
    if (opts.fahrenheit !== undefined) {
      await this.write(Path.profileBoostTemperature(slot), Codec.encodeCelsius(Temperature.cFromF(opts.fahrenheit)));
      this.patchProfile(slot, { boostFahrenheit: opts.fahrenheit });
    }
    if (opts.seconds !== undefined) {
      await this.write(Path.profileBoostTime(slot), encF32(opts.seconds));
      this.patchProfile(slot, { boostSeconds: opts.seconds });
    }
  }

  // ---- Lighting -------------------------------------------------------------

  /** Sets color and mode, then turns the lantern on with the 2-hour timer the official app uses. */
  async setLantern(on: boolean, color?: Color) {
    if (color) {
      await this.write(Path.lanternColor, encodeColor(color));
      this.patch({ lanternColor: color });
    }
    if (on && !this._state.lanternOn) await this.write(Path.lanternTime, encF32(LANTERN_SECONDS));
    await this.write(Path.lanternCommand, new Uint8Array([on ? 1 : 0]));
    this.patch({ lanternOn: on });
  }

  /** One of Puffco's built-in animations (`LanternAnimation.*`). */
  async setLanternAnimation(raw: Uint8Array) {
    await this.write(Path.lanternColor, raw);
    if (!this._state.lanternOn) {
      await this.write(Path.lanternTime, encF32(LANTERN_SECONDS));
      await this.write(Path.lanternCommand, new Uint8Array([1]));
      this.patch({ lanternOn: true });
    }
  }

  /** 0–255, applied to all four LED zones. */
  setLanternBrightness(value: number) {
    const v = Math.min(255, Math.max(0, Math.round(value)));
    return this.write(Path.lanternBrightness, new Uint8Array([v, v, v, v]));
  }

  async setStealthMode(on: boolean) {
    await this.write(Path.stealthMode, new Uint8Array([on ? 1 : 0]));
    this.patch({ stealthMode: on });
  }

  async setDeviceName(name: string) {
    await this.write(Path.deviceName, utf8(name).subarray(0, 32));
    this.patch({ name });
  }

  /** Test hook. */
  async _sleep(ms: number) { await sleep(ms); }
}
