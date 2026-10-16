import { useEffect, useState } from "react";
import { Switch2Photo } from "../devices";
import { store, useRig } from "../store";
import { Glass, Screen } from "../ui";

const isIOS = () => /iPhone|iPad|iPod/.test(navigator.userAgent);

/** First run, and the place to forget or reconnect the rig later. */
export function ConnectScreen() {
  const snap = useRig();
  if (!snap.rig) return <FirstRun />;
  return <ManageRig />;
}

/** Before any rig is connected: the device, one line, one button. */
function FirstRun() {
  const snap = useRig();
  const [help, setHelp] = useState(false);
  const noBluetooth = !snap.bluetoothAvailable && !snap.mock;

  const line = noBluetooth
    ? (isIOS() ? "This browser can't use Bluetooth. Open this page in Bluefy." : "This browser can't use Bluetooth. Open this page in Chrome or Edge.")
    : snap.error ?? (snap.connecting ? "Looking for your rig…" : "Turn it on, then press the button.");

  return (
    <main className="relative mx-auto max-w-[520px] min-h-[100dvh] overflow-hidden flex flex-col px-7"
      style={{ paddingTop: "calc(16px + env(safe-area-inset-top))", paddingBottom: "calc(36px + env(safe-area-inset-bottom))" }}>
      <div aria-hidden="true" className="absolute inset-0 pointer-events-none flex justify-center">
        <div className={`absolute w-[420px] h-[300px] top-[22%] ${snap.connecting ? "animate-[breathe_1.6s_ease-in-out_infinite]" : ""}`}
          style={{ background: "radial-gradient(closest-side, rgba(0,225,237,0.28), transparent)", filter: "blur(10px)" }} />
        <div className="absolute top-[11%]" style={{ opacity: noBluetooth ? 0.4 : 1 }}><Switch2Photo height={640} /></div>
        <div className="absolute inset-x-0 bottom-0 h-[50%]" style={{ background: "linear-gradient(transparent, var(--bg) 45%)" }} />
      </div>

      <header className="relative flex items-center justify-between h-10">
        <span className="text-[15px] font-medium">Rigs</span>
        <button type="button" onClick={() => setHelp(true)} className="h-10 -mr-2 px-2 text-[15px] text-ink-2">Help</button>
      </header>

      <div className="flex-1" />

      <div className="relative">
        <h1 className="text-[40px] font-light tracking-[-0.02em] leading-none">Switch 2</h1>
        <p className={`mt-2.5 text-[16px] leading-snug max-w-[320px] ${snap.error && !noBluetooth ? "text-[#ff7a6b]" : "text-ink-2"}`} aria-live="polite">{line}</p>
        {noBluetooth ? (
          <a href="?mock&demo" className="pressable mt-8 inline-flex items-center gap-4 text-[18px] no-underline text-ink">
            <span className="ring-button w-[78px] h-[78px] flex items-center justify-center"><PowerIcon /></span>Try a simulated rig
          </a>
        ) : (
          <button type="button" disabled={snap.connecting} onClick={() => void store.connect()} className="pressable mt-8 flex items-center gap-4 text-[18px] disabled:opacity-100">
            <span className="ring-button w-[78px] h-[78px] flex items-center justify-center"><PowerIcon /></span>
            {snap.connecting ? "Searching…" : "Connect"}
          </button>
        )}
      </div>

      {help && <TroubleSheet onClose={() => setHelp(false)} />}
    </main>
  );
}

const PowerIcon = () => (
  <svg width="26" height="30" viewBox="0 0 24 28" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden="true"><path d="M7 7.5a9 9 0 1 0 10 0" /><path d="M12 3v10" /></svg>
);

function TroubleSheet({ onClose }: { onClose: () => void }) {
  const snap = useRig();
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const steps = [
    ["Turn pairing on", "Hold + and − together for 3 seconds. The rig flashes and buzzes."],
    ["Close the Dr. Dabber app", "On every phone and tablet nearby. Only one app can connect at a time."],
    ["Allow Bluetooth", "Check that this browser has Bluetooth permission in Settings."],
  ];

  return (
    <div className="fixed inset-0 z-30 flex items-end justify-center" role="dialog" aria-modal="true" aria-label="Help connecting">
      <button type="button" aria-label="Close" onClick={onClose} className="absolute inset-0 bg-black/50 animate-[fade_200ms_ease-out]" />
      <div className="relative w-full max-w-[520px] px-6 pt-6 border-t animate-[rise_260ms_cubic-bezier(0.2,0.8,0.2,1)]"
        style={{ background: "var(--sheet)", borderColor: "var(--line)", paddingBottom: "calc(24px + env(safe-area-inset-bottom))" }}>
        <h2 className="text-[24px] font-light tracking-[-0.02em]">Having trouble?</h2>
        <ol className="mt-4 flex flex-col gap-4">
          {steps.map(([title, body], i) => (
            <li key={title} className="flex gap-3.5">
              <span className="shrink-0 w-5 pt-px text-[15px] tnum text-accent">{i + 1}</span>
              <span className="flex flex-col">
                <span className="text-[16px] font-medium">{title}</span>
                <span className="text-[14px] text-ink-2 leading-snug">{body}</span>
              </span>
            </li>
          ))}
        </ol>
        {snap.bluetoothAvailable && !snap.mock && (
          <button type="button" disabled={snap.connecting} onClick={() => { onClose(); void store.connect(true); }}
            className="pressable mt-6 w-full h-[50px] text-[16px] glass">
            Show every nearby device
          </button>
        )}
        <button type="button" onClick={onClose} className="mt-2 w-full h-[44px] text-[16px] font-medium text-ink-2">Done</button>
      </div>
    </div>
  );
}

/** With a rig attached: reached from Settings to forget or reconnect it. */
function ManageRig() {
  const snap = useRig();
  const connected = snap.rig?.state.connected ?? false;

  return (
    <Screen title="Your rig" subtitle="Connected over Bluetooth" backTo="/">
      <Glass className="mt-8 flex items-center gap-4 p-5">
        <div className="shrink-0 w-[56px] flex justify-center"><Switch2Photo height={110} dim={!connected} /></div>
        <span className="flex flex-col gap-0.5 flex-1 min-w-0">
          <span className="text-[20px] font-light">Switch 2</span>
          <span className={`text-[13px] ${connected ? "text-accent" : "text-ink-2"}`}>{connected ? "Connected" : "Disconnected"}</span>
        </span>
        <button type="button" onClick={() => { if (confirm("Forget this rig?")) void store.disconnect(); }} className="glass-strong pressable h-10 px-4 text-[14px]">Forget</button>
      </Glass>

      {snap.error && <p className="mt-4 text-[13px] font-semibold text-red-400">{snap.error}</p>}

      {snap.bluetoothAvailable && !snap.mock && (
        <p className="mt-5 px-1.5 text-[12px] text-ink-3 leading-relaxed">
          {store.canRemember
            ? "This browser remembers the rig and reconnects on its own when it's on and nearby."
            : "This browser can't remember the rig between visits, so you'll pick it each time you open the app."}
        </p>
      )}
      <p className="mt-4 px-1.5 text-[12px] text-ink-3 leading-relaxed">Nothing leaves your phone. No account, no cloud.</p>
    </Screen>
  );
}
