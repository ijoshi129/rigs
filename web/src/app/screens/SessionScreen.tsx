import { Lorax, Switch2, activePresetOf, activeProfileOf, initialDumpComplete, isHeating, secondsRemaining } from "../../rigkit";
import { navigate } from "../router";
import { formatTemp, useSettings } from "../settings";
import { type PeakProSlot, type Sample, type Switch2Slot, rigName, store, useRigs } from "../store";
import { heatColor } from "../theme";
import { PeakProIcon, Switch2Icon } from "../devices";
import { BoltIcon, GearIcon, GlassButton, IconButton, Screen, Segmented, StopIcon } from "../ui";
import { ConnectScreen } from "./ConnectScreen";

export function SessionScreen() {
  const snap = useRigs();
  const slot = snap[snap.activeRig] ?? snap.switch2 ?? snap.peakPro;
  if (!slot) return <ConnectScreen />;
  const other = slot.kind === "switch2" ? snap.peakPro : snap.switch2;
  return slot.kind === "switch2"
    ? <Switch2Session slot={slot} canSwap={!!other} />
    : <PeakProSession slot={slot} canSwap={!!other} />;
}

function Header({ name, battery, charging, canSwap, kind }: { name: string; battery?: number; charging?: boolean; canSwap: boolean; kind: "switch2" | "peakPro" }) {
  return (
    <header className="flex items-center justify-between">
      <div className="flex items-baseline gap-2.5 min-w-0">
        <h1 className="text-[34px] font-extrabold tracking-[-0.02em] leading-none truncate">{name}</h1>
        {battery !== undefined && <span className="text-[15px] font-semibold text-ink-2 tnum shrink-0">{battery}%{charging ? " ⚡" : ""}</span>}
      </div>
      <div className="flex gap-2">
        {canSwap && (
          <IconButton label={`Switch to ${kind === "switch2" ? "Peak Pro" : "Switch 2"}`} onClick={() => store.setActiveRig(kind === "switch2" ? "peakPro" : "switch2")}>
            {kind === "switch2" ? <PeakProIcon size={22} /> : <Switch2Icon size={22} />}
          </IconButton>
        )}
        <IconButton label="Appearance and settings" href="#/appearance"><GearIcon /></IconButton>
      </div>
    </header>
  );
}

function Hero({ f, label, sub, progress, remaining }: { f?: number; label: string; sub?: string; progress?: number; remaining?: string }) {
  const s = useSettings();
  const color = f !== undefined && s.heatColorsNumber && f > 150 ? heatColor(f) : "var(--ink)";
  return (
    <div className="mt-12 flex flex-col items-center">
      <div className="flex items-baseline gap-1">
        <span className="rounded-face text-[150px] font-extrabold leading-[0.9] tracking-[-0.04em] tnum transition-colors duration-300" style={{ color, textShadow: "0 8px 40px rgba(0,0,0,0.25)" }}>
          {formatTemp(f, s.units)}
        </span>
        <span className="rounded-face text-[30px] font-bold text-ink-2">°{s.units}</span>
      </div>
      <div className="mt-3.5 text-[17px] font-semibold text-ink/85">{label}</div>
      {sub && <div className="text-[14px] font-medium text-ink-2 mt-0.5">{sub}</div>}
      {progress !== undefined && (
        <div className="mt-4 w-[250px] h-2.5 rounded-full glass overflow-hidden" style={{ borderRadius: 5 }}>
          <div className="h-full rounded-full transition-[width] duration-300" style={{ width: `${Math.round(progress * 100)}%`, background: "var(--fill)" }} />
        </div>
      )}
      {remaining && <div className="mt-2 text-[15px] font-bold tnum text-ink-2">{remaining}</div>}
    </div>
  );
}

