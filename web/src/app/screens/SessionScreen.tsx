import { Switch2, activePresetOf, initialDumpComplete } from "../../rigkit";
import { Switch2Photo } from "../devices";
import { navigate } from "../router";
import { formatTemp, useSettings } from "../settings";
import { store, useRig } from "../store";
import { heatColor } from "../theme";
import { GearIcon, StopIcon } from "../ui";
import { ConnectScreen } from "./ConnectScreen";

export function SessionScreen() {
  const snap = useRig();
  const s = useSettings();
  const slot = snap.rig;
  if (!slot) return <ConnectScreen />;

  const { state, device } = slot;
  const status = state.status;
  const heating = status?.sessionActive ?? false;
  const tempF = status ? Switch2.statusF(status) : undefined;
  const preset = activePresetOf(state);
  const targetF = preset?.fahrenheit;
  const extend = status?.sessionExtend ?? 0;
  const remaining = status?.sessionSecondsRemaining ?? 0;
  const activeIndex = status?.activePreset ?? state.activePreset ?? 1;
  const ready = state.connected && !!status;
  const run = (name: string, op: () => Promise<void>) => void store.run(name, op);
  const pick = (i: number) => run("Preset", () => device.setActivePreset(i));
  // Presets ordered coolest to hottest; the ladder shows them hottest at the top.
  const byTemp = [1, 2, 3, 4, 5].sort((a, b) => (state.presets[a]?.fahrenheit ?? 0) - (state.presets[b]?.fahrenheit ?? 0) || a - b);
  const pos = byTemp.indexOf(activeIndex);

  const line = !state.connected ? (snap.connecting ? "Reconnecting…" : "Disconnected")
    : !status ? "Waiting for the rig"
    : heating ? (targetF !== undefined && tempF !== undefined && tempF < targetF - 5 ? `Heating to ${formatTemp(targetF, s.units)}°` : "Holding")
    : initialDumpComplete(state) ? "Ready" : "Syncing";
  const detail = heating && remaining > 0 ? `${remaining} s left` : undefined;

  const color = tempF !== undefined && s.heatColorsNumber && tempF > 150 ? heatColor(tempF) : "var(--ink)";

  return (
    <main className="relative mx-auto max-w-[520px] min-h-[100dvh] overflow-hidden flex flex-col px-7"
      style={{ paddingTop: "calc(16px + env(safe-area-inset-top))", paddingBottom: "calc(76px + 16px + env(safe-area-inset-bottom))" }}>
      {/* The rig, half off the right edge, behind everything. */}
      <div aria-hidden="true" className="absolute inset-0 pointer-events-none">
        <div className="absolute w-[380px] h-[420px] left-[40%] top-[14%]" style={{ background: "radial-gradient(closest-side, rgba(0,225,237,0.2), transparent)", filter: "blur(10px)" }} />
        <div className="absolute -right-[150px] top-[10px]" style={{ opacity: state.connected ? 0.5 : 0.25, transition: "opacity 400ms ease" }}><Switch2Photo height={860} /></div>
        <div className="absolute inset-0" style={{ background: "linear-gradient(90deg, var(--bg) 25%, rgba(5,6,8,0.6) 58%, rgba(5,6,8,0.1))" }} />
        <div className="absolute inset-x-0 bottom-0 h-[55%]" style={{ background: "linear-gradient(transparent, var(--bg) 40%)" }} />
      </div>

      <header className="relative flex items-center justify-between h-10">
        <span className="text-[15px] font-medium truncate">{state.name ?? slot.deviceName}</span>
        <span className="flex items-center gap-3 shrink-0">
          {status && <span className="text-[15px] text-ink-2 tnum">{status.batteryPercent}%{status.charging ? " ⚡" : ""}</span>}
          <a href="#/appearance" aria-label="Settings" className="pressable w-9 h-9 -mr-2 flex items-center justify-center text-ink-2"><GearIcon /></a>
        </span>
      </header>

      <section className="relative mt-[5vh]" aria-live="polite">
        <div className="flex items-start">
          <span className="text-[130px] [@media(max-height:740px)]:text-[100px] font-extralight leading-[0.85] tracking-[-0.05em] tnum transition-colors duration-300" style={{ color }}>
            {formatTemp(tempF, s.units)}
          </span>
          <span className="text-[34px] font-light mt-1.5 ml-1">°{s.units}</span>
        </div>
        <div className="mt-4 [@media(max-height:740px)]:mt-3 text-[17px]">{line}{detail && <span className="text-ink-2"> · {detail}</span>}</div>
        {slot.error && <p className="mt-2 text-[14px] text-[#ff7a6b]">{slot.error}</p>}
      </section>

      {/* The presets as a ladder, hottest at the top. */}
      <div className="relative mt-[4vh] flex flex-col items-start" role="group" aria-label="Presets. Hold one to edit it.">
        {[...byTemp].reverse().map((i) => {
          const p = state.presets[i];
          const active = i === activeIndex;
          return (
            <button key={i} type="button" aria-pressed={active} disabled={heating || !ready}
              onClick={() => pick(i)}
              onPointerDown={(e) => holdToEdit(e, i)}
              onContextMenu={(e) => e.preventDefault()}
              className={`flex items-center gap-3 h-11 [@media(max-height:740px)]:h-9 pr-4 tnum disabled:opacity-100 ${active ? "text-ink" : "text-ink-3"}`}>
              <span className="h-[2px] transition-[width] duration-200" style={active ? { width: 34, background: "var(--accent)", boxShadow: "0 0 8px var(--accent)" } : { width: 14, height: 1, background: "#3a3d44" }} />
              <span className={`font-light transition-[font-size] duration-200 ${active ? "text-[26px]" : "text-[20px]"}`}>{p?.fahrenheit !== undefined ? formatTemp(p.fahrenheit, s.units) : "—"}</span>
              {active && p && <span className="text-[14px] text-ink-2 ml-1">{[Switch2.profileName(p.profile), p.holdSeconds !== undefined ? `${p.holdSeconds} s` : undefined].filter(Boolean).join(" · ")}</span>}
            </button>
          );
        })}
      </div>

      <div className="flex-1 min-h-4" />

      <div className="relative">
        <div className="flex items-center justify-between">
          {state.connected ? (
            <button type="button" disabled={!ready} onClick={() => run(heating ? "Stop" : "Start", () => (heating ? device.stopSession() : device.startSession()))}
              className="pressable flex items-center gap-4 text-[18px]">
              <span className="ring-button w-[78px] h-[78px] flex items-center justify-center">{heating ? <StopIcon /> : <PowerIcon />}</span>
              {heating ? "Stop" : `Heat to ${formatTemp(targetF, s.units)}°`}
            </button>
          ) : (
            <button type="button" disabled={snap.connecting} onClick={() => void store.connect()} className="pressable flex items-center gap-4 text-[18px]">
              <span className="ring-button w-[78px] h-[78px] flex items-center justify-center"><PowerIcon /></span>
              {snap.connecting ? "Reconnecting…" : "Reconnect"}
            </button>
          )}

          {/* Mirrors the rig's +/− rocker: steps the preset, or the hold time while heating. */}
          <div className="flex items-center gap-3.5">
            {heating && <span className="text-[14px] text-ink-2 text-right leading-tight">Hold<br />time</span>}
            <div className="w-[52px] h-[96px] rounded-[26px] flex flex-col" style={{ background: "#15171b", border: "1.5px solid #34373e" }}>
              <button type="button" aria-label={heating ? "Add 10 seconds" : "Hotter preset"}
                disabled={!ready || (heating ? extend >= 9 : pos >= byTemp.length - 1)}
                onClick={() => (heating ? run("Extend", () => device.extendSession(extend + 1)) : pick(byTemp[pos + 1]!))}
                className="pressable flex-1 text-[26px] font-light disabled:opacity-30">+</button>
              <button type="button" aria-label={heating ? "Remove 10 seconds" : "Cooler preset"}
                disabled={!ready || (heating ? extend <= 0 : pos <= 0)}
                onClick={() => (heating ? run("Extend", () => device.extendSession(extend - 1)) : pick(byTemp[pos - 1]!))}
                className="pressable flex-1 text-[26px] font-light disabled:opacity-30">−</button>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
}

/** Long-press a preset to open its editor. */
function holdToEdit(e: React.PointerEvent, index: number) {
  const el = e.currentTarget;
  const t = setTimeout(() => { navigate(`/presets/${index}`); if (navigator.vibrate) navigator.vibrate(10); }, 500);
  const cancel = () => { clearTimeout(t); el.removeEventListener("pointerup", cancel); el.removeEventListener("pointerleave", cancel); el.removeEventListener("pointercancel", cancel); };
  el.addEventListener("pointerup", cancel);
  el.addEventListener("pointerleave", cancel);
  el.addEventListener("pointercancel", cancel);
}

const PowerIcon = () => (
  <svg width="26" height="30" viewBox="0 0 24 28" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden="true"><path d="M7 7.5a9 9 0 1 0 10 0" /><path d="M12 3v10" /></svg>
);
