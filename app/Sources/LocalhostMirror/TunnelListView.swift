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
                || ($0.project?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !scanner.alerts.isEmpty { alertBanner }
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
        .frame(width: 440)
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

    // MARK: - Alert Banner

    private var alertBanner: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(scanner.alerts.suffix(5)) { alert in
                        HStack(spacing: 4) {
                            Image(systemName: alert.severity == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 9))
                            Text(alert.message)
                                .font(.system(size: 10))
                                .lineLimit(1)
                            Button(action: { scanner.dismissAlert(alert) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                            }
                            .buttonStyle(.borderless)
                        }
                        .foregroundColor(alert.severity == .critical ? .red : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((alert.severity == .critical ? Color.red : Color.orange).opacity(0.1))
                        .cornerRadius(4)
                    }

                    if scanner.alerts.count > 1 {
                        Button(action: { scanner.clearAlerts() }) {
                            Text("Clear all")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 6)
        }
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
                        tailscaleIp: client.tailscale?.ip ?? client.tailscale?.hostname ?? "?",
                        onExpose: { name in exposePort(port, name: name) },
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
        .frame(minHeight: 300, maxHeight: 500)
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
            if let error = client.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(minHeight: 120)
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

    private func exposePort(_ port: LocalPort, name: String) {
        let finalName = name.isEmpty ? (port.project ?? port.processName.lowercased()) : name
        Task {
            let response = await client.expose(port: port.port, name: finalName)
            if let r = response, r.ok {
                showToast("Exposed /\(finalName)")
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
        let host = client.tailscale?.ip ?? client.tailscale?.hostname ?? "?"
        let tunnel = client.tunnels.first { $0.localPort == port.port }
        let name = tunnel?.name ?? "port-\(port.port)"
        var url = "http://\(host):19100/\(name)"
        if let token = tunnel?.token, !token.isEmpty {
            url += "?token=\(token)"
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
    let tailscaleIp: String
    let onExpose: (String) -> Void
    let onStop: () -> Void
    let onCopy: () -> Void
    let onKill: () -> Void
    let onToast: (String) -> Void

    @State private var isHovered = false
    @State private var confirmKill = false
    @State private var showExposeInput = false
    @State private var exposeName = ""

    private var portColor: Color {
        CommonPorts.color(for: port.port, processName: port.processName)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status dot
            ZStack {
                Circle()
                    .fill(isExposed ? Color.green : portColor.opacity(0.6))
                    .frame(width: 6, height: 6)
                if port.hasAlert {
                    Circle()
                        .stroke(Color.red, lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                // Port number + labels
                HStack(spacing: 5) {
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

                    if port.stats?.isZombie == true {
                        Text("zombie")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.15))
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

                // Process info + project
                HStack(spacing: 0) {
                    Text(port.processName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(" · PID \(port.pid)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let project = port.project {
                        Text(" · ")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(project)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.cyan)
                    }
                }

                // CPU / RAM bar
                if let stats = port.stats {
                    HStack(spacing: 8) {
                        // CPU
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.system(size: 8))
                            Text(String(format: "%.0f%%", stats.cpu))
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundColor(port.hasHighCPU ? .red : .secondary)

                        // RAM
                        HStack(spacing: 3) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 8))
                            Text("\(stats.memoryMB)MB")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundColor(port.hasHighMemory ? .red : .secondary)
                    }
                }
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
                } else if showExposeInput {
                    HStack(spacing: 4) {
                        TextField("alias", text: $exposeName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 90)
                            .onSubmit { submitExpose() }
                            .onAppear {
                                exposeName = port.project ?? port.processName.lowercased()
                            }
                        Button(action: { submitExpose() }) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.borderless)
                        Button(action: { showExposeInput = false }) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    HStack(spacing: 4) {
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
                            Button(action: onCopy) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy Tailscale URL")

                            Button(action: onStop) {
                                Image(systemName: "stop.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.borderless)
                            .help("Stop tunnel")
                        } else {
                            Button(action: { showExposeInput = true }) {
                                Image(systemName: "arrow.up.right.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.borderless)
                            .help("Expose over Tailscale")
                        }

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
            if !hovering { confirmKill = false; showExposeInput = false }
        }
    }

    private func submitExpose() {
        onExpose(exposeName)
        showExposeInput = false
        exposeName = ""
    }
}
