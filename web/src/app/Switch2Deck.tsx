import { Switch2, activePresetOf, initialDumpComplete } from "../rigkit";
import { BatteryBadge, Deck, HeatCurve, HeroTemperature, MenuButton, PresetChip, SessionButton } from "./components";
import { type Switch2Slot, store } from "./store";

export function Switch2Deck({ slot }: { slot: Switch2Slot }) {
  const { state, device, history } = slot;
  const status = state.status;
  const heating = status?.sessionActive ?? false;
  const tempF = status ? Switch2.statusF(status) : undefined;
  const active = activePresetOf(state);
  const targetF = active?.fahrenheit;
  const connected = state.connected;

  const label = !connected
    ? "Disconnected"
    : !status
      ? "Waiting for the rig"
      : heating
        ? targetF !== undefined && tempF !== undefined && tempF < targetF - 5
          ? "Heating"
          : `Holding · ${Switch2.profileName(active?.profile)}`
        : initialDumpComplete(state)
          ? "Idle"
          : "Syncing";

  const run = (name: string, op: () => Promise<void>) => void store.run("switch2", name, op);

  return (
    <Deck>
      <header className="flex items-center gap-3">
        <h2 className="text-[22px] font-bold leading-none">{state.name ?? slot.deviceName}</h2>
        {!connected && <span className="text-[13px] font-medium text-dim">Disconnected</span>}
        <span className="ml-auto" />
        <BatteryBadge percent={status?.batteryPercent} charging={status?.charging} />
        <MenuButton onDisconnect={() => void store.disconnect("switch2")} />
      </header>

      <HeroTemperature fahrenheit={tempF} label={label} />
      <HeatCurve samples={history} target={targetF} maximum={700} />

      <SessionButton
        heating={heating}
        idleTitle={targetF !== undefined ? `Heat to ${targetF}°` : "Heat"}
        secondsRemaining={status?.sessionSecondsRemaining}
        disabled={!status || !connected}
        onClick={() => run(heating ? "Stop" : "Start", () => (heating ? device.stopSession() : device.startSession()))}
      />

      <div className="chips flex gap-2 overflow-x-auto -mx-5 px-5">
        {state.presets.slice(1).map((p) => (
          <PresetChip
            key={p.index}
            title={p.fahrenheit !== undefined ? `${p.fahrenheit}°` : "—"}
            detail={[Switch2.profileName(p.profile) || undefined, p.holdSeconds !== undefined ? `${p.holdSeconds} s` : undefined].filter(Boolean).join(" · ")}
            active={p.index === (status?.activePreset ?? state.activePreset)}
            disabled={heating || !connected}
            onClick={() => run("Preset", () => device.setActivePreset(p.index))}
          />
        ))}
      </div>

      {slot.error && <p className="text-[13px] font-medium text-red-400">{slot.error}</p>}
    </Deck>
  );
}
