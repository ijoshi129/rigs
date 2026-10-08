import { be16, byte, bytes, cleanString, hi, lo, utf8, Temperature } from "../transport";
import { CONTROL, type Characteristics, FLAG_ON, type Settings, TempUnit, UUIDs, isHeatingProfile } from "../switch2/protocol";
import type { Preset } from "../switch2/state";
import { MockTransport } from "./mockTransport";

/**
 * A fake Switch 2 behind a MockTransport. Answers the clock sync with a full
 * state dump, echoes preset writes, and runs a believable heating cycle.
 */
export class Switch2Simulator {
  readonly transport = new MockTransport();
  speed = 1;

  private presets: Preset[];
  private settings: Settings = {
    activePreset: 2, lightMode: 10, autoShutOffMinutes: 15, unit: TempUnit.fahrenheit,
    sessionActive: false, hapticFeedback: true, sessionExtend: 0, brightness: 60,
  };
  private temperature = 72;
  private sessionRemaining = 0;
  private battery = 87;
  private charging = false;
  private name = "Switch 2";
  private heater?: ReturnType<typeof setTimeout>;

  constructor(readonly characteristics: Characteristics = CONTROL) {
    this.presets = [500, 450, 500, 550, 600, 650].map((f, index) => ({
      index, fahrenheit: f, celsius: Temperature.fToCInt(f), holdSeconds: 30, profile: 193,
      curve: Array.from({ length: 6 }, () => ({ seconds: 0, fahrenheit: 0, celsius: 0 })),
    }));
    this.transport.onWrite = (c, d) => this.receive(c, d);
    this.transport.onRead = (c) => this.readInfo(c);
  }

  stop() {
    if (this.heater) clearTimeout(this.heater);
  }

  // ---- Inbound ----------------------------------------------------------------

  private receive(characteristic: string, d: Uint8Array) {
    if (characteristic !== this.characteristics.write || d.length < 2) return;
    const op = byte(d, 0);
    const p = byte(d, 2);
    switch (op) {
      case 177: this.sendDump(); break;
      case 178: this.sendAnalytics(); break;
      case 179: {
        const pr = this.presets[p];
        if (pr) { pr.fahrenheit = be16(d, 3); pr.celsius = be16(d, 5); }
        this.emit([163, 8, p, byte(d, 3), byte(d, 4), byte(d, 5), byte(d, 6), 163]);
        break;
      }
      case 181: {
        const pr = this.presets[p];
        const prof = byte(d, 3);
        if (pr && isHeatingProfile(prof)) pr.profile = prof;
        this.emit([165, 5, p, prof, 165]);
        break;
      }
      case 183: {
        const pr = this.presets[p];
        if (pr) pr.holdSeconds = be16(d, 3);
        this.emit([167, 6, p, byte(d, 3), byte(d, 4), 167]);
        break;
      }
      case 186:
      case 187: {
        const pr = this.presets[p];
        const start = op === 186 ? 0 : 3;
        if (pr) for (let i = 0; i < 3; i++) {
          const b = 3 + i * 5;
          pr.curve[start + i] = { seconds: byte(d, b + 4), fahrenheit: be16(d, b), celsius: be16(d, b + 2) };
        }
        const echo = op === 186 ? 170 : 171;
        this.emit([echo, ...Array.from(d.subarray(1, d.length - 1)), echo]);
        break;
      }
      case 185: this.applySettings(d); break;
      case 198: this.emit([241, 5, byte(d, 2), 0, 241]); break;
      case 209: this.name = cleanString(d.subarray(2, d.length - 1)); break;
      case 210: this.name += cleanString(d.subarray(2, d.length - 1)); this.sendName(); break;
    }
  }

  private applySettings(d: Uint8Array) {
    const wasActive = this.settings.sessionActive;
    const s = this.settings;
    s.activePreset = byte(d, 3);
    s.lightMode = byte(d, 6);
    s.autoShutOffMinutes = byte(d, 8);
    s.unit = byte(d, 9) === TempUnit.celsius ? TempUnit.celsius : TempUnit.fahrenheit;
    s.sessionActive = byte(d, 10) === FLAG_ON;
    s.hapticFeedback = byte(d, 11) === FLAG_ON;
    s.sessionExtend = byte(d, 12);
    s.brightness = byte(d, 13);
    if (s.sessionActive && s.sessionExtend > 0) this.sessionRemaining += s.sessionExtend * 10;
    if (s.sessionActive && !wasActive) this.startHeating();
    else if (!s.sessionActive && wasActive) this.stopHeating();
    this.sendStatus();
  }

