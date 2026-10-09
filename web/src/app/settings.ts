import { useSyncExternalStore } from "react";

export type Appearance = "auto" | "light" | "dark";
export type Units = "F" | "C";

export interface Wallpaper {
  id: string;
  name: string;
  a: string;
  b: string;
  c: string;
}

export const wallpapers: Wallpaper[] = [
  { id: "ember", name: "Ember", a: "#ff7a1a", b: "#1d4a8a", c: "#3a2a7a" },
  { id: "ocean", name: "Ocean", a: "#2fb7ff", b: "#1d2f8a", c: "#0f4d5a" },
  { id: "aurora", name: "Aurora", a: "#39d98a", b: "#1d4a8a", c: "#3a2a7a" },
  { id: "violet", name: "Violet", a: "#8a5cff", b: "#2a1d6a", c: "#4a1d5a" },
  { id: "rose", name: "Rose", a: "#ff3d6e", b: "#4a1d3a", c: "#3a2a7a" },
  { id: "graphite", name: "Graphite", a: "#6b7280", b: "#2a3140", c: "#1d2430" },
];

export interface Settings {
  appearance: Appearance;
  /** A wallpaper id, "rig" to follow the rig's lights, or "custom". */
  wallpaper: string;
  custom: { a: string; b: string; c: string };
  /** 0..100 */
  frost: number;
  /** 0..100 */
  glow: number;
  heatColorsNumber: boolean;
  units: Units;
}

const KEY = "rigs.settings";
const defaults: Settings = {
  appearance: "auto",
  wallpaper: "ember",
  custom: { a: "#ff7a1a", b: "#1d4a8a", c: "#3a2a7a" },
  frost: 60,
  glow: 50,
  heatColorsNumber: true,
  units: "F",
};

function load(): Settings {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? { ...defaults, ...JSON.parse(raw) } : defaults;
  } catch {
    return defaults;
  }
}

class SettingsStore {
  private value = load();
  private listeners = new Set<() => void>();
  /** Colors pushed in by the rig store when wallpaper = "rig". */
  private rigColors: { a: string; b: string; c: string } | null = null;
  private media = typeof matchMedia === "function" ? matchMedia("(prefers-color-scheme: light)") : null;

  constructor() {
    this.media?.addEventListener("change", () => this.apply());
    this.apply();
  }

  subscribe = (l: () => void) => {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  };
  getSnapshot = () => this.value;

  update(patch: Partial<Settings>) {
    this.value = { ...this.value, ...patch };
    try { localStorage.setItem(KEY, JSON.stringify(this.value)); } catch { /* private mode */ }
    this.apply();
    for (const l of this.listeners) l();
  }

  setRigColors(colors: { a: string; b: string; c: string } | null) {
    this.rigColors = colors;
    if (this.value.wallpaper === "rig") this.apply();
  }

  get resolvedAppearance(): "light" | "dark" {
    if (this.value.appearance !== "auto") return this.value.appearance;
    return this.media?.matches ? "light" : "dark";
  }

  colors(): { a: string; b: string; c: string } {
    const s = this.value;
    if (s.wallpaper === "custom") return s.custom;
    if (s.wallpaper === "rig") return this.rigColors ?? wallpapers[0]!;
    return wallpapers.find((w) => w.id === s.wallpaper) ?? wallpapers[0]!;
  }

  private apply() {
    if (typeof document === "undefined") return;
    const root = document.documentElement;
    const { a, b, c } = this.colors();
    root.style.setProperty("--wp-a", a);
    root.style.setProperty("--wp-b", b);
    root.style.setProperty("--wp-c", c);
    root.style.setProperty("--glow", String(0.15 + (this.value.glow / 100) * 0.6));
    root.style.setProperty("--frost", `${Math.round(6 + (this.value.frost / 100) * 34)}px`);
    root.dataset.appearance = this.resolvedAppearance;
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", this.resolvedAppearance === "light" ? "#e8ecf3" : "#0a0d16");
  }
}

export const settings = new SettingsStore();
export const useSettings = () => useSyncExternalStore(settings.subscribe, settings.getSnapshot);

export const formatTemp = (f: number | undefined, units: Units, digits = 0) => {
  if (f === undefined) return "—";
  const v = units === "F" ? f : ((f - 32) * 5) / 9;
  return v.toFixed(digits);
};
