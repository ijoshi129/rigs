import { useEffect, useState } from "react";
import { Switch2, Temperature, curvePoints } from "../../rigkit";
import { navigate } from "../router";
import { formatTemp, useSettings } from "../settings";
import { store, useRig } from "../store";
import { Glass, IconButton, ProfileGlyph, Row, Screen, SectionLabel, Stepper } from "../ui";

export function PresetEditScreen({ index }: { index: number }) {
  const snap = useRig();
  const s = useSettings();
  const slot = snap.rig;
  const preset = slot?.state.presets[index];
  const [f, setF] = useState(preset?.fahrenheit ?? 500);
  const [hold, setHold] = useState(preset?.holdSeconds ?? 30);
  const [profile, setProfile] = useState<Switch2.HeatingProfile>(preset?.profile ?? 193);
  const [saving, setSaving] = useState(false);
  useEffect(() => { if (preset) { setF(preset.fahrenheit ?? 500); setHold(preset.holdSeconds ?? 30); setProfile(preset.profile ?? 193); } }, [preset?.index]);

  if (!slot || !preset) return <Screen title="Preset" backTo="/presets"><p className="text-ink-2">Connect the Switch 2 first.</p></Screen>;

  const save = async () => {
    setSaving(true);
    await store.run("Save preset", () => slot.device.savePreset({ ...preset, fahrenheit: f, holdSeconds: hold, profile, curve: preset.curve }));
    setSaving(false);
    navigate("/presets");
  };

  return (
    <Screen
      title={`Preset ${index}`}
      subtitle={`Switch 2 · button ${index}`}
      backTo="/presets"
      action={<button type="button" onClick={() => void save()} disabled={saving} className="glass-prominent pressable h-10 px-[18px] text-[15px] font-medium">{saving ? "Saving…" : "Save"}</button>}
    >
      <div className="mt-6">
        <div className="flex items-center justify-between">
          <IconButton label="Lower by 5 degrees" onClick={() => setF(Math.max(250, f - 5))}><span className="text-[28px] font-medium leading-none">−</span></IconButton>
          <div className="flex items-baseline gap-1">
            <span className="rounded-face text-[96px] font-light leading-[0.9] tracking-[-0.04em] tnum">{formatTemp(f, s.units)}</span>
            <span className="rounded-face text-[26px] font-light text-ink-2">°{s.units}</span>
          </div>
          <IconButton label="Raise by 5 degrees" onClick={() => setF(Math.min(650, f + 5))}><span className="text-[28px] font-medium leading-none">+</span></IconButton>
        </div>
        <label htmlFor="temp" className="block mt-3.5 text-center text-[13px] font-medium text-ink-2">
          Temperature · {s.units === "F" ? `${Math.round(Temperature.cFromF(f))} °C` : `${Math.round(f)} °F`}
        </label>
        <input id="temp" type="range" min={250} max={650} step={1} value={f} onChange={(e) => setF(Number(e.target.value))} className="mt-1" />
      </div>

      <Glass className="mt-5 px-[18px]">
        <Row title="Hold time" detail="10 to 90 seconds" last>
          <Stepper value={hold} min={10} max={90} step={5} onChange={setHold} format={(v) => `${v} s`} label="Hold time" />
        </Row>
      </Glass>

      <SectionLabel>Heating profile</SectionLabel>
      <div className="grid grid-cols-3 gap-2">
        {Switch2.heatingProfiles.map((p) => {
          const active = p.code === profile;
          return (
            <button key={p.code} type="button" aria-pressed={active} onClick={() => setProfile(p.code)} className={`${active ? "glass-strong font-medium" : "glass font-medium"} pressable h-[66px] flex flex-col items-center justify-center gap-1.5 text-[13px]`}>
              <ProfileGlyph code={p.code} width={34} />{p.name}
            </button>
          );
        })}
      </div>
      <p className="mt-2.5 px-1.5 text-[13px] font-medium text-ink-2 leading-relaxed">{Switch2.heatingProfiles.find((p) => p.code === profile)?.summary}</p>
      {profile === 241 && (
        <p className="mt-2 px-1.5 text-[13px] font-medium text-ink-2">Custom curve: {curvePoints(preset).length} points on the rig. Editing the points comes next.</p>
      )}

      {slot.error && <p className="mt-4 text-[13px] font-medium text-red-400">{slot.error}</p>}
      <p className="mt-6 text-center text-[12px] font-medium text-ink-3">Saving writes to the rig, about three seconds. Its button {index} changes with it.</p>
    </Screen>
  );
}
