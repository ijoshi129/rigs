import { type BLETransport, RigKitError } from "../rigkit";

/** BLETransport over one Web Bluetooth device. Call `open` before anything else. */
export class WebBluetoothTransport implements BLETransport {
  private chars = new Map<string, BluetoothRemoteGATTCharacteristic>();
  private handlers: (() => void)[] = [];
  /** Services found on the device, for diagnostics. */
  readonly services: string[] = [];

  constructor(readonly device: BluetoothDevice) {
    device.addEventListener("gattserverdisconnected", () => {
      this.chars.clear();
      for (const h of this.handlers) h();
    });
  }

  /** Connects GATT and caches every characteristic under the given services. */
  async open(services: string[]) {
    const gatt = this.device.gatt;
    if (!gatt) throw new RigKitError("unsupported", "device has no GATT");
    const server = await gatt.connect();
    this.services.length = 0;
    for (const uuid of services) {
      try {
        const service = await server.getPrimaryService(uuid);
        this.services.push(uuid);
        for (const c of await service.getCharacteristics()) this.chars.set(c.uuid, c);
      } catch {
        // Service absent on this device; fine.
      }
    }
  }

  get characteristicUUIDs(): string[] {
    return Array.from(this.chars.keys());
  }

  has(characteristic: string) {
    return this.chars.has(characteristic);
  }

  private char(uuid: string) {
    const c = this.chars.get(uuid);
    if (!c) throw new RigKitError(this.device.gatt?.connected ? "unsupported" : "notConnected", `characteristic ${uuid}`);
    return c;
  }

  async subscribe(characteristic: string, onValue: (d: Uint8Array) => void) {
    const c = this.char(characteristic);
    c.addEventListener("characteristicvaluechanged", (e) => {
      const v = (e.target as BluetoothRemoteGATTCharacteristic).value;
      if (v) onValue(new Uint8Array(v.buffer.slice(v.byteOffset, v.byteOffset + v.byteLength)));
    });
    await c.startNotifications();
  }

  async write(characteristic: string, data: Uint8Array, withResponse = false) {
    const c = this.char(characteristic);
    const buf = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer;
    if (withResponse) await c.writeValueWithResponse(buf);
    else await c.writeValueWithoutResponse(buf);
  }

  async read(characteristic: string) {
    const v = await this.char(characteristic).readValue();
    return new Uint8Array(v.buffer.slice(v.byteOffset, v.byteOffset + v.byteLength));
  }

  async disconnect() {
    this.device.gatt?.disconnect();
  }

  onDisconnect(handler: () => void) {
    this.handlers.push(handler);
  }
}
