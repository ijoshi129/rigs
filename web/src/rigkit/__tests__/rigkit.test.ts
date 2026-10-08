import { describe, expect, it } from "vitest";
import { hex, encF32, encI32, encU32, leF32, sleep } from "../transport";
import * as Switch2 from "../switch2/protocol";
import { applyMessage, initialDumpComplete, initialSwitch2State, curvePoints } from "../switch2/state";
import { Switch2Device } from "../switch2/device";
import * as Lorax from "../lorax/protocol";
import { PeakProDevice } from "../lorax/device";
import { MockTransport } from "../mock/mockTransport";
import { Switch2Simulator } from "../mock/switch2Simulator";
import { PeakProSimulator } from "../mock/peakProSimulator";

const arr = (d: Uint8Array) => Array.from(d);

describe("Switch 2 commands", () => {
  it("clock sync layout", () => {
    const d = new Date(Date.UTC(2026, 9, 8, 21, 5));
    expect(arr(Switch2.Command.syncClock(d))).toEqual([177, 9, 7, 234, 10, 8, 21, 5, 177]);
  });

  it("analytics request", () => {
    expect(arr(Switch2.Command.requestAnalytics())).toEqual([178, 4, 255, 178]);
  });

  it("preset temperature sends both units", () => {
    expect(arr(Switch2.Command.setPresetTemperature(1, 500))).toEqual([179, 8, 1, 1, 244, 1, 4, 179]);
    expect(() => Switch2.Command.setPresetTemperature(1, 700)).toThrow();
    expect(() => Switch2.Command.setPresetTemperature(6, 500)).toThrow();
  });

  it("profile, hold, cleaning", () => {
    expect(arr(Switch2.Command.setHeatingProfile(3, 225))).toEqual([181, 5, 3, 225, 181]);
    expect(arr(Switch2.Command.setHoldTime(2, 45))).toEqual([183, 6, 2, 0, 45, 183]);
    expect(arr(Switch2.Command.cleaningAssist(true))).toEqual([198, 4, 170, 198]);
    expect(arr(Switch2.Command.cleaningAssist(false))).toEqual([198, 4, 0, 198]);
  });

  it("settings packet is twenty bytes", () => {
    const d = Switch2.Command.settings({
      activePreset: 3, lightMode: 12, autoShutOffMinutes: 15, unit: 15,
      sessionActive: true, hapticFeedback: true, sessionExtend: 2, brightness: 80,
    });
    expect(arr(d)).toEqual([185, 20, 0, 3, 0, 0, 12, 0, 15, 15, 170, 170, 2, 80, 0, 0, 0, 0, 0, 185]);
  });

  it("name splits at 17", () => {
    const [a, b] = Switch2.Command.setDeviceName("My Favorite Rig Ever");
    expect(a.length).toBe(20);
    expect(b.length).toBe(15);
    expect(new TextDecoder().decode(a.subarray(2, 19))).toBe("My Favorite Rig E");
    expect(new TextDecoder().decode(b.subarray(2, 5))).toBe("ver");
    expect(() => Switch2.Command.setDeviceName("")).toThrow();
    expect(() => Switch2.Command.setDeviceName("ünïcödé")).toThrow();
  });

  it("custom curve sorts and pads", () => {
    const [a, b] = Switch2.Command.setCustomCurve(1, [Switch2.curvePoint(20, 450), Switch2.curvePoint(5, 550)]);
    expect(a.length).toBe(19);
    expect(arr(a).slice(0, 8)).toEqual([186, 19, 1, 2, 38, 1, 32, 5]);
    expect(arr(b)).toEqual([187, 19, 1, ...Array(15).fill(0), 187]);
  });
});

