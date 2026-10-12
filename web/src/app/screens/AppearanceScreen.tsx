import { settings, useSettings, wallpapers } from "../settings";
import { useRig } from "../store";
import { Glass, Row, Screen, SectionLabel, Segmented, Toggle } from "../ui";

export function AppearanceScreen() {
  const s = useSettings();
  const snap = useRig();
  const set = settings.update.bind(settings);

  return (
    <Screen title="Appearance" subtitle="Color is yours to pick. The layout stays the same." backTo="/">
      <SectionLabel>Appearance</SectionLabel>
      <Segmented options={["auto", "light", "dark"] as const} value={s.appearance} onChange={(v) => set({ appearance: v })} render={(v) => v[0]!.toUpperCase() + v.slice(1)} />

      <SectionLabel>Wallpaper</SectionLabel>
      <div className="grid grid-cols-4 gap-2.5">
        {wallpapers.map((w) => <Swatch key={w.id} label={w.name} active={s.wallpaper === w.id} onClick={() => set({ wallpaper: w.id })} style={{ background: `radial-gradient(circle at 30% 30%, ${w.a}, ${w.b} 70%)` }} />)}
        <Swatch label="Follow the rig's lights" active={s.wallpaper === "rig"} onClick={() => set({ wallpaper: "rig" })} style={{ background: "conic-gradient(from 0deg, #ff7a1a, #ff3d6e, #8a5cff, #2fb7ff, #39d98a, #ff7a1a)" }}>
          <span className="w-[60%] h-[60%] rounded-full flex items-center justify-center text-[10px] font-bold" style={{ background: "var(--bg)" }}>RIG</span>
        </Swatch>
        <Swatch label="Custom colors" active={s.wallpaper === "custom"} onClick={() => set({ wallpaper: "custom" })} style={{ background: `radial-gradient(circle at 30% 30%, ${s.custom.a}, ${s.custom.b} 70%)`, borderStyle: s.wallpaper === "custom" ? "solid" : "dashed" }}>
          <span className="text-[22px] font-semibold">+</span>
        </Swatch>
      </div>
      <p className="mt-2 px-1.5 text-[12px] font-medium text-ink-3">"Rig" follows whatever light mode the rig is showing{snap.rig ? "" : ", once it's connected"}.</p>

      {s.wallpaper === "custom" && (
        <Glass className="mt-3 px-[18px]">
          {(["a", "b", "c"] as const).map((k, i) => (
            <Row key={k} title={["Glow", "Second", "Third"][i]!} last={i === 2}>
              <input type="color" value={s.custom[k]} aria-label={`Custom color ${i + 1}`} onChange={(e) => set({ custom: { ...s.custom, [k]: e.target.value } })} className="w-11 h-9 rounded-full border-0 bg-transparent" />
            </Row>
          ))}
        </Glass>
      )}

      <Glass className="mt-5 px-[18px]">
        <div className="py-3 border-b" style={{ borderColor: "rgba(127,127,127,0.18)" }}>
          <div className="flex justify-between text-[15px] font-semibold"><label htmlFor="frost">Frost</label><span className="text-ink-2">{s.frost < 34 ? "Light" : s.frost < 67 ? "Medium" : "Heavy"}</span></div>
          <input id="frost" type="range" min={0} max={100} value={s.frost} onChange={(e) => set({ frost: Number(e.target.value) })} />
        </div>
        <div className="py-3 border-b" style={{ borderColor: "rgba(127,127,127,0.18)" }}>
          <div className="flex justify-between text-[15px] font-semibold"><label htmlFor="glow">Glow</label><span className="text-ink-2">{s.glow < 34 ? "Calm" : s.glow < 67 ? "Soft" : "Vivid"}</span></div>
          <input id="glow" type="range" min={0} max={100} value={s.glow} onChange={(e) => set({ glow: Number(e.target.value) })} />
        </div>
        <Row title="Heat colors the number" detail="White when cold, amber when hot">
          <Toggle on={s.heatColorsNumber} label="Heat colors the number" onChange={(v) => set({ heatColorsNumber: v })} />
        </Row>
        <Row title="Units" last>
          <div className="w-[120px]"><Segmented options={["F", "C"] as const} value={s.units} onChange={(v) => set({ units: v })} render={(v) => `°${v}`} /></div>
        </Row>
      </Glass>

      <SectionLabel>Rig</SectionLabel>
      <Glass className="px-[18px]">
        <Row title="Switch 2" detail={snap.rig ? (snap.rig.state.connected ? "Connected" : "Disconnected") : "Not connected"} last><a href="#/connect" className="glass pressable h-9 px-4 rounded-full text-[14px] font-bold flex items-center no-underline">Manage</a></Row>
      </Glass>

      <p className="mt-6 px-1.5 text-[12px] font-medium text-ink-3 leading-relaxed">Rigs {__APP_VERSION__} · <a href="https://github.com/ijoshi129/rigs" className="underline">Source on GitHub</a>{snap.mock && " · simulated rig"}</p>
    </Screen>
  );
}

function Swatch({ label, active, onClick, style, children }: { label: string; active: boolean; onClick: () => void; style: React.CSSProperties; children?: React.ReactNode }) {
  return (
    <button
      type="button"
      aria-label={label + (active ? ", selected" : "")}
      aria-pressed={active}
      onClick={onClick}
      className="pressable aspect-square rounded-[20px] flex items-center justify-center text-ink"
      style={{ ...style, border: active ? "2px solid var(--ink)" : "1px solid rgba(127,127,127,0.4)", boxShadow: active ? "0 0 0 3px rgba(127,127,127,0.3)" : undefined }}
    >
      {children}
    </button>
  );
}
