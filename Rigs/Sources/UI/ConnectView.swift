import CoreBluetooth
import SwiftUI

/// Finds rigs in range and connects one. Shown inline when nothing is
/// connected, and as a sheet to add the second rig.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var inline = false

    var body: some View {
        Group {
            if let bt = model.bluetooth {
                content(bt)
            } else {
                Text("Both rigs are simulated on this device.")
                    .font(Theme.body).foregroundStyle(Theme.dim)
            }
        }
        .padding(inline ? 0 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func content(_ bt: BluetoothManager) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            switch bt.bluetoothState {
            case .poweredOn:
                scanner(bt)
            case .unauthorized:
                message("Rigs needs Bluetooth access.", detail: "Turn it on in Settings → Rigs.")
            case .poweredOff:
                message("Bluetooth is off.", detail: "Turn it on in Control Center to find your rigs.")
            default:
                message("Starting Bluetooth…", detail: nil)
            }
        }
        .onAppear { bt.startScan() }
        .onDisappear { bt.stopScan() }
    }

    private func scanner(_ bt: BluetoothManager) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(inline ? "Connect a rig" : "Add a rig").font(Theme.title).foregroundStyle(Theme.text)
                Spacer()
                if bt.isScanning { ProgressView().tint(Theme.dim) }
            }

            if bt.discovered.isEmpty {
                Text("Turn the rig on and keep it near your phone. On the Switch 2, hold + and − for 3 seconds if it doesn't appear. Close the official app if it's open.")
                    .font(Theme.body).foregroundStyle(Theme.dim)
            }

            ForEach(bt.discovered) { rig in
                let taken = (rig.kind == .switch2 && bt.switch2 != nil) || (rig.kind == .peakPro && bt.peakPro != nil)
                Button {
                    Task {
                        await bt.connect(rig)
                        if !inline, bt.lastError == nil { dismiss() }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rig.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                            Text(rig.kind.displayName).font(Theme.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        if bt.connecting == rig.id {
                            ProgressView().tint(Theme.dim)
                        } else {
                            Image(systemName: signalSymbol(rig.rssi)).foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(14)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(taken || bt.connecting != nil)
                .opacity(taken ? 0.4 : 1)
            }

            if let err = bt.lastError {
                Text(err).font(Theme.caption).foregroundStyle(.red)
            }

            if !bt.isScanning {
                Button("Scan again") { bt.startScan() }.font(Theme.body)
            }
        }
    }

    private func message(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.title).foregroundStyle(Theme.text)
            if let detail { Text(detail).font(Theme.body).foregroundStyle(Theme.dim) }
        }
    }

    private func signalSymbol(_ rssi: Int) -> String {
        switch rssi {
        case ..<(-85): "cellularbars"
        case ..<(-70): "chart.bar.fill"
        default: "wifi"
        }
    }
}