describe("Switch 2 messages", () => {
  it("status parses", () => {
    const m = Switch2.parseMessage(new Uint8Array([169, 20, 0, 3, 0, 0, 12, 170, 15, 14, 1, 244, 15, 27, 170, 1, 87, 0, 60, 169]));
    expect(m?.type).toBe("status");
    if (m?.type !== "status") return;
    const s = m.status;
    expect(s.activePreset).toBe(3);
    expect(s.sessionActive).toBe(true);
    expect(s.temperature).toBe(500);
    expect(Switch2.statusC(s)).toBe(260);
    expect(s.sessionSecondsRemaining).toBe(27);
    expect(s.batteryPercent).toBe(87);
    expect(s.charging).toBe(false);
    expect(s.brightness).toBe(60);
  });

  it("preset packets parse", () => {
    expect(Switch2.parseMessage(new Uint8Array([163, 8, 2, 2, 38, 1, 32, 163]))).toEqual({ type: "presetTemperature", preset: 2, fahrenheit: 550, celsius: 288 });
    expect(Switch2.parseMessage(new Uint8Array([165, 5, 4, 241, 165]))).toEqual({ type: "presetProfile", preset: 4, profile: 241 });
    expect(Switch2.parseMessage(new Uint8Array([167, 6, 1, 0, 90, 167]))).toEqual({ type: "presetHoldTime", preset: 1, seconds: 90 });
    expect(Switch2.parseMessage(new Uint8Array([168, 4, 5, 168]))).toEqual({ type: "activePreset", preset: 5 });
  });

  it("analytics length 20", () => {
    const m = Switch2.parseMessage(new Uint8Array([162, 20, 1, 244, 1, 4, 1, 44, 0, 9, 0, 48, 193, 10, 16, 0, 0, 2, 162]));
    expect(m?.type).toBe("analytics");
    if (m?.type !== "analytics") return;
    expect(m.analytics).toMatchObject({ favoriteTempF: 500, favoriteTempC: 260, totalHeatingCycles: 300, mostCyclesInADay: 9, totalChargeCycles: 48, favoriteHeatingProfile: 193, favoriteLightMode: 10, totalTime: 4096, totalDeviceResets: 2 });
  });

  it("state assembles name and curve", () => {
    let s = initialSwitch2State();
    s = applyMessage(s, { type: "nameChunk", final: false, data: new TextEncoder().encode("My Favorite Rig E") });
    s = applyMessage(s, { type: "nameChunk", final: true, data: new TextEncoder().encode("ver") });
    expect(s.name).toBe("My Favorite Rig Ever");
    s = applyMessage(s, { type: "customCurve", preset: 1, startIndex: 3, points: [Switch2.curvePoint(40, 400)] });
    expect(s.presets[1]!.curve[3]!.fahrenheit).toBe(400);
    expect(curvePoints(s.presets[1]!)).toHaveLength(1);
    expect(initialDumpComplete(s)).toBe(false);
  });
});

describe("Lorax", () => {
  it("framing", () => {
    expect(arr(Lorax.packCommand(0x0102, 16, new Uint8Array([9])))).toEqual([0x02, 0x01, 16, 9]);
    const r = Lorax.unpackReply(new Uint8Array([0x02, 0x01, 0, 0xaa, 0xbb]));
    expect(r.seq).toBe(0x0102);
    expect(r.status).toBe(0);
    expect(arr(r.payload)).toEqual([0xaa, 0xbb]);
    expect(() => Lorax.unpackReply(new Uint8Array([1, 2]))).toThrow();
  });

  it("short payloads", () => {
    expect(arr(Lorax.readShortPayload("/p/bat/soc", 240))).toEqual([0, 0, 240, 0, ...Array.from(new TextEncoder().encode("/p/bat/soc"))]);
    expect(arr(Lorax.writeShortPayload("/p/app/mc", new Uint8Array([7])))).toEqual([0, 0, 0, ...Array.from(new TextEncoder().encode("/p/app/mc")), 0, 7]);
  });

  it("auth token vectors", async () => {
    expect(hex(await Lorax.authToken(new Uint8Array(16)))).toBe("b38af858578966e2c28e5afbdca34add");
    expect(hex(await Lorax.authToken(new Uint8Array(Array.from({ length: 16 }, (_, i) => i))))).toBe("cc4af4246a24eb8bb512bc7dc5157b9c");
    await expect(Lorax.authToken(new Uint8Array([1, 2, 3]))).rejects.toThrow();
  });

  it("codecs", () => {
    expect(Lorax.Codec.fahrenheit(encF32(260))).toBeCloseTo(500);
    expect(Lorax.Codec.fahrenheit(encI32(2600))).toBeCloseTo(500);
    expect(Lorax.Codec.fahrenheit(new Uint8Array([1, 2]))).toBeUndefined();
    expect(Lorax.Codec.battery(new Uint8Array([64]))).toBe(64);
    expect(Lorax.Codec.battery(encU32(64))).toBe(64);
    expect(Lorax.Codec.battery(encF32(64))).toBe(64);
    expect(Lorax.Codec.count(encU32(1342))).toBe(1342);
    expect(Lorax.Codec.count(encF32(1342))).toBe(1342);
    expect(Lorax.Codec.seconds(encU32(45))).toBe(45);
    expect(Lorax.Codec.seconds(encF32(45))).toBe(45);
    expect(Lorax.Codec.seconds(encU32(45_000), 300)).toBe(45);
  });

  it("firmware letters", () => {
    expect(Lorax.Codec.firmwareLetters(1)).toBe("A");
    expect(Lorax.Codec.firmwareLetters(21)).toBe("Z");
    expect(Lorax.Codec.firmwareLetters(22)).toBe("AA");
    expect(Lorax.Codec.firmwareLetters(28)).toBe("AG");
    expect(Lorax.Codec.firmwareLetters(0)).toBe("X*");
  });

  it("color round trip", () => {
    const c: Lorax.Color = { red: 10, green: 20, blue: 30, mode: 5 };
    expect(arr(Lorax.encodeColor(c))).toEqual([10, 20, 30, 0, 5, 0, 0, 0]);
    expect(Lorax.decodeColor(Lorax.encodeColor(c))).toEqual(c);
  });
});

