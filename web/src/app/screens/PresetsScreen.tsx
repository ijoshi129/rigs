import { Switch2 } from "../../rigkit";
import { formatTemp, useSettings } from "../settings";
import { useRigs } from "../store";
import { ChevronRight, Glass, ProfileGlyph, Screen, SectionLabel } from "../ui";

export function PresetsScreen() {
  const snap = useRigs();
  const s = useSettings();
  const sw = snap.switch2;
  const pp = snap.peakPro;

  return (
    <Screen title="Presets" subtitle={sw ? "The five buttons on the Switch 2" : "Connect a rig to edit its presets"}>
      {sw && (
        <Glass className="overflow-hidden">
          {sw.state.presets.slice(1).map((p, i, arr) => {
            const active = p.index === (sw.state.status?.activePreset ?? sw.state.activePreset);
            return (
              <a key={p.index} href={`#/presets/s${p.index}`} className={`flex items-center gap-3.5 px-[18px] py-4 no-underline text-ink ${active ? "glass-strong" : ""} ${i < arr.length - 1 ? "border-b" : ""}`} style={{ borderColor: "rgba(127,127,127,0.18)" }}>
                <span className="rounded-face text-[30px] font-extrabold tnum w-[72px]">{p.fahrenheit !== undefined ? `${formatTemp(p.fahrenheit, s.units)}°` : "—"}</span>
                <span className="flex flex-col gap-0.5 flex-1 min-w-0">
                  <span className="text-[16px] font-semibold flex items-center gap-2">{Switch2.profileName(p.profile) || "Profile"}{active && <span className="text-[11px] font-bold px-2 py-0.5 rounded-full glass-strong">Active</span>}</span>
                  <span className="text-[13px] font-medium text-ink-2">{p.holdSeconds ?? "—"} s hold</span>
                </span>
                <span className="text-ink/70"><ProfileGlyph code={p.profile} /></span>
                <span className="text-ink/45"><ChevronRight /></span>
              </a>
            );
          })}
        </Glass>
      )}

      {pp && (
        <>
          <SectionLabel>Peak Pro</SectionLabel>
          <Glass className="overflow-hidden">
            {pp.state.profiles.map((p, i, arr) => {
              const active = p.slot === pp.state.activeProfile;
              return (
                <a key={p.slot} href={`#/presets/p${p.slot}`} className={`flex items-center gap-3.5 px-[18px] py-4 no-underline text-ink ${active ? "glass-strong" : ""} ${i < arr.length - 1 ? "border-b" : ""}`} style={{ borderColor: "rgba(127,127,127,0.18)" }}>
                  <span className="rounded-face text-[30px] font-extrabold tnum w-[72px]">{p.fahrenheit !== undefined ? `${formatTemp(p.fahrenheit, s.units)}°` : "—"}</span>
                  <span className="flex flex-col gap-0.5 flex-1 min-w-0">
                    <span className="text-[16px] font-semibold flex items-center gap-2">{p.name || `Profile ${p.slot + 1}`}{active && <span className="text-[11px] font-bold px-2 py-0.5 rounded-full glass-strong">Active</span>}</span>
                    <span className="text-[13px] font-medium text-ink-2">{p.seconds !== undefined ? `${Math.round(p.seconds)} s` : "—"}{p.boostFahrenheit !== undefined ? ` · boost +${Math.round(p.boostFahrenheit - 32) > 0 ? Math.round(((p.boostFahrenheit - 32) * 5) / 9) : 0}°C` : ""}</span>
                  </span>
                  {p.color && <span className="w-4 h-4 rounded-full shrink-0" style={{ background: `rgb(${p.color.red} ${p.color.green} ${p.color.blue})` }} aria-hidden="true" />}
                  <span className="text-ink/45"><ChevronRight /></span>
                </a>
              );
            })}
          </Glass>
        </>
      )}

      <p className="mt-5 px-1.5 text-[12px] font-medium text-ink-3 leading-relaxed">Changes are written to the rig as you save them, so the buttons on the device match the app.</p>
    </Screen>
  );
}
