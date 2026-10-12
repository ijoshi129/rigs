import { Switch2, activePresetOf, initialDumpComplete } from "../../rigkit";
import { navigate } from "../router";
import { formatTemp, useSettings } from "../settings";
import { type Sample, store, useRig } from "../store";
import { heatColor } from "../theme";
import { GearIcon, GlassButton, IconButton, Screen, Segmented, StopIcon } from "../ui";
import { ConnectScreen } from "./ConnectScreen";

export function SessionScreen() {
  const snap = useRig();
  const s = useSettings();
  const slot = snap.rig;
  if (!slot) return <ConnectScreen />;

  const { state, device, history } = slot;
  const status = state.status;
  const heating = status?.sessionActive ?? false;
  const tempF = status ? Switch2.statusF(status) : undefined;
  const preset = activePresetOf(state);
  const targetF = preset?.fahrenheit;
  const hold = preset?.holdSeconds ?? 30;
  const extend = status?.sessionExtend ?? 0;
  const total = hold + extend * 10;
  const remaining = status?.sessionSecondsRemaining ?? 0;
  const run = (name: string, op: () => Promise<void>) => void store.run(name, op);

  const label = !state.connected ? "Disconnected"
    : !status ? "Waiting for the rig"
    : heating ? (targetF !== undefined && tempF !== undefined && tempF < targetF - 5 ? `Heating to ${formatTemp(targetF, s.units)}` : `Holding at ${formatTemp(targetF, s.units)}`)
    : initialDumpComplete(state) ? "Idle" : "Syncing";

  const color = tempF !== undefined && s.heatColorsNumber && tempF > 150 ? heatColor(tempF) : "var(--ink)";

  return (
    <Screen>
      <header className="flex items-center justify-between">
        <div className="flex items-baseline gap-2.5 min-w-0">
          <h1 className="text-[34px] font-extrabold tracking-[-0.02em] leading-none truncate">{state.name ?? slot.deviceName}</h1>
          {status && <span className="text-[15px] font-semibold text-ink-2 tnum shrink-0">{status.batteryPercent}%{status.charging ? " ⚡" : ""}</span>}
        </div>
        <IconButton label="Appearance and settings" href="#/appearance"><GearIcon /></IconButton>
      </header>

      <div className="mt-12 flex flex-col items-center">
        <div className="flex items-baseline gap-1">
          <span className="rounded-face text-[150px] font-extrabold leading-[0.9] tracking-[-0.04em] tnum transition-colors duration-300" style={{ color, textShadow: "0 8px 40px rgba(0,0,0,0.25)" }}>
            {formatTemp(tempF, s.units)}
          </span>
          <span className="rounded-face text-[30px] font-bold text-ink-2">°{s.units}</span>
        </div>
        <div className="mt-3.5 text-[17px] font-semibold text-ink/85">{label}</div>
        {preset?.profile !== undefined && <div className="text-[14px] font-medium text-ink-2 mt-0.5">{Switch2.profileName(preset.profile)}</div>}
        {heating && (
          <>
            <div className="mt-4 w-[250px] h-2.5 glass overflow-hidden" style={{ borderRadius: 5 }}>
              <div className="h-full rounded-full transition-[width] duration-300" style={{ width: `${Math.round(Math.max(0, Math.min(1, 1 - remaining / Math.max(1, total))) * 100)}%`, background: "var(--fill)" }} />
            </div>
            <div className="mt-2 text-[15px] font-bold tnum text-ink-2">{remaining} s left</div>
          </>
        )}
      </div>

      <Trace samples={history} target={targetF} />

      <div className="mt-6">
        <Segmented
          options={[1, 2, 3, 4, 5]}
          value={status?.activePreset ?? state.activePreset ?? 1}
          disabled={heating || !state.connected || !status}
          onChange={(i) => run("Preset", () => device.setActivePreset(i))}
          onHold={(i) => navigate(`/presets/${i}`)}
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
      {!state.connected && (
        <div className="mt-6 flex flex-col items-center gap-2">
          <GlassButton onClick={() => navigate("/connect")}>{snap.connecting ? "Reconnecting…" : "Reconnect"}</GlassButton>
          {snap.connecting && <span className="text-[13px] font-medium text-ink-2">Trying to reach the rig. Make sure it's on and pairing is enabled.</span>}
        </div>
      )}
    </Screen>
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
