import { settings, useSettings } from "../settings";
import { useRig } from "../store";
import { Glass, Row, Screen, SectionLabel, Segmented, Toggle } from "../ui";

export function AppearanceScreen() {
  const s = useSettings();
  const snap = useRig();
  const set = settings.update.bind(settings);

  return (
    <Screen title="Settings" backTo="/">
      <SectionLabel>Display</SectionLabel>
      <Glass className="px-[18px]">
        <Row title="Heat colors the number" detail="White when cold, amber when hot">
          <Toggle on={s.heatColorsNumber} label="Heat colors the number" onChange={(v) => set({ heatColorsNumber: v })} />
        </Row>
        <Row title="Units" last>
          <div className="w-[120px]"><Segmented options={["F", "C"] as const} value={s.units} onChange={(v) => set({ units: v })} render={(v) => `°${v}`} /></div>
        </Row>
      </Glass>

      <SectionLabel>Rig</SectionLabel>
      <Glass className="px-[18px]">
        <Row title="Switch 2" detail={snap.rig ? (snap.rig.state.connected ? "Connected" : "Disconnected") : "Not connected"} last><a href="#/connect" className="glass-strong pressable h-9 px-4 text-[14px] flex items-center no-underline text-ink">Manage</a></Row>
      </Glass>

      <p className="mt-6 px-1 text-[12px] text-ink-3 leading-relaxed">Rigs {__APP_VERSION__} · <a href="https://github.com/ijoshi129/rigs" className="underline">Source on GitHub</a>{snap.mock && " · simulated rig"}</p>
    </Screen>
  );
}
