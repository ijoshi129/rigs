import { formatTemp, useSettings } from "../settings";
import { type HistoryEntry, rigName, store, useRigs } from "../store";
import { Glass, Screen, SectionLabel } from "../ui";

const dayKey = (t: number) => new Date(t).toDateString();
const timeOf = (t: number) => new Date(t).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });

export function HistoryScreen() {
  const snap = useRigs();
  const s = useSettings();
  const h = snap.history;
  const today = h.filter((e) => dayKey(e.start) === dayKey(Date.now()));
  const targets = h.map((e) => e.targetF).filter((v): v is number => v !== undefined).sort((a, b) => a - b);
  const usual = targets.length ? targets[Math.floor(targets.length / 2)] : undefined;
  const lifetime = snap.switch2?.state.analytics.totalHeatingCycles ?? snap.peakPro?.state.totalDabs;

  // Last seven days, oldest first.
  const days = Array.from({ length: 7 }, (_, i) => { const d = new Date(); d.setDate(d.getDate() - (6 - i)); return d; });
  const counts = days.map((d) => h.filter((e) => dayKey(e.start) === d.toDateString()).length);
  const maxCount = Math.max(1, ...counts);

  const groups = new Map<string, HistoryEntry[]>();
  for (const e of h) { const k = dayKey(e.start); groups.set(k, [...(groups.get(k) ?? []), e]); }

  return (
    <Screen title="History" subtitle="Kept on this phone only">
      <div className="flex gap-2.5">
        <Tile n={String(today.length)} label="today" />
        <Tile n={usual !== undefined ? `${formatTemp(usual, s.units)}°` : "—"} label="usual" />
        <Tile n={lifetime !== undefined ? lifetime.toLocaleString() : "—"} label="on the rig" wide />
      </div>

      <div className="mt-5 flex justify-between px-1.5 text-[13px] font-semibold text-ink-2"><span>This week</span><span className="tnum">{counts.reduce((a, b) => a + b, 0)} sessions</span></div>
      <svg viewBox="0 0 350 64" className="w-full h-16 mt-2" role="img" aria-label={`Sessions per day this week: ${counts.join(", ")}`}>
        {counts.map((c, i) => {
          const hgt = Math.max(8, (c / maxCount) * 60);
          return <rect key={i} x={4 + i * 50} y={64 - hgt} width="40" height={hgt} rx="6" fill={i === 6 ? "var(--fill)" : "var(--track)"} />;
        })}
      </svg>
      <div className="flex justify-between px-[14px] mt-1 text-[11px] font-semibold text-ink-3">{days.map((d) => <span key={d.toDateString()}>{d.toLocaleDateString([], { weekday: "narrow" })}</span>)}</div>

      {h.length === 0 ? (
        <Glass className="mt-6 p-5"><p className="text-[15px] font-semibold">No sessions yet</p><p className="mt-1 text-[13px] font-medium text-ink-2">Each heat cycle you run from here gets logged, with its peak temperature.</p></Glass>
      ) : (
        Array.from(groups.entries()).map(([k, entries]) => (
          <div key={k}>
            <SectionLabel>{k === dayKey(Date.now()) ? "Today" : new Date(entries[0]!.start).toLocaleDateString([], { weekday: "long", month: "short", day: "numeric" })}</SectionLabel>
            <Glass className="overflow-hidden">
              {entries.map((e, i) => (
                <div key={e.id} className={`flex items-center gap-3 px-[18px] py-3 ${i < entries.length - 1 ? "border-b" : ""}`} style={{ borderColor: "rgba(127,127,127,0.18)" }}>
                  <span className="text-[13px] font-semibold text-ink-2 w-[62px] tnum">{timeOf(e.start)}</span>
                  <span className="rounded-face text-[24px] font-extrabold w-[62px] tnum">{e.targetF !== undefined ? `${formatTemp(e.targetF, s.units)}°` : "—"}</span>
                  <span className="flex flex-col flex-1 min-w-0">
                    <span className="text-[15px] font-semibold">{rigName[e.rig]}{e.profile ? ` · ${e.profile}` : ""}</span>
                    <span className="text-[12px] font-medium text-ink-2">
                      {[e.holdS ? `${e.holdS} s` : undefined, e.peakF ? `peaked ${formatTemp(e.peakF, s.units)}°` : undefined, e.extended ? "extended" : undefined, e.boosted ? "boosted" : undefined].filter(Boolean).join(" · ")}
                    </span>
                  </span>
                </div>
              ))}
            </Glass>
          </div>
        ))
      )}

      {h.length > 0 && (
        <button type="button" onClick={() => { if (confirm("Clear the whole history on this phone?")) store.clearHistory(); }} className="mt-6 text-[13px] font-semibold text-ink-2 underline px-1.5">Clear history</button>
      )}
      <p className="mt-5 px-1.5 text-[12px] font-medium text-ink-3 leading-relaxed">The rig's own lifetime counter is read from the device. The log of sessions is yours and never leaves the phone.</p>
    </Screen>
  );
}

function Tile({ n, label, wide }: { n: string; label: string; wide?: boolean }) {
  return (
    <Glass className={`${wide ? "flex-[1.2]" : "flex-1"} px-4 py-3.5 flex flex-col gap-0.5`} radius={22}>
      <span className="rounded-face text-[40px] font-extrabold leading-[0.95] tnum">{n}</span>
      <span className="text-[12px] font-semibold text-ink-2">{label}</span>
    </Glass>
  );
}
