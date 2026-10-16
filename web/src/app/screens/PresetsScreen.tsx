import { Switch2 } from "../../rigkit";
import { formatTemp, useSettings } from "../settings";
import { useRig } from "../store";
import { ChevronRight, Glass, ProfileGlyph, Screen } from "../ui";

export function PresetsScreen() {
  const snap = useRig();
  const s = useSettings();
  const rig = snap.rig;

  return (
    <Screen title="Presets" subtitle={rig ? "The five buttons on the Switch 2" : "Connect the rig to edit its presets"}>
      {rig && (
        <Glass className="overflow-hidden">
          {rig.state.presets.slice(1).map((p, i, arr) => {
            const active = p.index === (rig.state.status?.activePreset ?? rig.state.activePreset);
            return (
              <a key={p.index} href={`#/presets/${p.index}`} className={`flex items-center gap-3.5 px-[18px] py-4 no-underline text-ink ${active ? "glass-strong" : ""} ${i < arr.length - 1 ? "border-b" : ""}`} style={{ borderColor: "var(--line)" }}>
                <span className="rounded-face text-[30px] font-light tnum w-[72px]">{p.fahrenheit !== undefined ? `${formatTemp(p.fahrenheit, s.units)}°` : "—"}</span>
                <span className="flex flex-col gap-0.5 flex-1 min-w-0">
                  <span className="text-[16px] font-medium flex items-center gap-2">{Switch2.profileName(p.profile) || "Profile"}{active && <span className="text-[11px] font-medium px-2 py-0.5 glass-strong">Active</span>}</span>
                  <span className="text-[13px] font-medium text-ink-2">{p.holdSeconds ?? "—"} s hold</span>
                </span>
                <span className="text-ink/70"><ProfileGlyph code={p.profile} /></span>
                <span className="text-ink/45"><ChevronRight /></span>
              </a>
            );
          })}
        </Glass>
      )}
      <p className="mt-5 px-1.5 text-[12px] font-medium text-ink-3 leading-relaxed">Changes are written to the rig as you save them, so the buttons on the device match the app.</p>
    </Screen>
  );
}
