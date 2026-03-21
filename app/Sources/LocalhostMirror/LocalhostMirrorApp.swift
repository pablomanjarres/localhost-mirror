import SwiftUI

@main
struct LocalhostMirrorApp: App {
    @StateObject private var client = DaemonClient()
    @StateObject private var scanner = PortScanner()

    var body: some Scene {
        MenuBarExtra {
            TunnelListView(client: client, scanner: scanner)
        } label: {
            Image(systemName: "arrow.triangle.swap")
        }
        .menuBarExtraStyle(.window)
    }
}
