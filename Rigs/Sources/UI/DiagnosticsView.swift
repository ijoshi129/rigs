import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// The Bluetooth log, newest first, with a share button that exports all of it.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var packets = true
    @State private var confirmClear = false
    /// Bumped by Clear so the timeline redraws at once.
    @State private var cleared = 0

    /// Rendering thousands of rows is slow; the export has the rest.
    private let shown = 600

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Diagnostics", subtitle: "What happened on the Bluetooth link", showsBack: true)

            HStack(spacing: 10) {
                SquareSegmented(options: [true, false], selection: packets, label: { $0 ? "Everything" : "Events" }) { packets = $0 }
                ShareLink(item: DiagnosticsFile(model: model), preview: SharePreview("Rigs diagnostics")) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(Theme.surfaceStrong)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Share diagnostics")
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let _ = cleared
                let all = Diagnostics.shared.snapshot()
                let entries = Array(all.reversed().lazy.filter { packets || !$0.kind.isPacket }.prefix(shown))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if entries.isEmpty {
                            Text("Nothing yet. Connect to the rig and everything it says shows up here.")
                                .font(.geist(13)).foregroundStyle(Theme.ink2).padding(.vertical, 16)
                        }
                        ForEach(entries) { DiagnosticsRow(entry: $0) }
                    }
                    .padding(.vertical, 8)
                }
                .overlay(alignment: .bottom) {
                    Text("\(all.count) entries this run · Share sends earlier runs too")
                        .font(.geist(11)).foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Theme.background.opacity(0.94))
                }
            }
            .padding(.top, 14)

            Button("Clear log") { confirmClear = true }
                .font(.geist(14)).foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity).frame(height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 70)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Clear the diagnostics log?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                Diagnostics.shared.clear()
                cleared += 1
            }
        }
    }
}

private struct DiagnosticsRow: View {
    let entry: Diagnostics.Entry

    private var color: Color {
        switch entry.kind {
        case .error: Theme.error
        case .tx: Theme.accent
        case .rx: Theme.ink2
        case .ble, .app: Theme.ink
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(Diagnostics.timeFormatter.string(from: entry.time)).foregroundStyle(Theme.ink3)
                Text(entry.kind.rawValue).foregroundStyle(color)
                if entry.repeats > 1 { Text("×\(entry.repeats)").foregroundStyle(Theme.ink3) }
            }
            Text(entry.text)
                .foregroundStyle(entry.kind == .error ? Theme.error : Theme.ink)
                .textSelection(.enabled)
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }
}

/// Built when the share sheet asks for it, so the export is never stale.
struct DiagnosticsFile: Transferable {
    let model: AppModel

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let url = await MainActor.run { Diagnostics.shared.export(rig: file.model.rig) }
            return SentTransferredFile(url)
        }
    }
}

/// The diagnostics screen in a sheet, for the connect screen's help.
struct DiagnosticsSheet: View {
    var body: some View {
        NavigationStack { DiagnosticsView() }
            .presentationCornerRadius(0)
            .presentationBackground(Theme.background)
    }
}
