import { bytes, byte, encF32, encU16, encU32, equal, leF32, leU16, leU32, utf8 } from "../transport";
import { ModeCommand, Opcode, OperatingState, Path, UUIDs, authToken, encodeColor } from "../lorax/protocol";
import { MockTransport } from "./mockTransport";

/** A fake Peak Pro: a Lorax path store with the real handshake check and a simulated heat cycle. */
export class PeakProSimulator {
  readonly transport = new MockTransport();
  speed = 1;
  requireAuthentication = true;

  private files = new Map<string, Uint8Array>();
  private seed = crypto.getRandomValues(new Uint8Array(16));
  private unlocked = false;
  private heater?: ReturnType<typeof setTimeout>;
  private celsius = 22;
  private elapsed = 0;

  constructor() {
    const f = this.files;
    f.set(Path.deviceName, utf8("Peak Pro"));
    f.set(Path.serialNumber, utf8("SIMPEAK0001"));
    f.set(Path.hardwareRevision, utf8("3"));
    f.set(Path.modelCode, utf8("21"));
    f.set(Path.firmwareRevision, encU32(28)); // "AG"
    f.set(Path.operatingState, new Uint8Array([OperatingState.idle]));
    f.set(Path.chamberTemperature, encF32(this.celsius));
    f.set(Path.commandedTemperature, encF32(0));
    f.set(Path.elapsed, encF32(0));
    f.set(Path.total, encF32(0));
    f.set(Path.activeProfile, new Uint8Array([1]));
    f.set(Path.chamberType, new Uint8Array([4]));
    f.set(Path.batteryLevel, new Uint8Array([64]));
    f.set(Path.chargeState, new Uint8Array([4]));
    f.set(Path.totalDabs, encU32(1342));
    f.set(Path.tripDabs, encU32(17));
    f.set(Path.dabsRemaining, encU32(9));
    f.set(Path.stealthMode, new Uint8Array([0]));
    f.set(Path.lanternCommand, new Uint8Array([0]));
    f.set(Path.lanternColor, encodeColor({ red: 0, green: 180, blue: 255, mode: 1 }));
    const defaults: [string, number, number, [number, number, number]][] = [
      ["Low", 232, 60, [0, 200, 120]], ["Medium", 260, 60, [0, 120, 255]],
      ["High", 288, 60, [255, 120, 0]], ["Peak", 315, 75, [255, 0, 80]],
    ];
    defaults.forEach(([name, temp, secs, [r, g, b]], i) => {
      f.set(Path.profileName(i), utf8(name));
      f.set(Path.profileTemperature(i), encF32(temp));
      f.set(Path.profileTime(i), encF32(secs));
      f.set(Path.profileColor(i), encodeColor({ red: r, green: g, blue: b, mode: 1 }));
      f.set(Path.profileBoostTemperature(i), encF32(5));
      f.set(Path.profileBoostTime(i), encF32(10));
    });
    this.transport.onWrite = (c, d) => this.receive(c, d);
    this.transport.onRead = (c) => this.readChar(c);
  }

  stop() {
    if (this.heater) clearTimeout(this.heater);
  }

  /** Test hook: the value currently stored at a path. */
  value(path: string) {
    return this.files.get(path);
  }

  private readChar(c: string): Uint8Array {
    switch (c) {
      case UUIDs.version: return encU16(1);
      case UUIDs.pupAppVersion: return new Uint8Array([1, 0, 0, 0]);
      default: throw new Error(`unsupported read ${c}`);
    }
  }

  private reply(seq: number, status: number, payload: Uint8Array = new Uint8Array()) {
    this.transport.emit(UUIDs.reply, bytes(encU16(seq), [status], payload));
  }

  private get authorized() {
    return !this.requireAuthentication || this.unlocked;
  }

