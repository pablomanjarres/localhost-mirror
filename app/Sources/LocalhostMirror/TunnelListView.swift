import SwiftUI

struct TunnelListView: View {
    @ObservedObject var client: DaemonClient
    @ObservedObject var scanner: PortScanner
    @State private var searchText = ""
    @State private var toast: String?

    private var exposedPorts: Set<Int> {
        Set(client.tunnels.map { $0.localPort })
    }

    var filteredPorts: [LocalPort] {
        let ports = scanner.ports
        if searchText.isEmpty { return ports }
        return ports.filter {
            "\($0.port)".contains(searchText)
                || $0.processName.localizedCaseInsensitiveContains(searchText)
                || (scanner.portTitles[$0.port]?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (CommonPorts.label(for: $0.port, processName: $0.processName)?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if scanner.ports.count > 5 { searchBar }
            Divider()

            if !client.isConnected {
                disconnectedView
            } else if scanner.ports.isEmpty {
                emptyView
            } else if filteredPorts.isEmpty {
                noMatchView
            } else {
                portList
            }

            Divider()
            footer
        }
        .frame(width: 350)
        .onAppear {
            client.startPolling()
            scanner.startScanning()
        }
        .onDisappear {
            client.stopPolling()
            scanner.stopScanning()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Localhost Mirror")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            HStack(spacing: 10) {
                if !client.tunnels.isEmpty {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("\(client.tunnels.count) exposed")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Text("\(scanner.ports.count) ports")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button(action: { scanner.scan(); client.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var searchBar: some View {
        TextField("Filter ports...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
    }

    // MARK: - Port List

    private var portList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredPorts.enumerated()), id: \.element.id) { index, port in
                    PortRow(
                        port: port,
                        title: scanner.portTitles[port.port],
                        isExposed: exposedPorts.contains(port.port),
                        tunnel: client.tunnels.first { $0.localPort == port.port },
                        tailscaleHost: client.tailscale?.hostname ?? client.tailscale?.ip ?? "?",
                        onExpose: { exposePort(port) },
                        onStop: { stopTunnel(port) },
                        onCopy: { copyUrl(port) },
                        onKill: { scanner.killProcess(port) },
                        onToast: { showToast($0) }
                    )
                    if index < filteredPorts.count - 1 {
                        Divider().padding(.leading, 28)
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    // MARK: - States

    private var disconnectedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text("Daemon not running")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button("Start Daemon") { client.startDaemon() }
                .controlSize(.small)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "network.slash")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text("No listening ports")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }

    private var noMatchView: some View {
        Text("No matching ports")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let ts = client.tailscale {
                HStack(spacing: 4) {
                    Circle()
                        .fill(ts.isRunning ? Color.green : Color.red)
                        .frame(width: 5, height: 5)
                    Text(ts.isRunning ? String(ts.hostname.prefix(22)) : "Tailscale off")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let toast = toast {
                Text(toast)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func exposePort(_ port: LocalPort) {
        Task {
            let response = await client.expose(port: port.port, name: port.processName.lowercased())
            if let r = response, r.ok {
                showToast("Exposed :\(port.port)")
            } else {
                showToast(response?.error ?? "Failed")
            }
        }
    }

    private func stopTunnel(_ port: LocalPort) {
        if let tunnel = client.tunnels.first(where: { $0.localPort == port.port }) {
            Task {
                await client.stop(tunnelId: tunnel.id)
                showToast("Stopped")
            }
        }
    }

    private func copyUrl(_ port: LocalPort) {
        // Use raw IP — MagicDNS often doesn't resolve on iOS devices
        let host = client.tailscale?.ip ?? client.tailscale?.hostname ?? "?"
        let tunnel = client.tunnels.first { $0.localPort == port.port }
        var url = "http://\(host):19100/?tunnel=\(port.port)"
        if let token = tunnel?.token, !token.isEmpty {
            url += "&token=\(token)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        showToast("URL copied")
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Port Row

struct PortRow: View {
    let port: LocalPort
    let title: String?
    let isExposed: Bool
    let tunnel: Tunnel?
    let tailscaleHost: String
    let onExpose: () -> Void
    let onStop: () -> Void
    let onCopy: () -> Void
    let onKill: () -> Void
    let onToast: (String) -> Void

    @State private var isHovered = false
    @State private var confirmKill = false

    private var portColor: Color {
        CommonPorts.color(for: port.port, processName: port.processName)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status dot: green if exposed, colored by type otherwise
            Circle()
                .fill(isExposed ? Color.green : portColor.opacity(0.6))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                // Port number + labels
                HStack(spacing: 6) {
                    Text(":\(port.port)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))

                    if let label = CommonPorts.label(for: port.port, processName: port.processName) {
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(portColor.opacity(0.15))
                            .cornerRadius(3)
                    }

                    if isExposed {
                        Text("exposed")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(3)
                    }

                    if port.isLocalhostOnly && !isExposed {
                        Text("local")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(3)
                    }
                }

                // HTTP title
                if let title = title {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.7))
                        .lineLimit(1)
                }

                // Process info
                Text("\(port.processName) · PID \(port.pid)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Hover actions
            if isHovered {
                if confirmKill {
                    HStack(spacing: 4) {
                        Text("Kill?")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                        Button(action: { onKill(); confirmKill = false }) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        Button(action: { confirmKill = false }) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    HStack(spacing: 4) {
                        // Open locally
                        Button(action: {
                            if let url = URL(string: "http://localhost:\(port.port)") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("Open localhost:\(port.port)")

                        if isExposed {
                            // Copy tunnel URL
                            Button(action: onCopy) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy Tailscale URL")

                            // Stop tunnel
                            Button(action: onStop) {
                                Image(systemName: "stop.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.borderless)
                            .help("Stop tunnel")
                        } else {
                            // Expose
                            Button(action: onExpose) {
                                Image(systemName: "arrow.up.right.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.borderless)
                            .help("Expose over Tailscale")
                        }

                        // Kill process
                        Button(action: { confirmKill = true }) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.borderless)
                        .help("Kill process")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if !hovering { confirmKill = false }
        }
    }
}
