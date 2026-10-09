import { useEffect, useRef, useState } from "react";
import { Lorax, Switch2 } from "../../rigkit";
import { type PeakProSlot, type Switch2Slot, lightModeColors, store, useRigs } from "../store";
import { Glass, Row, Screen, SectionLabel, Segmented, Stepper, Toggle } from "../ui";

export function LightsScreen() {
  const snap = useRigs();
  const slot = snap[snap.activeRig] ?? snap.switch2 ?? snap.peakPro;
  if (!slot) return <Screen title="Lights" subtitle="Connect a rig first"><p className="text-ink-2">Lighting controls appear once a rig is connected.</p></Screen>;
  const both = !!snap.switch2 && !!snap.peakPro;
  return (
    <Screen title="Lights" subtitle={slot.kind === "switch2" ? "Switch 2 · changes apply instantly" : "Peak Pro · lantern and profile glow"}>
      {both && (
        <div className="mb-5"><Segmented options={["switch2", "peakPro"] as const} value={slot.kind} onChange={(k) => store.setActiveRig(k)} render={(k) => (k === "switch2" ? "Switch 2" : "Peak Pro")} /></div>
      )}
      {slot.kind === "switch2" ? <Switch2Lights slot={slot} /> : <PeakProLights slot={slot} />}
    </Screen>
  );
}

/** A slider that only writes to the rig after the finger lifts or 300 ms of quiet. */
function useDebouncedWrite(write: (v: number) => void, delay = 300) {
  const t = useRef<ReturnType<typeof setTimeout>>(undefined);
  return (v: number) => { clearTimeout(t.current); t.current = setTimeout(() => write(v), delay); };
}

function Switch2Lights({ slot }: { slot: Switch2Slot }) {
  const { state, device } = slot;
  const st = state.status;
  const run = (name: string, op: () => Promise<void>) => void store.run("switch2", name, op);
  const [bright, setBright] = useState(st?.brightness ?? 100);
  useEffect(() => { if (st) setBright(st.brightness); }, [st?.brightness]);
  const writeBright = useDebouncedWrite((v) => run("Brightness", () => device.setBrightness(v)));
  const mode = st?.lightMode ?? 1;

  return (
    <>
      <Glass className="px-[18px] py-3.5">
        <div className="flex justify-between text-[15px] font-semibold"><label htmlFor="bright">Brightness</label><span className="text-ink-2 tnum">{bright}%</span></div>
        <input id="bright" type="range" min={0} max={100} value={bright} disabled={!st} onChange={(e) => { const v = Number(e.target.value); setBright(v); writeBright(v); }} />
        <div className="text-[12px] font-medium text-ink-2">All the way down is stealth: only the power button stays lit.</div>
      </Glass>

      <SectionLabel>Light mode · {Switch2.lightModeName(mode)}</SectionLabel>
      <div className="grid grid-cols-6 gap-2.5">
        {Switch2.lightModes.map((m) => {
          const [a, b] = lightModeColors[m.code] ?? ["#888", "#444"];
          const active = m.code === mode;
          return (
            <button
              key={m.code}
              type="button"
              aria-label={m.name + (active ? ", selected" : "")}
              aria-pressed={active}
              disabled={!st}
              onClick={() => run("Light mode", () => device.setLightMode(m.code))}
              className="pressable aspect-square rounded-full"
              style={{ background: m.code <= 9 ? a : `linear-gradient(135deg, ${a}, ${b})`, border: active ? "2px solid var(--ink)" : "1px solid rgba(127,127,127,0.35)", boxShadow: active ? "0 0 0 3px rgba(127,127,127,0.3)" : undefined }}
            />
          );
        })}
      </div>
      <p className="mt-2 px-1.5 text-[12px] font-medium text-ink-3">These are the rig's own LED modes, in the rig's own colors.</p>

      <Glass className="mt-5 px-[18px]">
        <Row title="Haptic feedback">
          <Toggle on={st?.hapticFeedback ?? false} label="Haptic feedback" onChange={(v) => run("Haptics", () => device.setHapticFeedback(v))} />
        </Row>
        <Row title="Auto shut-off" detail={st?.autoShutOffMinutes ? `${st.autoShutOffRemainingMinutes} min left` : "Never"}>
          <Stepper value={st?.autoShutOffMinutes ?? 0} min={0} max={60} step={5} label="Auto shut-off" format={(v) => (v === 0 ? "Off" : `${v} min`)} onChange={(v) => run("Auto shut-off", () => device.setAutoShutOff(v))} />
        </Row>
        <Row title="Cleaning assist" detail="100° for 30 s to loosen the insert">
          <button type="button" disabled={!st} onClick={() => run("Cleaning", () => device.setCleaningAssist(!state.cleaningActive))} className="glass pressable h-9 px-4 rounded-full text-[14px] font-bold">{state.cleaningActive ? "Stop" : "Start"}</button>
        </Row>
        <Row title="Name" detail={`${state.name ?? slot.deviceName}${state.firmwareVersion ? ` · ${state.firmwareVersion}` : ""}`} last>
          <button type="button" onClick={() => { const n = prompt("Name this rig", state.name ?? ""); if (n) run("Rename", () => device.setDeviceName(n)); }} className="glass pressable h-9 px-4 rounded-full text-[14px] font-bold">Rename</button>
        </Row>
      </Glass>
      {slot.error && <p className="mt-4 text-[13px] font-semibold text-red-400">{slot.error}</p>}
    </>
  );
}