  private readInfo(c: string): Uint8Array {
    switch (c) {
      case UUIDs.modelNumber: return utf8("Switch 2");
      case UUIDs.serialNumber: return utf8("SIM-000001");
      case UUIDs.softwareRevision: return utf8("1.4.2");
      case UUIDs.hardwareRevision: return utf8("B");
      case UUIDs.manufacturer: return utf8("Dr. Dabber");
      case UUIDs.batteryLevel: return new Uint8Array([this.battery]);
      default: throw new Error(`unsupported read ${c}`);
    }
  }

  // ---- Heating ----------------------------------------------------------------

  private startHeating() {
    const preset = this.presets[this.settings.activePreset]!;
    const target = preset.fahrenheit ?? 500;
    this.sessionRemaining = preset.holdSeconds ?? 30;
    this.stop();
    const step = () => {
      let done = false;
      if (this.temperature < target) {
        this.temperature = Math.min(target, this.temperature + Math.round(60 * this.speed));
      } else {
        this.sessionRemaining -= 1;
        this.temperature = Math.max(target - 40, this.temperature - 2);
        done = this.sessionRemaining <= 0;
      }
      this.sendStatus();
      if (done) {
        this.settings.sessionActive = false;
        this.sessionRemaining = 0;
        this.sendStatus();
        this.coolDown();
        return;
      }
      this.heater = setTimeout(step, 250 / this.speed);
    };
    step();
  }

  private stopHeating() {
    this.stop();
    this.sessionRemaining = 0;
    this.coolDown();
  }

  private coolDown() {
    const step = () => {
      this.temperature = Math.max(72, this.temperature - Math.round(15 * this.speed));
      this.sendStatus();
      if (this.temperature > 72) this.heater = setTimeout(step, 500 / this.speed);
    };
    this.heater = setTimeout(step, 500 / this.speed);
  }

  // ---- Outbound ---------------------------------------------------------------

  private emit(b: number[]) {
    this.transport.emit(this.characteristics.notify, new Uint8Array(b));
  }

  private sendStatus() {
    const s = this.settings;
    const temp = s.unit === TempUnit.fahrenheit ? this.temperature : Temperature.fToCInt(this.temperature);
    this.emit([169, 20, 0, s.activePreset, 0, 0, s.lightMode, s.sessionActive ? FLAG_ON : 0,
      s.autoShutOffMinutes, s.autoShutOffMinutes, hi(temp), lo(temp), s.unit,
      Math.min(255, Math.max(0, this.sessionRemaining)), s.hapticFeedback ? FLAG_ON : 0,
      s.sessionExtend, this.battery, this.charging ? FLAG_ON : 0, s.brightness, 169]);
  }

  private sendName() {
    const b = Array.from(utf8(this.name));
    const first = b.slice(0, 17), rest = b.slice(17);
    this.emit([193, first.length + 3, ...first, 193]);
    this.emit([194, rest.length + 3, ...rest, 194]);
  }

  private sendDump() {
    const now = new Date();
    const y = now.getUTCFullYear();
    this.emit([161, 9, hi(y), lo(y), now.getUTCMonth() + 1, now.getUTCDate(), now.getUTCHours(), now.getUTCMinutes(), 161]);
    for (const p of this.presets) {
      const f = p.fahrenheit ?? 0, c = p.celsius ?? 0, h = p.holdSeconds ?? 30;
      this.emit([163, 8, p.index, hi(f), lo(f), hi(c), lo(c), 163]);
      this.emit([165, 5, p.index, p.profile ?? 193, 165]);
      this.emit([167, 6, p.index, hi(h), lo(h), 167]);
    }
    this.emit([168, 4, this.settings.activePreset, 168]);
    this.emit([195, 11, ...Array.from(utf8("G1.4.2   ")), 195]);
    this.emit([196, 11, ...Array.from(utf8("B2.0.1  ")), 196]);
    this.emit([225, 7, 1, 0, 0, 0, 225]);
    this.emit([241, 5, 0, 0, 241]);
    this.sendName();
    this.sendStatus();
  }

  private sendAnalytics() {
    this.emit([162, 20, hi(500), lo(500), hi(260), lo(260), 0x01, 0x2c, 0, 9, 0, 48, 193, 10, 0x10, 0x00, 0, 2, 162]);
    this.emit([162, 11, 0, 0x02, 0x9a, 0x6c, 0, 0x0f, 0x42, 0x40, 162]);
    this.emit([162, 13, 0, 20, 0, 180, 0, 60, 0, 30, 0, 10, 162]);
  }

  /** Unused helper kept for parity with the Swift simulator. */
  protected _bytes = bytes;
}