const until = async (cond: () => boolean, ms = 3000) => {
  const end = Date.now() + ms;
  while (!cond()) {
    if (Date.now() > end) throw new Error("timed out waiting");
    await sleep(5);
  }
};

describe("Switch 2 device against simulator", () => {
  it("connects, receives the dump, runs a session", async () => {
    const sim = new Switch2Simulator();
    sim.speed = 50;
    const dev = new Switch2Device(sim.transport);
    await dev.connect();
    await until(() => initialDumpComplete(dev.state) && !!dev.state.status && !!dev.state.name);
    expect(dev.state.name).toBe("Switch 2");
    expect(dev.state.presets[2]!.fahrenheit).toBe(500);
    expect(dev.state.presets[1]!.profile).toBe(193);
    expect(dev.state.status!.activePreset).toBe(2);
    expect(dev.state.firmwareVersion).toBe("G1.4.2");

    await dev.startSession();
    await until(() => dev.state.status!.sessionActive);
    await until(() => dev.state.status!.temperature >= 500);
    expect(dev.state.status!.temperature).toBe(500);

    await dev.stopSession();
    await until(() => !dev.state.status!.sessionActive);

    await dev.setPresetTemperature(4, 620);
    await until(() => dev.state.presets[4]!.fahrenheit === 620);
    expect(dev.state.presets[4]!.celsius).toBe(327);
    sim.stop();
    await dev.disconnect();
    expect(dev.isConnected).toBe(false);
  });

  it("settings need a status first", async () => {
    const dev = new Switch2Device(new MockTransport());
    await expect(dev.startSession()).rejects.toThrow();
  });
});

describe("Peak Pro device against simulator", () => {
  it("handshake then session", async () => {
    const sim = new PeakProSimulator();
    sim.speed = 50;
    const dev = new PeakProDevice(sim.transport);
    await dev.connect();
    const s = dev.state;
    expect(s.authenticated).toBe(true);
    expect(s.name).toBe("Peak Pro");
    expect(s.model).toBe("Peak Pro");
    expect(s.firmware).toBe("AG");
    expect(s.profiles[1]!.name).toBe("Medium");
    expect(s.profiles[1]!.fahrenheit).toBeCloseTo(500);
    expect(s.profiles[1]!.seconds).toBe(60);
    expect(s.activeProfile).toBe(1);
    expect(s.batteryPercent).toBe(64);
    expect(s.chamberType).toBe(4);
    expect(s.totalDabs).toBe(1342);

    await dev.startSession();
    expect(Lorax.isHeatingState(dev.state.operatingState)).toBe(true);
    for (let i = 0; i < 200 && dev.state.operatingState !== 8; i++) {
      await dev.refreshFast();
      await sleep(5);
    }
    expect(dev.state.operatingState).toBe(8);
    expect(dev.state.temperatureFahrenheit!).toBeGreaterThan(490);
    expect(dev.state.totalSeconds).toBe(60);

    await dev.stopSession();
    expect([9, 5]).toContain(dev.state.operatingState);

    await dev.setProfileTemperature(0, 460);
    expect(leF32(sim.value(Lorax.Path.profileTemperature(0))!)).toBeCloseTo(237.78, 1);
    await dev.setLantern(true, { red: 255, green: 0, blue: 0, mode: 1 });
    expect(arr(sim.value(Lorax.Path.lanternCommand)!)).toEqual([1]);
    expect(leF32(sim.value(Lorax.Path.lanternTime)!)).toBe(7200);
    sim.stop();
    await dev.disconnect();
  });

  it("wrong key is refused", async () => {
    const sim = new PeakProSimulator();
    const inner = sim.transport;
    const tampered = new MockTransport();
    tampered.onRead = (c) => inner.read(c);
    tampered.onWrite = async (c, d) => {
      const b = new Uint8Array(d);
      if (b.length > 3 && b[2] === Lorax.Opcode.unlockAccess) b[3]! ^= 0xff;
      await inner.write(c, b);
    };
    await inner.subscribe(Lorax.UUIDs.reply, (d) => tampered.emit(Lorax.UUIDs.reply, d));
    const dev = new PeakProDevice(tampered);
    await expect(dev.connect()).rejects.toMatchObject({ kind: "authenticationFailed", status: 1 });
    expect(dev.state.authenticated).toBe(false);
  });
});
