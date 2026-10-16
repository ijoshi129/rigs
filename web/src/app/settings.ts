import { useSyncExternalStore } from "react";

export type Units = "F" | "C";

export interface Settings {
  heatColorsNumber: boolean;
  units: Units;
}

const KEY = "rigs.settings";
const defaults: Settings = {
  heatColorsNumber: true,
  units: "F",
};

function load(): Settings {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return defaults;
    const { heatColorsNumber, units } = { ...defaults, ...JSON.parse(raw) } as Settings;
    return { heatColorsNumber, units };
  } catch {
    return defaults;
  }
}

class SettingsStore {
  private value = load();
  private listeners = new Set<() => void>();

  subscribe = (l: () => void) => {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  };
  getSnapshot = () => this.value;

  update(patch: Partial<Settings>) {
    this.value = { ...this.value, ...patch };
    try { localStorage.setItem(KEY, JSON.stringify(this.value)); } catch { /* private mode */ }
    for (const l of this.listeners) l();
  }
}

export const settings = new SettingsStore();
export const useSettings = () => useSyncExternalStore(settings.subscribe, settings.getSnapshot);

export const formatTemp = (f: number | undefined, units: Units, digits = 0) => {
  if (f === undefined) return "—";
  const v = units === "F" ? f : ((f - 32) * 5) / 9;
  return v.toFixed(digits);
};
