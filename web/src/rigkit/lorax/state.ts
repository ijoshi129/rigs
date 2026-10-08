import { type Color, isHeatingState } from "./protocol";

export interface Profile {
  /** 0–3 */
  slot: number;
  name: string;
  fahrenheit?: number;
  seconds?: number;
  color?: Color;
  boostFahrenheit?: number;
  boostSeconds?: number;
}

export interface PeakProState {
  name?: string;
  model?: string;
  serial?: string;
  firmware?: string;
  hardwareRevision?: string;
  operatingState: number;
  temperatureFahrenheit?: number;
  commandedFahrenheit?: number;
  elapsedSeconds?: number;
  totalSeconds?: number;
  batteryPercent?: number;
  chargeState?: number;
  chamberType?: number;
  totalDabs?: number;
  tripDabs?: number;
  dabsRemaining?: number;
  activeProfile: number;
  profiles: Profile[];
  stealthMode: boolean;
  lanternOn: boolean;
  lanternColor?: Color;
  authenticated: boolean;
  connected: boolean;
}

export const initialPeakProState = (): PeakProState => ({
  operatingState: 5,
  activeProfile: 0,
  profiles: [0, 1, 2, 3].map((slot) => ({ slot, name: "" })),
  stealthMode: false,
  lanternOn: false,
  authenticated: false,
  connected: false,
});

export const isHeating = (s: PeakProState) => isHeatingState(s.operatingState);
export const secondsRemaining = (s: PeakProState) =>
  s.totalSeconds !== undefined && s.elapsedSeconds !== undefined ? Math.max(0, s.totalSeconds - s.elapsedSeconds) : undefined;
export const activeProfileOf = (s: PeakProState): Profile => s.profiles[Math.min(Math.max(s.activeProfile, 0), 3)]!;
