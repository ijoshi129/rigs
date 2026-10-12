import { Switch2Render } from "../devices";
import { store, useRig } from "../store";
import { Glass, Screen } from "../ui";

const isIOS = () => /iPhone|iPad|iPod/.test(navigator.userAgent);

/** First run, and the place to forget or reconnect the rig later. */
export function ConnectScreen() {
  const snap = useRig();
  const firstRun = !snap.rig;

  return (
    <Screen title={firstRun ? undefined : "Your rig"} subtitle={firstRun ? undefined : "Connected over Bluetooth"} backTo={firstRun ? undefined : "/"}>
      {firstRun && (
        <div className="pt-8">
          <div className="rounded-face text-[64px] font-extrabold tracking-[-0.04em] leading-none">Rigs</div>
          <p className="mt-3.5 text-[17px] font-medium text-ink/80 leading-snug max-w-[300px]">Turn the Switch 2 on, close the Dr. Dabber app if it's open, and connect.</p>
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
          <a href="?mock&demo" className="inline-block mt-3 text-[14px] font-semibold underline">Try it with a simulated rig</a>
        </Glass>
      )}

      <Glass className="mt-8 flex items-center gap-4 p-5" radius={26}>
        <div className="shrink-0 w-[68px] flex justify-center"><Switch2Render height={118} /></div>
        <span className="flex flex-col gap-0.5 flex-1 min-w-0">
          <span className="text-[20px] font-extrabold">Switch 2</span>
          <span className="text-[13px] font-medium text-ink-2">{snap.rig ? (snap.rig.state.connected ? "Connected" : "Disconnected") : "Dr. Dabber · induction, 5 presets"}</span>
        </span>
        {snap.rig ? (
          <button type="button" onClick={() => { if (confirm("Forget this rig?")) void store.disconnect(); }} className="glass pressable h-10 px-4 rounded-full text-[14px] font-bold">Forget</button>
        ) : (
          <button
            type="button"
            disabled={snap.connecting || snap.mock || !snap.bluetoothAvailable}
            onClick={() => void store.connect()}
            className="pressable h-10 px-[18px] rounded-full text-[14px] font-extrabold"
            style={{ background: "var(--fill)", color: "var(--bg)" }}
          >
            {snap.connecting ? "Connecting…" : "Connect"}
          </button>
        )}
      </Glass>

      {snap.error && <p className="mt-4 text-[13px] font-semibold text-red-400">{snap.error}</p>}

      <Glass className="mt-5 p-4" radius={22}>
        <div className="text-[14px] font-bold">Rig not showing up?</div>
        <p className="mt-1 text-[13px] font-medium text-ink-2 leading-relaxed">
          Hold + and − together for 3 seconds to turn pairing on. The rig flashes and buzzes once. Pairing off saves battery, so it may have turned itself off.
          Make sure the Dr. Dabber app is fully closed on every device, and that this browser is allowed to use Bluetooth in your system settings.
        </p>
        {!snap.rig && snap.bluetoothAvailable && !snap.mock && (
          <button type="button" disabled={snap.connecting} onClick={() => void store.connect(true)} className="mt-3 text-[13px] font-semibold underline text-ink">Show every nearby device</button>
        )}
      </Glass>

      {snap.bluetoothAvailable && !snap.mock && (
        <p className="mt-5 px-1.5 text-[12px] font-medium text-ink-3 leading-relaxed">
          {store.canRemember
            ? "This browser remembers the rig: next time, the app reconnects on its own when the rig is on and nearby."
            : "This browser can't remember devices between visits, so you'll tap Connect and pick the rig each time you open the app. While the app is open, it reconnects on its own if the link drops."}
        </p>
      )}
      <p className="mt-4 text-[12px] font-medium text-ink-3 leading-relaxed">Nothing leaves your phone. No account, no cloud.{snap.mock && " The rig is simulated right now."} · v{__APP_VERSION__}</p>
    </Screen>
  );
}
