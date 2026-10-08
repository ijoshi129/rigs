import { Deck } from "./components";
import { type RigKind, type Snapshot, rigName, store } from "./store";

const isIOS = () => /iPhone|iPad|iPod/.test(navigator.userAgent);

/** Adds a rig. Shown as its own deck while a slot is empty. */
export function ConnectPanel({ snap }: { snap: Snapshot }) {
  const missing = (["switch2", "peakPro"] as RigKind[]).filter((k) => !snap[k]);
  if (snap.mock || missing.length === 0) return null;

  if (!snap.bluetoothAvailable) {
    return (
      <Deck>
        <h2 className="text-[22px] font-bold leading-none">This browser can't reach Bluetooth</h2>
        <p className="text-dim">
          {isIOS()
            ? "On iPhone, open this page in Bluefy, Path Browser, or LabLink. Safari and Chrome for iOS don't support Web Bluetooth."
            : "Use Chrome, Edge, or Brave. Safari and Firefox don't support Web Bluetooth."}
        </p>
      </Deck>
    );
  }

  return (
    <Deck>
      <h2 className="text-[22px] font-bold leading-none">{snap.switch2 || snap.peakPro ? "Add a rig" : "Connect a rig"}</h2>
      <p className="text-dim">
        Turn the rig on and keep it near this device. Close the official app if it's open. On the Switch 2, hold + and − for 3 seconds if it doesn't appear.
      </p>
      <div className="flex flex-col gap-2">
        {missing.map((kind) => (
          <button
            key={kind}
            type="button"
            disabled={snap.connecting !== undefined}
            onClick={() => void store.connect(kind)}
            className="flex items-center justify-between rounded-2xl bg-raised px-4 py-3.5 text-left disabled:opacity-50"
          >
            <span className="text-[17px] font-semibold">{rigName[kind]}</span>
            <span className="text-[13px] font-medium text-dim">{snap.connecting === kind ? "Connecting…" : "Connect"}</span>
          </button>
        ))}
      </div>
      {snap.error && <p className="text-[13px] font-medium text-red-400">{snap.error}</p>}
    </Deck>
  );
}
