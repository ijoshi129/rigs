import { type RigKind, rigName, store, useRigs } from "../store";
import { Glass, Screen } from "../ui";

const isIOS = () => /iPhone|iPad|iPod/.test(navigator.userAgent);

/** First run, and the place to add or forget a rig later. */
export function ConnectScreen() {
  const snap = useRigs();
  const firstRun = !snap.switch2 && !snap.peakPro;

  return (
    <Screen title={firstRun ? undefined : "Rigs"} subtitle={firstRun ? undefined : "Connected over Bluetooth"} backTo={firstRun ? undefined : "/"}>
      {firstRun && (
        <div className="pt-8">
          <div className="rounded-face text-[64px] font-extrabold tracking-[-0.04em] leading-none">Rigs</div>
          <p className="mt-3.5 text-[17px] font-medium text-ink/80 leading-snug max-w-[300px]">Pick the rig next to you. Turn it on first, and close its official app if it's open.</p>
        </div>
      )}

      {!snap.bluetoothAvailable && !snap.mock && (
        <Glass className="mt-8 p-5">
          <div className="text-[18px] font-bold">This browser can't reach Bluetooth</div>
          <p className="mt-1.5 text-[14px] font-medium text-ink-2 leading-relaxed">
            {isIOS()
              ? "On iPhone, open this page in Bluefy, Path Browser, or LabLink. Safari and Chrome for iOS don't support Web Bluetooth."
              : "Use Chrome, Edge, or Brave. Safari and Firefox don't support Web Bluetooth."}
          </p>
          <a href="?mock&demo" className="inline-block mt-3 text-[14px] font-semibold underline">Try it with simulated rigs</a>
        </Glass>
      )}

      <div className="mt-8 flex flex-col gap-3">
        {(["switch2", "peakPro"] as RigKind[]).map((kind) => (
          <RigCard key={kind} kind={kind} connected={!!snap[kind]} connecting={snap.connecting === kind} busy={snap.connecting !== undefined} mock={snap.mock} available={snap.bluetoothAvailable} />
        ))}
      </div>

      {snap.error && <p className="mt-4 text-[13px] font-semibold text-red-400">{snap.error}</p>}

      <Glass className="mt-5 p-4" radius={22}>
        <div className="text-[14px] font-bold">Rig not showing up?</div>
        <p className="mt-1 text-[13px] font-medium text-ink-2 leading-relaxed">Switch 2: hold + and − together for 3 seconds to turn pairing on.<br />Peak Pro: hold the power button until the light bar turns blue.</p>
      </Glass>

      <p className="mt-6 text-[12px] font-medium text-ink-3 leading-relaxed">Nothing leaves your phone. No account, no cloud.{snap.mock && " Both rigs are simulated right now."}</p>
    </Screen>
  );
}

function RigCard({ kind, connected, connecting, busy, mock, available }: { kind: RigKind; connected: boolean; connecting: boolean; busy: boolean; mock: boolean; available: boolean }) {
  const detail = kind === "switch2" ? "Dr. Dabber · induction, 5 presets" : "Puffco · 4 profiles, lantern";
  return (
    <Glass className="flex items-center gap-4 p-5" radius={26}>
      {kind === "switch2" ? (
        <svg width="44" height="58" viewBox="0 0 56 72" aria-hidden="true" className="text-ink/85"><rect x="6" y="2" width="44" height="68" rx="10" fill="none" stroke="currentColor" strokeWidth="2" /><circle cx="28" cy="22" r="11" fill="none" stroke="currentColor" strokeWidth="2" /><rect x="18" y="44" width="20" height="6" rx="3" fill="currentColor" /><rect x="18" y="56" width="20" height="6" rx="3" fill="currentColor" opacity="0.4" /></svg>
      ) : (
        <svg width="44" height="58" viewBox="0 0 56 72" aria-hidden="true" className="text-ink/85"><path d="M14 70 C 6 70, 4 62, 8 54 L 20 30 L 36 30 L 48 54 C 52 62, 50 70, 42 70 Z" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" /><rect x="20" y="4" width="16" height="26" rx="6" fill="none" stroke="currentColor" strokeWidth="2" /><circle cx="28" cy="56" r="5" fill="currentColor" /></svg>
      )}
      <span className="flex flex-col gap-0.5 flex-1 min-w-0">
        <span className="text-[20px] font-extrabold">{rigName[kind]}</span>
        <span className="text-[13px] font-medium text-ink-2">{connected ? "Connected" : detail}</span>
      </span>
      {connected ? (
        <button type="button" onClick={() => { if (confirm(`Disconnect ${rigName[kind]}?`)) void store.disconnect(kind); }} className="glass pressable h-10 px-4 rounded-full text-[14px] font-bold">Forget</button>
      ) : (
        <button
          type="button"
          disabled={busy || mock || !available}
          onClick={() => void store.connect(kind)}
          className="pressable h-10 px-[18px] rounded-full text-[14px] font-extrabold"
          style={{ background: "var(--fill)", color: "var(--bg)" }}
        >
          {connecting ? "Connecting…" : "Connect"}
        </button>
      )}
    </Glass>
  );
}
