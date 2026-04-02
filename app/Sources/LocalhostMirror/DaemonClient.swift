import Foundation

@MainActor
class DaemonClient: ObservableObject {
    @Published var tunnels: [Tunnel] = []
    @Published var isConnected = false
    @Published var tailscale: TailscaleInfo?
    @Published var lastError: String?

    private let baseURL = "http://127.0.0.1:19099"
    private var timer: Timer?

    func startPolling() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        Task {
            await fetchStatus()
            await fetchTunnels()
        }
    }

    private func fetchStatus() async {
        guard let url = URL(string: "\(baseURL)/api/status") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let status = try JSONDecoder().decode(StatusResponse.self, from: data)
            isConnected = status.daemon ?? false
            tailscale = status.tailscale
            lastError = nil
        } catch {
            isConnected = false
            tailscale = nil
        }
    }

    private func fetchTunnels() async {
        guard let url = URL(string: "\(baseURL)/api/tunnels") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(TunnelsResponse.self, from: data)
            tunnels = response.tunnels
        } catch {
            tunnels = []
        }
    }

    func expose(port: Int, name: String?) async -> ExposeResponse? {
        guard let url = URL(string: "\(baseURL)/api/tunnels") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["localPort": port]
        if let name = name, !name.isEmpty { body["name"] = name }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ExposeResponse.self, from: data)
            refresh()
            return response
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func stop(tunnelId: String) async {
        guard let url = URL(string: "\(baseURL)/api/tunnels/\(tunnelId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        _ = try? await URLSession.shared.data(for: request)
        refresh()
    }

    func startDaemon() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "cd \(projectPath()) && npx tsx \(daemonScriptPath()) >> ~/.localhost-mirror/daemon.log 2>&1 &"]
        task.currentDirectoryURL = URL(fileURLWithPath: projectPath())

        // Pipe output so the GUI process doesn't block
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            // Give the backgrounded daemon time to bind
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.refresh()
            }
        } catch {
            lastError = "Failed to start daemon: \(error.localizedDescription)"
        }
    }

    private func projectPath() -> String {
        // Find the project by looking relative to the app or at known path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Projects/localhost-mirror"
    }

    private func daemonScriptPath() -> String {
        return "\(projectPath())/src/daemon.ts"
    }
}
