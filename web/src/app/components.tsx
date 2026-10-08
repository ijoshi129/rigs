import type { ReactNode } from "react";
import { DIM, heatColor } from "./theme";
import type { Sample } from "./store";

export function Deck({ children }: { children: ReactNode }) {
  return (
    <section className="rounded-deck border border-hairline bg-surface p-5 flex flex-col gap-4">{children}</section>
  );
}

export function BatteryBadge({ percent, charging }: { percent?: number; charging?: boolean }) {
  const level = percent ?? 0;
  const bars = level < 15 ? 0 : level < 40 ? 1 : level < 65 ? 2 : level < 90 ? 3 : 4;
  return (
    <span className="inline-flex items-center gap-1.5 text-[13px] font-medium text-dim tnum" aria-label={`Battery ${percent ?? "unknown"}%`}>
      <svg width="24" height="12" viewBox="0 0 24 12" aria-hidden="true">
        <rect x="0.5" y="0.5" width="20" height="11" rx="2.5" fill="none" stroke="currentColor" />
        <rect x="21.5" y="3.5" width="2" height="5" rx="1" fill="currentColor" />
        {Array.from({ length: bars }, (_, i) => (
          <rect key={i} x={2.5 + i * 4.25} y="2.5" width="3.5" height="7" rx="0.75" fill="currentColor" />
        ))}
        {charging && <path d="M11 1 7 7h3l-1 4 4-6h-3z" fill="var(--color-bg)" stroke="currentColor" strokeWidth="0.75" />}
      </svg>
      {percent !== undefined && <span>{percent}%</span>}
    </span>
  );
}

/** Live temperature as the hero: the number carries the heat color. */
export function HeroTemperature({ fahrenheit, label }: { fahrenheit?: number; label: string }) {
  return (
    <div className="flex flex-col">
      <div className="flex items-baseline gap-1">
        <span
          className="hero-number text-[76px] leading-none font-extrabold tnum tracking-tight"
          style={{ color: fahrenheit === undefined ? DIM : heatColor(fahrenheit) }}
        >
          {fahrenheit === undefined ? "—" : Math.round(fahrenheit)}
        </span>
        <span className="text-[26px] font-semibold text-dim">°F</span>
      </div>
      <span className="text-[13px] font-medium text-dim">{label}</span>
    </div>
  );
}

/** The one big control per rig. Says what it will do. */
export function SessionButton({
  heating, idleTitle, secondsRemaining, disabled, onClick,
}: { heating: boolean; idleTitle: string; secondsRemaining?: number; disabled?: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={heating ? "Stop session" : idleTitle}
      className={
        "flex items-center gap-2 w-full rounded-full px-5 py-4 text-[18px] font-semibold transition-opacity disabled:opacity-40 " +
        (heating ? "bg-raised text-ink ring-1 ring-inset ring-ember/60" : "bg-ember text-bg")
      }
    >
      {heating ? <StopIcon /> : <FlameIcon />}
      <span>{heating ? "Stop" : idleTitle}</span>
      {heating && secondsRemaining !== undefined && <span className="ml-auto tnum text-ink/80">{secondsRemaining} s</span>}
    </button>
  );
}

/** A preset or profile chip. Active state is the ember fill. */
export function PresetChip({ title, detail, active, disabled, onClick }: {
  title: string; detail: string; active: boolean; disabled?: boolean; onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={active}
      className={
        "shrink-0 min-w-[74px] rounded-[14px] px-3 py-2.5 text-left transition-opacity disabled:opacity-50 " +
        (active ? "bg-ember text-bg" : "bg-raised text-ink")
      }
    >
      <div className="text-[17px] font-bold tnum leading-tight">{title}</div>
      <div className="text-[12px] font-medium whitespace-nowrap leading-tight mt-0.5">{detail}</div>
    </button>
  );
}

/** Temperature over the session. The line takes the live temperature's color; the dashed rule is the target. */
export function HeatCurve({ samples, target, maximum }: { samples: Sample[]; target?: number; maximum: number }) {
  const W = 600, H = 120, L = 28, R = 6, T = 10, B = 6;
  const min = 50;
  const y = (f: number) => T + (H - T - B) * (1 - (Math.min(Math.max(f, min), maximum) - min) / (maximum - min));
  const current = samples[samples.length - 1]?.f ?? 100;
  const color = heatColor(current);
  const id = `g${Math.round(current)}`;

  let path = "", area = "";
  if (samples.length >= 2) {
    const t0 = samples[0]!.t, t1 = Math.max(samples[samples.length - 1]!.t, t0 + 1000);
    const x = (t: number) => L + ((t - t0) / (t1 - t0)) * (W - L - R);
    path = samples.map((s, i) => `${i ? "L" : "M"}${x(s.t).toFixed(1)} ${y(s.f).toFixed(1)}`).join(" ");
    area = `${path} L${x(samples[samples.length - 1]!.t).toFixed(1)} ${H - B} L${L} ${H - B} Z`;
  }
  const ticks = [200, 400, 600].filter((v) => v < maximum);

  return (
    <div className="relative">
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-[120px]" preserveAspectRatio="none" role="img" aria-label="Session temperature curve">
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={color} stopOpacity="0.35" />
            <stop offset="1" stopColor={color} stopOpacity="0" />
          </linearGradient>
        </defs>
        {ticks.map((v) => (
          <g key={v}>
            <line x1={L} x2={W - R} y1={y(v)} y2={y(v)} stroke="rgb(255 255 255 / 0.08)" />
            <text x={L - 6} y={y(v) + 3.5} fontSize="10" textAnchor="end" fill={DIM}>{v}</text>
          </g>
        ))}
        {target !== undefined && (
          <g>
            <line x1={L} x2={W - R} y1={y(target)} y2={y(target)} stroke={DIM} strokeOpacity="0.7" strokeDasharray="4 4" />
            <text x={W - R} y={y(target) - 4} fontSize="11" textAnchor="end" fill={DIM}>{Math.round(target)}°</text>
          </g>
        )}
        {area && <path d={area} fill={`url(#${id})`} />}
        {path && <path d={path} fill="none" stroke={color} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />}
      </svg>
      {samples.length < 2 && (
        <div className="absolute inset-0 flex items-center justify-center text-[13px] font-medium text-dim">
          Start a session to see the heat curve
        </div>
      )}
    </div>
  );
}

export function MenuButton({ onDisconnect }: { onDisconnect: () => void }) {
  return (
    <button
      type="button"
      onClick={() => { if (confirm("Disconnect this rig?")) onDisconnect(); }}
      className="text-dim hover:text-ink text-[13px] font-medium px-2 py-1 rounded-md hover:bg-raised"
    >
      Disconnect
    </button>
  );
}

const FlameIcon = () => (
  <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M12 2c1 4 5 6 5 11a5 5 0 0 1-10 0c0-2 1-3 1-3s0 3 2 3c1 0 1-1 1-2 0-2-1-3 1-9z" />
  </svg>
);
const StopIcon = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <rect x="5" y="5" width="14" height="14" rx="3" />
  </svg>
);
