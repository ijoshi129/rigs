import { useEffect } from "react";
import { ConnectPanel } from "./ConnectPanel";
import { PeakProDeck } from "./PeakProDeck";
import { Switch2Deck } from "./Switch2Deck";
import { store, useRigs } from "./store";

export function App() {
  const snap = useRigs();

  useEffect(() => {
    void store.reconnectRemembered();
  }, []);

  return (
    <main className="mx-auto max-w-[1100px] px-4 pb-10 pt-6 sm:pt-10">
      <h1 className="text-[40px] font-extrabold tracking-tight leading-none mb-6">Rigs</h1>
      <div className="grid gap-4 md:grid-cols-2 items-start">
        {snap.switch2 && <Switch2Deck slot={snap.switch2} />}
        {snap.peakPro && <PeakProDeck slot={snap.peakPro} />}
        <ConnectPanel snap={snap} />
      </div>
      {snap.mock && (
        <p className="mt-6 text-[13px] font-medium text-dim">Both rigs are simulated. Drop <code>?mock</code> from the address to use real ones.</p>
      )}
    </main>
  );
}
