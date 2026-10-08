import { Lorax, activeProfileOf, isHeating, secondsRemaining } from "../rigkit";
import { BatteryBadge, Deck, HeatCurve, HeroTemperature, MenuButton, PresetChip, SessionButton } from "./components";
import { type PeakProSlot, store } from "./store";

export function PeakProDeck({ slot }: { slot: PeakProSlot }) {
  const { state, device, history } = slot;
  const heating = isHeating(state);
  const active = activeProfileOf(state);
  const targetF = active.fahrenheit;
  const remaining = secondsRemaining(state);
  const label = !state.connected ? "Disconnected" : !state.authenticated ? "Pairing" : Lorax.operatingStateName(state.operatingState);
  const run = (name: string, op: () => Promise<void>) => void store.run("peakPro", name, op);

  return (
    <Deck>
      <header className="flex items-center gap-3">
        <h2 className="text-[22px] font-bold leading-none">{state.name ?? slot.deviceName}</h2>
        {state.connected && state.chamberType ? (
          <span className="text-[13px] font-medium text-dim">{Lorax.chamberTypeName(state.chamberType)}</span>
        ) : null}
        <span className="ml-auto" />
        <BatteryBadge percent={state.batteryPercent} charging={Lorax.isCharging(state.chargeState)} />
        <MenuButton onDisconnect={() => void store.disconnect("peakPro")} />
      </header>

      <HeroTemperature fahrenheit={state.temperatureFahrenheit} label={label} />
      <HeatCurve samples={history} target={targetF} maximum={650} />

      <div className="flex gap-2.5">
        <SessionButton
          heating={heating}
          idleTitle={targetF !== undefined ? `Heat to ${Math.round(targetF)}°` : "Heat"}
          secondsRemaining={remaining !== undefined ? Math.round(remaining) : undefined}
          disabled={!state.authenticated || !state.connected}
          onClick={() => run(heating ? "Stop" : "Start", () => (heating ? device.stopSession() : device.startSession()))}
        />
        {heating && (
          <button
            type="button"
            aria-label="Boost"
            onClick={() => run("Boost", () => device.boost())}
            className="shrink-0 rounded-full bg-raised text-ember w-14 h-14 flex items-center justify-center"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M13 2 4 14h6l-1 8 9-12h-6z" />
            </svg>
          </button>
        )}
      </div>

      <div className="chips flex gap-2 overflow-x-auto -mx-5 px-5">
        {state.profiles.map((p) => (
          <PresetChip
            key={p.slot}
            title={p.fahrenheit !== undefined ? `${Math.round(p.fahrenheit)}°` : "—"}
            detail={[p.name || undefined, p.seconds !== undefined ? `${Math.round(p.seconds)} s` : undefined].filter(Boolean).join(" · ")}
            active={p.slot === state.activeProfile}
            disabled={heating || !state.connected}
            onClick={() => run("Profile", () => device.setActiveProfile(p.slot))}
          />
        ))}
      </div>

      {slot.error && <p className="text-[13px] font-medium text-red-400">{slot.error}</p>}
    </Deck>
  );
}