  private async receive(c: string, d: Uint8Array) {
    const seq = leU16(d);
    if (c !== UUIDs.command || d.length < 3 || seq === undefined) return;
    const op = byte(d, 2);
    const payload = d.subarray(3);
    switch (op) {
      case Opcode.getAccessSeed:
        this.reply(seq, 0, this.seed);
        break;
      case Opcode.unlockAccess: {
        const expected = await authToken(this.seed);
        this.unlocked = equal(payload, expected);
        this.reply(seq, this.unlocked ? 0 : 1);
        break;
      }
      case Opcode.getLimits:
        this.reply(seq, 0, bytes(encU16(240), [32, 32]));
        break;
      case Opcode.readShort: {
        if (!this.authorized) { this.reply(seq, 5); return; }
        const path = new TextDecoder().decode(payload.subarray(4));
        const v = this.files.get(path);
        if (v) this.reply(seq, 0, v); else this.reply(seq, 2);
        break;
      }
      case Opcode.writeShort: {
        if (!this.authorized) { this.reply(seq, 5); return; }
        const body = payload.subarray(3);
        const nul = body.indexOf(0);
        if (nul < 0) { this.reply(seq, 3); return; }
        const path = new TextDecoder().decode(body.subarray(0, nul));
        const value = body.slice(nul + 1);
        this.files.set(path, value);
        this.reply(seq, 0);
        if (path === Path.modeCommand) this.handleMode(byte(value, 0));
        break;
      }
      default:
        this.reply(seq, 4);
    }
  }

  // ---- Heat cycle ---------------------------------------------------------------

  private handleMode(cmd: number) {
    switch (cmd) {
      case ModeCommand.heatCycleStart: this.startCycle(); break;
      case ModeCommand.heatCycleAbort: this.abortCycle(); break;
      case ModeCommand.heatCycleBoost: {
        const slot = byte(this.files.get(Path.activeProfile) ?? new Uint8Array([0]), 0);
        const add = leF32(this.files.get(Path.profileBoostTime(slot)) ?? encF32(10)) ?? 10;
        const total = leF32(this.files.get(Path.total) ?? encF32(0)) ?? 0;
        this.files.set(Path.total, encF32(total + add));
        break;
      }
    }
  }

  private setState(s: number) {
    this.files.set(Path.operatingState, new Uint8Array([s]));
  }

  private startCycle() {
    this.stop();
    const slot = byte(this.files.get(Path.activeProfile) ?? new Uint8Array([0]), 0);
    const target = leF32(this.files.get(Path.profileTemperature(slot)) ?? encF32(260)) ?? 260;
    const duration = leF32(this.files.get(Path.profileTime(slot)) ?? encF32(60)) ?? 60;
    this.elapsed = 0;
    this.files.set(Path.total, encF32(duration));
    this.files.set(Path.elapsed, encF32(0));
    this.files.set(Path.commandedTemperature, encF32(target));
    this.setState(OperatingState.preheat);
    const step = () => {
      let phase: number;
      if (this.celsius < target) {
        this.celsius = Math.min(target, this.celsius + 12 * this.speed);
        this.files.set(Path.chamberTemperature, encF32(this.celsius));
        phase = OperatingState.preheat;
      } else {
        this.elapsed += 0.25 * this.speed;
        this.files.set(Path.elapsed, encF32(this.elapsed));
        const total = leF32(this.files.get(Path.total)!) ?? duration;
        if (this.elapsed >= total) {
          const n = leU32(this.files.get(Path.totalDabs)!) ?? 0;
          this.files.set(Path.totalDabs, encU32(n + 1));
          phase = OperatingState.fade;
        } else {
          phase = OperatingState.active;
        }
      }
      this.setState(phase);
      if (phase === OperatingState.fade) { this.coolDown(); return; }
      this.heater = setTimeout(step, 250 / this.speed);
    };
    step();
  }

  private abortCycle() {
    this.stop();
    this.setState(OperatingState.fade);
    this.coolDown();
  }

  private coolDown() {
    const step = () => {
      this.celsius = Math.max(22, this.celsius - 6 * this.speed);
      this.files.set(Path.chamberTemperature, encF32(this.celsius));
      if (this.celsius > 22) this.heater = setTimeout(step, 500 / this.speed);
      else this.setState(OperatingState.idle);
    };
    this.heater = setTimeout(step, 500 / this.speed);
  }
}
