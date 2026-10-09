import { useEffect, useState } from "react";
import { Switch2, Temperature, curvePoints } from "../../rigkit";
import { navigate } from "../router";
import { formatTemp, useSettings } from "../settings";
import { store, useRigs } from "../store";
import { Glass, IconButton, ProfileGlyph, Row, Screen, SectionLabel, Stepper } from "../ui";

export function PresetEditScreen({ id }: { id: string }) {
  const kind = id.startsWith("p") ? "peakPro" : "switch2";
  const index = Number(id.slice(1));
  return kind === "switch2" ? <EditSwitch2 index={index} /> : <EditPeakPro slot={index} />;
}

function TempControl({ f, min, max, onChange }: { f: number; min: number; max: number; onChange: (f: number) => void }) {
  const s = useSettings();
  return (
    <div className="mt-6">
      <div className="flex items-center justify-between">
        <IconButton label="Lower by 5 degrees" onClick={() => onChange(Math.max(min, f - 5))}><span className="text-[28px] font-medium leading-none">−</span></IconButton>
        <div className="flex items-baseline gap-1">
          <span className="rounded-face text-[96px] font-extrabold leading-[0.9] tracking-[-0.04em] tnum">{formatTemp(f, s.units)}</span>
          <span className="rounded-face text-[26px] font-bold text-ink-2">°{s.units}</span>
        </div>
        <IconButton label="Raise by 5 degrees" onClick={() => onChange(Math.min(max, f + 5))}><span className="text-[28px] font-medium leading-none">+</span></IconButton>
      </div>
      <label htmlFor="temp" className="block mt-3.5 text-center text-[13px] font-semibold text-ink-2">
        Temperature · {s.units === "F" ? `${Math.round(Temperature.cFromF(f))} °C` : `${Math.round(f)} °F`}
      </label>
      <input id="temp" type="range" min={min} max={max} step={1} value={f} onChange={(e) => onChange(Number(e.target.value))} className="mt-1" />
    </div>
  );
}

function EditSwitch2({ index }: { index: number }) {
  const snap = useRigs();
  const slot = snap.switch2;
  const preset = slot?.state.presets[index];
  const [f, setF] = useState(preset?.fahrenheit ?? 500);
  const [hold, setHold] = useState(preset?.holdSeconds ?? 30);
  const [profile, setProfile] = useState<Switch2.HeatingProfile>(preset?.profile ?? 193);
  const [saving, setSaving] = useState(false);
  useEffect(() => { if (preset) { setF(preset.fahrenheit ?? 500); setHold(preset.holdSeconds ?? 30); setProfile(preset.profile ?? 193); } }, [preset?.index]);

  if (!slot || !preset) return <Screen title="Preset" backTo="/presets"><p className="text-ink-2">Connect the Switch 2 first.</p></Screen>;

  const save = async () => {
    setSaving(true);
    await store.run("switch2", "Save preset", () => slot.device.savePreset({ ...preset, fahrenheit: f, holdSeconds: hold, profile, curve: preset.curve }));
    setSaving(false);
    navigate("/presets");
  };

  return (
    <Screen
      title={`Preset ${index}`}
      subtitle={`Switch 2 · button ${index}`}
      backTo="/presets"
      action={<button type="button" onClick={() => void save()} disabled={saving} className="glass-prominent pressable h-10 px-[18px] rounded-full text-[15px] font-bold">{saving ? "Saving…" : "Save"}</button>}
    >
      <TempControl f={f} min={250} max={650} onChange={setF} />

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
            <button key={p.code} type="button" aria-pressed={active} onClick={() => setProfile(p.code)} className={`${active ? "glass-strong font-extrabold" : "glass font-semibold"} pressable h-[66px] rounded-[18px] flex flex-col items-center justify-center gap-1.5 text-[13px]`}>
              <ProfileGlyph code={p.code} width={34} />{p.name}
            </button>
          );
        })}
      </div>
      <p className="mt-2.5 px-1.5 text-[13px] font-medium text-ink-2 leading-relaxed">{Switch2.heatingProfiles.find((p) => p.code === profile)?.summary}</p>
      {profile === 241 && (
        <p className="mt-2 px-1.5 text-[13px] font-medium text-ink-2">Custom curve: {curvePoints(preset).length} points on the rig. Editing the points comes next.</p>
      )}

      {slot.error && <p className="mt-4 text-[13px] font-semibold text-red-400">{slot.error}</p>}
      <p className="mt-6 text-center text-[12px] font-medium text-ink-3">Saving writes to the rig, about three seconds. Its button {index} changes with it.</p>
    </Screen>
  );
}

function EditPeakPro({ slot: slotIndex }: { slot: number }) {
  const snap = useRigs();
  const slot = snap.peakPro;
  const profile = slot?.state.profiles[slotIndex];
  const [f, setF] = useState(Math.round(profile?.fahrenheit ?? 500));
  const [secs, setSecs] = useState(Math.round(profile?.seconds ?? 60));
  const [name, setName] = useState(profile?.name ?? "");
  const [saving, setSaving] = useState(false);
  useEffect(() => { if (profile) { setF(Math.round(profile.fahrenheit ?? 500)); setSecs(Math.round(profile.seconds ?? 60)); setName(profile.name); } }, [profile?.slot]);

  if (!slot || !profile) return <Screen title="Profile" backTo="/presets"><p className="text-ink-2">Connect the Peak Pro first.</p></Screen>;

  const save = async () => {
    setSaving(true);
    await store.run("peakPro", "Save profile", async () => {
      if (Math.round(profile.fahrenheit ?? 0) !== f) await slot.device.setProfileTemperature(slotIndex, f);
      if (Math.round(profile.seconds ?? 0) !== secs) await slot.device.setProfileDuration(slotIndex, secs);
      if (profile.name !== name && name.trim()) await slot.device.setProfileName(slotIndex, name.trim());
    });
    setSaving(false);
    navigate("/presets");
  };

  return (
    <Screen
      title={profile.name || `Profile ${slotIndex + 1}`}
      subtitle={`Peak Pro · slot ${slotIndex + 1}`}
      backTo="/presets"
      action={<button type="button" onClick={() => void save()} disabled={saving} className="glass-prominent pressable h-10 px-[18px] rounded-full text-[15px] font-bold">{saving ? "Saving…" : "Save"}</button>}
    >
      <TempControl f={f} min={350} max={620} onChange={setF} />

      <Glass className="mt-5 px-[18px]">
        <Row title="Duration" detail="15 to 180 seconds">
          <Stepper value={secs} min={15} max={180} step={5} onChange={setSecs} format={(v) => `${v} s`} label="Duration" />
        </Row>
        <Row title="Name" last>
          <input value={name} onChange={(e) => setName(e.target.value)} maxLength={16} aria-label="Profile name" className="glass rounded-full h-9 px-4 text-[15px] font-semibold w-[150px] text-right bg-transparent" />
        </Row>
      </Glass>

      {profile.boostFahrenheit !== undefined && (
        <p className="mt-4 px-1.5 text-[13px] font-medium text-ink-2">Boost adds {Math.round(Temperature.cFromF(profile.boostFahrenheit))} °C for {Math.round(profile.boostSeconds ?? 0)} s. Editing boost comes next.</p>
      )}
      {slot.error && <p className="mt-4 text-[13px] font-semibold text-red-400">{slot.error}</p>}
      <p className="mt-6 text-center text-[12px] font-medium text-ink-3">Each change is written to the Peak Pro as you save.</p>
    </Screen>
  );
}