function Trace({ samples, target }: { samples: Sample[]; target?: number }) {
  if (samples.length < 2) return <div className="h-[52px] mt-5" />;
  const W = 300, H = 52;
  const min = 60, max = Math.max(700, target ?? 0);
  const t0 = samples[0]!.t, t1 = Math.max(samples[samples.length - 1]!.t, t0 + 1000);
  const x = (t: number) => ((t - t0) / (t1 - t0)) * W;
  const y = (f: number) => H - 4 - ((Math.min(Math.max(f, min), max) - min) / (max - min)) * (H - 8);
  const d = samples.map((s, i) => `${i ? "L" : "M"}${x(s.t).toFixed(1)} ${y(s.f).toFixed(1)}`).join(" ");
  return (
    <svg viewBox={`0 0 ${W} ${H}`} width={W} height={H} className="mt-5 mx-auto block opacity-80" role="img" aria-label="Temperature this session">
      {target !== undefined && <line x1="0" x2={W} y1={y(target)} y2={y(target)} stroke="var(--ink-3)" strokeDasharray="3 4" />}
      <path d={d} fill="none" stroke="var(--ink)" strokeWidth="2" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

function Switch2Session({ slot, canSwap }: { slot: Switch2Slot; canSwap: boolean }) {
  const { state, device, history } = slot;
  const s = useSettings();
  const status = state.status;
  const heating = status?.sessionActive ?? false;
  const tempF = status ? Switch2.statusF(status) : undefined;
  const preset = activePresetOf(state);
  const targetF = preset?.fahrenheit;
  const hold = preset?.holdSeconds ?? 30;
  const extend = status?.sessionExtend ?? 0;
  const total = hold + extend * 10;
  const remaining = status?.sessionSecondsRemaining ?? 0;
  const run = (name: string, op: () => Promise<void>) => void store.run("switch2", name, op);

  const label = !state.connected ? "Disconnected"
    : !status ? "Waiting for the rig"
    : heating ? (targetF !== undefined && tempF !== undefined && tempF < targetF - 5 ? `Heating to ${formatTemp(targetF, s.units)}` : `Holding at ${formatTemp(targetF, s.units)}`)
    : initialDumpComplete(state) ? "Idle" : "Syncing";

  return (
    <Screen>
      <Header name={state.name ?? slot.deviceName} battery={status?.batteryPercent} charging={status?.charging} canSwap={canSwap} kind="switch2" />
      <Hero
        f={tempF}
        label={label}
        sub={preset?.profile !== undefined ? Switch2.profileName(preset.profile) : undefined}
        progress={heating ? Math.max(0, Math.min(1, 1 - remaining / Math.max(1, total))) : undefined}
        remaining={heating ? `${remaining} s left` : undefined}
      />
      <Trace samples={history} target={targetF} />

      <div className="mt-6">
        <Segmented
          options={[1, 2, 3, 4, 5]}
          value={status?.activePreset ?? state.activePreset ?? 1}
          disabled={heating || !state.connected || !status}
          onChange={(i) => run("Preset", () => device.setActivePreset(i))}
          onHold={(i) => navigate(`/presets/s${i}`)}
          render={(i) => { const p = state.presets[i]; return p?.fahrenheit !== undefined ? formatTemp(p.fahrenheit, s.units) : "—"; }}
        />
        <div className="mt-2.5 text-center text-[13px] font-medium text-ink-2">
          {preset ? `${Switch2.profileName(preset.profile)} · ${preset.holdSeconds ?? "—"} s hold · hold a preset to edit it` : "Hold a preset to edit it"}
        </div>
      </div>

      <div className="mt-8 flex gap-2.5 items-center justify-center">
        <GlassButton
          prominent
          disabled={!status || !state.connected}
          onClick={() => run(heating ? "Stop" : "Start", () => (heating ? device.stopSession() : device.startSession()))}
        >
          {heating ? <><StopIcon />Stop</> : <>Heat to {formatTemp(targetF, s.units)}°</>}
        </GlassButton>
        {heating && (
          <GlassButton label="Add 10 seconds" className="!px-0 w-[60px] text-[14px]" disabled={extend >= 9} onClick={() => run("Extend", () => device.extendSession(extend + 1))}>+10</GlassButton>
        )}
      </div>
      {slot.error && <p className="mt-4 text-center text-[13px] font-semibold text-red-400">{slot.error}</p>}
    </Screen>
  );
}

function PeakProSession({ slot, canSwap }: { slot: PeakProSlot; canSwap: boolean }) {
  const { state, device, history } = slot;
  const s = useSettings();
  const heating = isHeating(state);
  const profile = activeProfileOf(state);
  const targetF = profile.fahrenheit;
  const remaining = secondsRemaining(state);
  const run = (name: string, op: () => Promise<void>) => void store.run("peakPro", name, op);
  const label = !state.connected ? "Disconnected" : !state.authenticated ? "Pairing" : Lorax.operatingStateName(state.operatingState);

  return (
    <Screen>
      <Header name={state.name ?? slot.deviceName} battery={state.batteryPercent} charging={Lorax.isCharging(state.chargeState)} canSwap={canSwap} kind="peakPro" />
      <Hero
        f={state.temperatureFahrenheit}
        label={label}
        sub={[profile.name, state.chamberType ? Lorax.chamberTypeName(state.chamberType) : undefined].filter(Boolean).join(" · ") || undefined}
        progress={heating && state.totalSeconds ? Math.max(0, Math.min(1, (state.elapsedSeconds ?? 0) / state.totalSeconds)) : undefined}
        remaining={heating && remaining !== undefined ? `${Math.round(remaining)} s left` : undefined}
      />
      <Trace samples={history} target={targetF} />

      <div className="mt-6">
        <Segmented
          options={[0, 1, 2, 3]}
          value={state.activeProfile}
          disabled={heating || !state.connected}
          onChange={(i) => run("Profile", () => device.setActiveProfile(i))}
          onHold={(i) => navigate(`/presets/p${i}`)}
          render={(i) => { const p = state.profiles[i]; return p?.fahrenheit !== undefined ? formatTemp(p.fahrenheit, s.units) : "—"; }}
        />
        <div className="mt-2.5 text-center text-[13px] font-medium text-ink-2">
          {profile.name ? `${profile.name} · ${Math.round(profile.seconds ?? 0)} s · hold a profile to edit it` : "Hold a profile to edit it"}
        </div>
      </div>

      <div className="mt-8 flex gap-2.5 items-center justify-center">
        <GlassButton
          prominent
          disabled={!state.authenticated || !state.connected}
          onClick={() => run(heating ? "Stop" : "Start", () => (heating ? device.stopSession() : device.startSession()))}
        >
          {heating ? <><StopIcon />Stop</> : <>Heat to {formatTemp(targetF, s.units)}°</>}
        </GlassButton>
        {heating && (
          <GlassButton label="Boost" className="!px-0 w-[60px]" onClick={() => { store.noteBoost("peakPro"); run("Boost", () => device.boost()); }}><BoltIcon /></GlassButton>
        )}
      </div>
      {slot.error && <p className="mt-4 text-center text-[13px] font-semibold text-red-400">{slot.error}</p>}
      <p className="sr-only">{rigName.peakPro}</p>
    </Screen>
  );
}