const lanternColors: [string, Lorax.Color][] = [
  ["White", { red: 255, green: 240, blue: 220, mode: 1 }], ["Amber", { red: 255, green: 150, blue: 40, mode: 1 }],
  ["Red", { red: 230, green: 40, blue: 50, mode: 1 }], ["Pink", { red: 255, green: 90, blue: 170, mode: 1 }],
  ["Purple", { red: 140, green: 60, blue: 255, mode: 1 }], ["Blue", { red: 50, green: 110, blue: 255, mode: 1 }],
  ["Cyan", { red: 40, green: 200, blue: 230, mode: 1 }], ["Green", { red: 60, green: 210, blue: 110, mode: 1 }],
];

function PeakProLights({ slot }: { slot: PeakProSlot }) {
  const { state, device } = slot;
  const run = (name: string, op: () => Promise<void>) => void store.run("peakPro", name, op);
  const [bright, setBright] = useState(200);
  const writeBright = useDebouncedWrite((v) => run("Brightness", () => device.setLanternBrightness(v)));
  const cur = state.lanternColor;

  return (
    <>
      <Glass className="px-[18px]">
        <Row title="Lantern" detail="Ambient light, stays on for two hours">
          <Toggle on={state.lanternOn} label="Lantern" onChange={(v) => run("Lantern", () => device.setLantern(v))} />
        </Row>
        <Row title="Stealth" detail="All lights off" last>
          <Toggle on={state.stealthMode} label="Stealth" onChange={(v) => run("Stealth", () => device.setStealthMode(v))} />
        </Row>
      </Glass>

      <SectionLabel>Lantern color</SectionLabel>
      <div className="grid grid-cols-8 gap-2.5">
        {lanternColors.map(([name, c]) => {
          const active = cur && cur.red === c.red && cur.green === c.green && cur.blue === c.blue;
          return (
            <button key={name} type="button" aria-label={name} aria-pressed={!!active} onClick={() => run("Lantern color", () => device.setLantern(true, c))} className="pressable aspect-square rounded-full" style={{ background: `rgb(${c.red} ${c.green} ${c.blue})`, border: active ? "2px solid var(--ink)" : "1px solid rgba(127,127,127,0.35)" }} />
          );
        })}
      </div>
      <div className="mt-3 grid grid-cols-3 gap-2">
        {([["Pulsing", Lorax.LanternAnimation.pulsing], ["Rotating", Lorax.LanternAnimation.rotating], ["Disco", Lorax.LanternAnimation.disco]] as const).map(([n, raw]) => (
          <button key={n} type="button" onClick={() => run(n, () => device.setLanternAnimation(raw))} className="glass pressable h-11 rounded-full text-[14px] font-bold">{n}</button>
        ))}
      </div>

      <Glass className="mt-5 px-[18px] py-3.5">
        <div className="flex justify-between text-[15px] font-semibold"><label htmlFor="lbright">Lantern brightness</label><span className="text-ink-2 tnum">{Math.round((bright / 255) * 100)}%</span></div>
        <input id="lbright" type="range" min={0} max={255} value={bright} onChange={(e) => { const v = Number(e.target.value); setBright(v); writeBright(v); }} />
      </Glass>

      <Glass className="mt-5 px-[18px]">
        <Row title="Name" detail={[state.name ?? slot.deviceName, state.model, state.firmware].filter(Boolean).join(" · ")} last>
          <button type="button" onClick={() => { const n = prompt("Name this rig", state.name ?? ""); if (n) run("Rename", () => device.setDeviceName(n)); }} className="glass pressable h-9 px-4 rounded-full text-[14px] font-bold">Rename</button>
        </Row>
      </Glass>
      {slot.error && <p className="mt-4 text-[13px] font-semibold text-red-400">{slot.error}</p>}
    </>
  );
}
