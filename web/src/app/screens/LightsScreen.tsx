import { useEffect, useRef, useState } from "react";
import { Switch2 } from "../../rigkit";
import { lightModeColors, store, useRig } from "../store";
import { Glass, Row, Screen, SectionLabel, Stepper, Toggle } from "../ui";

/** A slider that only writes to the rig after 300 ms of quiet. */
function useDebouncedWrite(write: (v: number) => void, delay = 300) {
  const t = useRef<ReturnType<typeof setTimeout>>(undefined);
  return (v: number) => { clearTimeout(t.current); t.current = setTimeout(() => write(v), delay); };
}

export function LightsScreen() {
  const snap = useRig();
  const slot = snap.rig;
  const st = slot?.state.status;
  const run = (name: string, op: () => Promise<void>) => void store.run(name, op);
  const [bright, setBright] = useState(st?.brightness ?? 100);
  useEffect(() => { if (st) setBright(st.brightness); }, [st?.brightness]);
  const writeBright = useDebouncedWrite((v) => { if (slot) run("Brightness", () => slot.device.setBrightness(v)); });

  if (!slot) return <Screen title="Lights" subtitle="Connect the rig first"><p className="text-ink-2">Lighting controls appear once the Switch 2 is connected.</p></Screen>;
  const { state, device } = slot;
  const mode = st?.lightMode ?? 1;

  return (
    <Screen title="Lights" subtitle="Changes apply to the rig instantly">
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
    </Screen>
  );
}
