#if DEBUG
import SwiftUI
import UIKit

/// Temporary device investigation tools, excluded from Release builds.
struct EdgeSAMDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var copied = false
    @State private var boxOnly = EdgeSAMDiagnosticBuffer.shared.knownGoodFirstPrompt

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("2564a3d first prompt (box only)", isOn: $boxOnly)
                    .onChange(of: boxOnly) { _, value in
                        EdgeSAMDiagnosticBuffer.shared.knownGoodFirstPrompt = value
                        EdgeSAMDiagnostics().event("experimentSetting", ["knownGoodFirstPrompt": "\(value)"])
                    }
                Text("Default is off. After changing this, close Outfit photo and reopen the same photo for a fresh first-garment run. Copy each run before clearing.")
                    .font(.footnote)
                HStack {
                    Button(copied ? "Copied" : "Copy diagnostics") {
                        text = EdgeSAMDiagnosticBuffer.shared.snapshot()
                        UIPasteboard.general.string = text
                        copied = true
                    }
                    Button("Refresh") { refresh() }
                    Button("Clear") {
                        EdgeSAMDiagnosticBuffer.shared.clear()
                        refresh()
                    }
                }
                ScrollView {
                    Text(text).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .navigationTitle("EdgeSAM diagnostics")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { refresh() }
        }
    }

    private func refresh() {
        text = EdgeSAMDiagnosticBuffer.shared.snapshot()
        copied = false
    }
}
#endif
