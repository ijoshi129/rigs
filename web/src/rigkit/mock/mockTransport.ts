import { type BLETransport, RigKitError } from "../transport";

/** An in-memory BLETransport. A simulator installs handlers and pushes notifications with `emit`. */
export class MockTransport implements BLETransport {
  private listeners = new Map<string, (d: Uint8Array) => void>();
  private disconnectHandlers: (() => void)[] = [];
  private open = true;

  onWrite?: (characteristic: string, data: Uint8Array) => void | Promise<void>;
  onRead?: (characteristic: string) => Uint8Array | Promise<Uint8Array>;

  async subscribe(characteristic: string, onValue: (d: Uint8Array) => void) {
    this.listeners.set(characteristic, onValue);
  }

  async write(characteristic: string, data: Uint8Array) {
    if (!this.open) throw new RigKitError("notConnected");
    await this.onWrite?.(characteristic, data);
  }

  async read(characteristic: string) {
    if (!this.open) throw new RigKitError("notConnected");
    if (!this.onRead) throw new RigKitError("unsupported", `read ${characteristic}`);
    return this.onRead(characteristic);
  }

  async disconnect() {
    if (!this.open) return;
    this.open = false;
    this.listeners.clear();
    for (const h of this.disconnectHandlers) h();
  }

  onDisconnect(handler: () => void) {
    this.disconnectHandlers.push(handler);
  }

  /** Pushes a notification to whoever subscribed. */
  emit(characteristic: string, data: Uint8Array) {
    this.listeners.get(characteristic)?.(data);
  }

  get isOpen() {
    return this.open;
  }
}
