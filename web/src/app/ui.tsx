import type { ReactNode } from "react";
import { back, navigate, useRoute } from "./router";

export function Screen({ children, title, subtitle, backTo, action }: {
  children: ReactNode; title?: string; subtitle?: string; backTo?: string; action?: ReactNode;
}) {
  return (
    <main className="relative z-10 mx-auto max-w-[520px] min-h-full px-5 pb-[120px]" style={{ paddingTop: "calc(16px + env(safe-area-inset-top))" }}>
      {title && (
        <header className="flex items-center gap-3 mb-5">
          {backTo !== undefined && (
            <IconButton label="Back" onClick={() => (backTo ? navigate(backTo) : back())}>
              <ChevronLeft />
            </IconButton>
          )}
          <div className="flex flex-col min-w-0">
            <h1 className="text-[34px] font-light tracking-[-0.03em] leading-none">{title}</h1>
            {subtitle && <span className="text-[14px] text-ink-2 mt-1.5">{subtitle}</span>}
          </div>
          {action && <div className="ml-auto">{action}</div>}
        </header>
      )}
      {children}
    </main>
  );
}

export function Glass({ children, className = "", radius = 0 }: { children: ReactNode; className?: string; radius?: number }) {
  return (
    <div className={`glass ${className}`} style={{ borderRadius: radius }}>
      {children}
    </div>
  );
}

export function IconButton({ children, label, onClick, href }: { children: ReactNode; label: string; onClick?: () => void; href?: string }) {
  const cls = "glass pressable w-10 h-10 flex items-center justify-center text-ink shrink-0";
  if (href) return <a href={href} aria-label={label} className={cls}>{children}</a>;
  return <button type="button" aria-label={label} onClick={onClick} className={cls}>{children}</button>;
}

export function GlassButton({ children, onClick, disabled, prominent, className = "", label }: {
  children: ReactNode; onClick?: () => void; disabled?: boolean; prominent?: boolean; className?: string; label?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      className={`${prominent ? "glass-prominent" : "glass"} pressable h-[56px] px-8 text-[17px] font-medium flex items-center justify-center gap-2.5 ${className}`}
    >
      {children}
    </button>
  );
}

/** A capsule segmented control. Children are the segments; `active` index is lifted. */
export function Segmented<T extends string | number>({ options, value, onChange, disabled, render, onHold }: {
  options: T[]; value: T; onChange: (v: T) => void; disabled?: boolean; render?: (v: T) => ReactNode; onHold?: (v: T) => void;
}) {
  return (
    <div className="glass p-1 flex gap-0.5 h-12">
      {options.map((o) => {
        const active = o === value;
        return (
          <button
            key={String(o)}
            type="button"
            aria-pressed={active}
            disabled={disabled}
            onClick={() => onChange(o)}
            onPointerDown={onHold ? (e) => startHold(e, () => onHold(o)) : undefined}
            onContextMenu={onHold ? (e) => e.preventDefault() : undefined}
            className={`pressable flex-1 text-[15px] tnum ${active ? "glass-strong font-medium text-ink" : "text-ink-2"} disabled:opacity-50`}
          >
            {render ? render(o) : String(o)}
          </button>
        );
      })}
    </div>
  );
}

function startHold(e: React.PointerEvent, fire: () => void) {
  const el = e.currentTarget;
  const t = setTimeout(() => { fire(); if (navigator.vibrate) navigator.vibrate(10); }, 500);
  const cancel = () => { clearTimeout(t); el.removeEventListener("pointerup", cancel); el.removeEventListener("pointerleave", cancel); el.removeEventListener("pointercancel", cancel); };
  el.addEventListener("pointerup", cancel);
  el.addEventListener("pointerleave", cancel);
  el.addEventListener("pointercancel", cancel);
}

export function Toggle({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      onClick={() => onChange(!on)}
      className="relative w-[52px] h-8 shrink-0 transition-colors"
      style={{ background: on ? "var(--accent)" : "var(--track)" }}
    >
      <span className="absolute top-0.5 w-7 h-7 bg-white transition-[left]" style={{ left: on ? 22 : 2 }} />
    </button>
  );
}

export function Stepper({ value, onChange, min, max, step = 1, format, label }: {
  value: number; onChange: (v: number) => void; min: number; max: number; step?: number; format?: (v: number) => string; label: string;
}) {
  return (
    <div className="flex items-center h-9 p-[3px] gap-0.5" style={{ background: "var(--track)" }}>
      <button type="button" aria-label={`${label}: less`} disabled={value <= min} onClick={() => onChange(Math.max(min, value - step))} className="pressable w-9 h-[30px] text-[18px] leading-none disabled:opacity-40">−</button>
      <span className="font-medium text-[15px] min-w-[52px] text-center tnum">{format ? format(value) : value}</span>
      <button type="button" aria-label={`${label}: more`} disabled={value >= max} onClick={() => onChange(Math.min(max, value + step))} className="pressable w-9 h-[30px] text-[18px] leading-none disabled:opacity-40">+</button>
    </div>
  );
}

