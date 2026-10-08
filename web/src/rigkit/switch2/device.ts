import { type BLETransport, Emitter, RigKitError, sleep } from "../transport";
import { CONTROL, Command, type Characteristics, type CurvePoint, type HeatingProfile, Limits, type Settings, type TempUnit, parseMessage, settingsFromStatus } from "./protocol";
import { type Preset, type Switch2State, applyMessage, curvePoints, initialSwitch2State } from "./state";

/**
 * One connected Switch 2. Owns the transport, keeps `state` current, and
 * paces writes the way the official app does.
 */
export class Switch2Device {
  private _state = initialSwitch2State();
  private updates = new Emitter<Switch2State>();
  private queue: Promise<void> = Promise.resolve();
  private lastWrite = 0;

  constructor(
    private readonly transport: BLETransport,
    readonly characteristics: Characteristics = CONTROL,
  ) {
    transport.onDisconnect(() => this.linkDropped());
  }

  get state() {
    return this._state;
  }
  get isConnected() {
    return this._state.connected;
  }
  onUpdate(listener: (s: Switch2State) => void) {
    return this.updates.on(listener);
  }

  /** Subscribes, syncs the clock, and asks for analytics. The device then streams its full state. */
  async connect() {
    await this.transport.subscribe(this.characteristics.notify, (d) => this.handle(d));
    this.set({ ...this._state, connected: true });
    await this.send(Command.syncClock());
    await sleep(Limits.presetGapMs);
    await this.send(Command.requestAnalytics());
  }

  async disconnect() {
    await this.transport.disconnect();
    this.linkDropped();
  }

  private linkDropped() {
    if (this._state.connected) this.set({ ...this._state, connected: false });
  }

  private set(s: Switch2State) {
    this._state = s;
    this.updates.emit(s);
  }

  private handle(packet: Uint8Array) {
    const m = parseMessage(packet);
    if (m) this.set(applyMessage(this._state, m));
  }

  // ---- Writing --------------------------------------------------------------

  private send(data: Uint8Array): Promise<void> {
    const op = async () => {
      if (!this._state.connected) throw new RigKitError("notConnected");
      const gap = Limits.writeGapMs - (Date.now() - this.lastWrite);
      if (gap > 0) await sleep(gap);
      await this.transport.write(this.characteristics.write, data, false);
      this.lastWrite = Date.now();
    };
    const p = this.queue.then(op);
    this.queue = p.catch(() => {});
    return p;
  }

  private currentSettings(): Settings {
    if (!this._state.status) throw new RigKitError("notConnected", "no status packet yet");
    return settingsFromStatus(this._state.status);
  }

  private async updateSettings(change: (s: Settings) => void) {
    const s = this.currentSettings();
    change(s);
    await this.send(Command.settings(s));
  }

  // ---- Session --------------------------------------------------------------

  startSession() { return this.updateSettings((s) => { s.sessionActive = true; }); }
  stopSession() { return this.updateSettings((s) => { s.sessionActive = false; }); }
  /** Adds `steps` × 10 s to the running hold. 0–9. */
  extendSession(steps: number) { return this.updateSettings((s) => { s.sessionExtend = steps; }); }
  setActivePreset(preset: number) {
    if (preset < 1 || preset > 5) throw new RigKitError("invalidValue", `preset ${preset}`);
    return this.updateSettings((s) => { s.activePreset = preset; });
  }

  // ---- Device settings ------------------------------------------------------

  setLightMode(code: number) { return this.updateSettings((s) => { s.lightMode = code; }); }
  setBrightness(percent: number) { return this.updateSettings((s) => { s.brightness = percent; }); }
  setAutoShutOff(minutes: number) { return this.updateSettings((s) => { s.autoShutOffMinutes = minutes; }); }
  setUnit(unit: TempUnit) { return this.updateSettings((s) => { s.unit = unit; }); }
  setHapticFeedback(on: boolean) { return this.updateSettings((s) => { s.hapticFeedback = on; }); }
  setCleaningAssist(on: boolean) { return this.send(Command.cleaningAssist(on)); }
  requestAnalytics() { return this.send(Command.requestAnalytics()); }

  async setDeviceName(name: string) {
    const [a, b] = Command.setDeviceName(name);
    await this.send(a);
    await this.send(b);
  }

  // ---- Presets --------------------------------------------------------------

  setPresetTemperature(preset: number, fahrenheit: number) { return this.send(Command.setPresetTemperature(preset, fahrenheit)); }
  setHoldTime(preset: number, seconds: number) { return this.send(Command.setHoldTime(preset, seconds)); }
  setHeatingProfile(preset: number, profile: HeatingProfile) { return this.send(Command.setHeatingProfile(preset, profile)); }

  /** Switches the preset to Custom and writes the curve, paced at 250 ms. */
  async setCustomCurve(preset: number, points: CurvePoint[]) {
    const [a, b] = Command.setCustomCurve(preset, points);
    await this.setHeatingProfile(preset, 241);
    await sleep(Limits.presetGapMs);
    await this.send(a);
    await sleep(Limits.presetGapMs);
    await this.send(b);
  }

  /** Writes temperature, hold, and profile with the 1 s spacing the official app uses. */
  async savePreset(p: Preset) {
    if (p.fahrenheit !== undefined) { await this.setPresetTemperature(p.index, p.fahrenheit); await sleep(1000); }
    if (p.holdSeconds !== undefined) { await this.setHoldTime(p.index, p.holdSeconds); await sleep(1000); }
    if (p.profile !== undefined) {
      if (p.profile === 241) await this.setCustomCurve(p.index, curvePoints(p));
      else await this.setHeatingProfile(p.index, p.profile);
    }
  }
}