export function Row({ title, detail, children, last }: { title: string; detail?: string; children?: ReactNode; last?: boolean }) {
  return (
    <div className={`flex items-center justify-between gap-4 min-h-[54px] py-2 ${last ? "" : "border-b"}`} style={{ borderColor: "var(--line)" }}>
      <span className="flex flex-col min-w-0">
        <span className="text-[15px]">{title}</span>
        {detail && <span className="text-[12px] text-ink-2">{detail}</span>}
      </span>
      {children}
    </div>
  );
}

export function SectionLabel({ children }: { children: ReactNode }) {
  return <div className="text-[12px] uppercase tracking-[0.1em] text-ink-3 px-1 mt-7 mb-2.5">{children}</div>;
}

export function TabBar() {
  const route = useRoute();
  const tabs: { key: string; label: string; icon: ReactNode; match: string[] }[] = [
    { key: "", label: "Session", icon: <FlameIcon />, match: ["session", "connect"] },
    { key: "presets", label: "Presets", icon: <SlidersIcon />, match: ["presets", "preset"] },
    { key: "lights", label: "Lights", icon: <BulbIcon />, match: ["lights"] },
    { key: "history", label: "History", icon: <ClockIcon />, match: ["history"] },
  ];
  return (
    <nav aria-label="Main" className="fixed left-0 right-0 bottom-0 z-20 flex justify-center border-t" style={{ background: "rgba(5,6,8,0.92)", borderColor: "var(--line)", paddingBottom: "env(safe-area-inset-bottom)" }}>
      <div className="w-full max-w-[520px] flex">
        {tabs.map((t) => {
          const active = t.match.includes(route.name);
          return (
            <a
              key={t.key}
              href={`#/${t.key}`}
              aria-current={active ? "page" : undefined}
              className={`relative flex-1 h-[58px] flex flex-col items-center justify-center gap-1 text-[11px] no-underline ${active ? "text-ink" : "text-ink-3"}`}
            >
              {active && <span className="absolute top-0 w-8 h-[2px]" style={{ background: "var(--accent)", boxShadow: "0 0 8px var(--accent)" }} />}
              {t.icon}
              {t.label}
            </a>
          );
        })}
      </div>
    </nav>
  );
}

// ---- Icons (stroke, currentColor) --------------------------------------------

const I = ({ children, size = 20, fill = false }: { children: ReactNode; size?: number; fill?: boolean }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={fill ? "currentColor" : "none"} stroke={fill ? "none" : "currentColor"} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{children}</svg>
);
export const FlameIcon = () => <I fill><path d="M12 2c1 4 5 6 5 11a5 5 0 0 1-10 0c0-2 1-3 1-3s0 3 2 3c1 0 1-1 1-2 0-2-1-3 1-9z" /></I>;
export const SlidersIcon = () => <I><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2.5" /><circle cx="10" cy="17" r="2.5" /></I>;
export const BulbIcon = () => <I><path d="M9 18h6M10 21h4M12 3a6 6 0 0 0-4 10.5c.7.6 1 1.3 1 2.5h6c0-1.2.3-1.9 1-2.5A6 6 0 0 0 12 3z" /></I>;
export const ClockIcon = () => <I><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></I>;
export const GearIcon = () => <I size={18}><circle cx="12" cy="12" r="3" /><path d="M19 12a7 7 0 0 0-.1-1l2-1.5-2-3.4-2.3 1a7 7 0 0 0-1.7-1L14.5 3h-5l-.4 2.6a7 7 0 0 0-1.7 1l-2.3-1-2 3.4L5.1 11a7 7 0 0 0 0 2l-2 1.5 2 3.4 2.3-1a7 7 0 0 0 1.7 1l.4 2.6h5l.4-2.6a7 7 0 0 0 1.7-1l2.3 1 2-3.4-2-1.5c.1-.3.1-.7.1-1z" /></I>;
export const SwapIcon = () => <I size={18}><path d="M7 7h11l-3-3M17 17H6l3 3" /></I>;
export const ChevronLeft = () => <I size={18}><path d="M15 5l-7 7 7 7" /></I>;
export const ChevronRight = () => <I size={16}><path d="M9 5l7 7-7 7" /></I>;
export const StopIcon = () => <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><rect width="14" height="14" fill="currentColor" /></svg>;
export const BoltIcon = () => <I size={18} fill><path d="M13 2 4 14h6l-1 8 9-12h-6z" /></I>;

/** Small glyph of a Switch 2 heating-profile shape. */
export function ProfileGlyph({ code, width = 26 }: { code?: number; width?: number }) {
  const d: Record<number, string> = {
    161: "M1 6 H25", 177: "M1 10 C 10 10, 14 2, 25 2", 193: "M1 2 C 10 2, 14 10, 25 10",
    209: "M1 2 C 7 2, 9 10, 13 10 S 19 2, 25 2", 225: "M1 10 C 7 10, 9 2, 13 2 S 19 10, 25 10", 241: "M1 8 L7 3 L13 7 L19 2 L25 6",
  };
  const path = code !== undefined ? d[code] : undefined;
  if (!path) return null;
  return <svg width={width} height={(width * 12) / 26} viewBox="0 0 26 12" aria-hidden="true"><path d={path} fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}
