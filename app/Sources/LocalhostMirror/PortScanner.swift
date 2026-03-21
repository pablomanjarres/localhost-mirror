import Foundation

struct ProcessStats {
    let cpu: Double    // percentage
    let memory: Double // percentage (of total RAM)
    let memoryMB: Int  // in MB
    let state: String  // R, S, Z, etc.
    var isZombie: Bool { state.contains("Z") }
}

struct LocalPort: Identifiable {
    let port: Int
    let processName: String
    let pid: Int
    let address: String
    var project: String?
    var stats: ProcessStats?

    var id: String { "\(port)-\(pid)" }
    var isLocalhostOnly: Bool { address == "127.0.0.1" || address == "localhost" }
    var hasHighCPU: Bool { (stats?.cpu ?? 0) > 80 }
    var hasHighMemory: Bool { (stats?.memoryMB ?? 0) > 500 }
    var hasAlert: Bool { hasHighCPU || hasHighMemory || (stats?.isZombie ?? false) }
}

struct Alert: Identifiable {
    let id = UUID()
    let message: String
    let severity: Severity
    let port: Int?
    let timestamp: Date

    enum Severity { case warning, critical }
}

@MainActor
class PortScanner: ObservableObject {
    @Published var ports: [LocalPort] = []
    @Published var portTitles: [Int: String] = [:]
    @Published var alerts: [Alert] = []
    private var timer: Timer?
    private var fetchedPorts = Set<Int>()
    private var previousPortSet = Set<Int>()

    private let hiddenPorts: Set<Int> = [19099, 19100]
    private let maxAlerts = 20

    private static let nonHTTPPorts: Set<Int> = [
        3306, 5432, 6379, 6380, 27017, 27018, 5984, 8529,
        9200, 9300, 7474, 7687, 26257, 8123,
        5672, 15672, 9092, 2181, 4222, 11211,
        2375, 2376, 2377, 11434, 11435,
        9229, 9230, 5858, 49152,
    ]

    // Well-known project markers to walk up and find
    private nonisolated static let projectMarkers = [
        "package.json", "Cargo.toml", "go.mod", "pyproject.toml",
        "Gemfile", "Package.swift", "Makefile", "docker-compose.yml",
        "pom.xml", "build.gradle",
    ]

    func startScanning() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func stopScanning() {
        timer?.invalidate()
        timer = nil
    }

    func scan() {
        Task.detached { [weak self] in
            var results = Self.scanPorts()
            let pids = results.map { $0.pid }

            // Batch fetch stats + projects for all PIDs
            let statsMap = Self.fetchStats(pids: pids)
            let projectMap = Self.fetchProjects(pids: pids)

            for i in results.indices {
                results[i].stats = statsMap[results[i].pid]
                results[i].project = projectMap[results[i].pid]
            }

            await MainActor.run {
                guard let self = self else { return }
                let activePorts = Set(results.map(\.port))

                // Clean up titles for disappeared ports
                for port in self.fetchedPorts where !activePorts.contains(port) {
                    self.portTitles.removeValue(forKey: port)
                    self.fetchedPorts.remove(port)
                }

                let filtered = results.filter { !self.hiddenPorts.contains($0.port) }

                // Generate alerts
                self.detectAlerts(old: self.ports, new: filtered)

                self.ports = filtered
                self.previousPortSet = activePorts

                // Fetch titles for new ports
                for p in self.ports where !self.fetchedPorts.contains(p.port) {
                    self.fetchTitle(for: p)
                }
            }
        }
    }

    func dismissAlert(_ alert: Alert) {
        alerts.removeAll { $0.id == alert.id }
    }

    func clearAlerts() {
        alerts.removeAll()
    }

    func killProcess(_ port: LocalPort) {
        Task.detached {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/kill")
            task.arguments = [String(port.pid)]
            try? task.run()
            task.waitUntilExit()
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run { [weak self] in
                self?.portTitles.removeValue(forKey: port.port)
                self?.fetchedPorts.remove(port.port)
                self?.scan()
            }
        }
    }

    // MARK: - Alerts

    private func detectAlerts(old: [LocalPort], new: [LocalPort]) {
        let oldPorts = Set(old.map(\.port))
        let newPorts = Set(new.map(\.port))

        // Ports that died unexpectedly (not killed by user)
        if !oldPorts.isEmpty {
            let died = oldPorts.subtracting(newPorts).subtracting(hiddenPorts)
            for port in died {
                if let p = old.first(where: { $0.port == port }) {
                    addAlert(.warning, ":\(port) (\(p.processName)) stopped", port: port)
                }
            }
        }

        // Check each new port for anomalies
        for port in new {
            guard let stats = port.stats else { continue }

            if stats.isZombie {
                addAlert(.critical, ":\(port.port) (\(port.processName)) is a zombie process", port: port.port)
            }
            if port.hasHighCPU {
                // Only alert once — check if we already have a recent alert for this
                let hasRecent = alerts.contains { $0.port == port.port && $0.message.contains("CPU") &&
                    Date().timeIntervalSince($0.timestamp) < 30 }
                if !hasRecent {
                    addAlert(.warning, ":\(port.port) CPU at \(String(format: "%.0f", stats.cpu))%", port: port.port)
                }
            }
            if port.hasHighMemory {
                let hasRecent = alerts.contains { $0.port == port.port && $0.message.contains("RAM") &&
                    Date().timeIntervalSince($0.timestamp) < 30 }
                if !hasRecent {
                    addAlert(.warning, ":\(port.port) RAM at \(stats.memoryMB)MB", port: port.port)
                }
            }
        }

        // Trim old alerts
        if alerts.count > maxAlerts {
            alerts = Array(alerts.suffix(maxAlerts))
        }
    }

    private func addAlert(_ severity: Alert.Severity, _ message: String, port: Int?) {
        alerts.append(Alert(message: message, severity: severity, port: port, timestamp: Date()))
    }

    // MARK: - Stats (CPU/RAM)

    private nonisolated static func fetchStats(pids: [Int]) -> [Int: ProcessStats] {
        guard !pids.isEmpty else { return [:] }
        let pidList = pids.map(String.init).joined(separator: ",")
        let output = shell("ps -p \(pidList) -o pid=,pcpu=,pmem=,rss=,state= 2>/dev/null")
        var result: [Int: ProcessStats] = [:]

        for line in output.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5 else { continue }
            guard let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let mem = Double(parts[2]),
                  let rssKB = Int(parts[3]) else { continue }
            let state = String(parts[4])
            result[pid] = ProcessStats(cpu: cpu, memory: mem, memoryMB: rssKB / 1024, state: state)
        }
        return result
    }

    // MARK: - Project Detection

    private nonisolated static func fetchProjects(pids: [Int]) -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        var result: [Int: String] = [:]

        for pid in pids {
            // Get the current working directory of the process
            let output = shell("lsof -p \(pid) -Fn 2>/dev/null | grep '^n/' | head -5")
            var cwd: String?

            for line in output.components(separatedBy: "\n") {
                guard line.hasPrefix("n/") else { continue }
                let path = String(line.dropFirst()) // remove 'n' prefix
                // Look for cwd entry (usually first directory)
                if FileManager.default.fileExists(atPath: path) {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                    if isDir.boolValue {
                        cwd = path
                        break
                    }
                }
            }

            // If no cwd from lsof, try /proc-style approach via pwdx equivalent
            if cwd == nil {
                let pwdOutput = shell("lsof -d cwd -p \(pid) -Fn 2>/dev/null | grep '^n/'").trimmingCharacters(in: .whitespacesAndNewlines)
                if pwdOutput.hasPrefix("n/") {
                    cwd = String(pwdOutput.dropFirst())
                }
            }

            guard let dir = cwd else { continue }

            // Walk up to find project root
            if let projectName = findProjectRoot(from: dir) {
                result[pid] = projectName
            }
        }
        return result
    }

    private nonisolated static func findProjectRoot(from path: String) -> String? {
        var current = path
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        while current.count > 1 && current != home && current != "/" {
            for marker in projectMarkers {
                let markerPath = (current as NSString).appendingPathComponent(marker)
                if FileManager.default.fileExists(atPath: markerPath) {
                    return (current as NSString).lastPathComponent
                }
            }
            // Also check for .git
            let gitPath = (current as NSString).appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitPath) {
                return (current as NSString).lastPathComponent
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    // MARK: - Title Fetching

    private func fetchTitle(for port: LocalPort) {
        guard !Self.nonHTTPPorts.contains(port.port) else { return }
        fetchedPorts.insert(port.port)

        guard let url = URL(string: "http://localhost:\(port.port)") else { return }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "GET"

        URLSession(configuration: .ephemeral).dataTask(with: request) { [weak self] data, response, _ in
            guard let data = data else { return }
            var title: String?

            if let html = String(data: data, encoding: .utf8) {
                title = Self.extractTitle(from: html)
            }
            if title == nil, let http = response as? HTTPURLResponse,
               let server = http.value(forHTTPHeaderField: "Server") {
                title = server
            }

            if let title = title, !title.isEmpty {
                DispatchQueue.main.async { self?.portTitles[port.port] = title }
            }
        }.resume()
    }

    private nonisolated static func extractTitle(from html: String) -> String? {
        guard let startRange = html.range(of: "<title", options: .caseInsensitive) else { return nil }
        guard let tagClose = html[startRange.upperBound...].range(of: ">") else { return nil }
        guard let endRange = html[tagClose.upperBound...].range(of: "</title>", options: .caseInsensitive) else { return nil }

        let title = String(html[tagClose.upperBound..<endRange.lowerBound])
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if title.count > 60 { return String(title.prefix(57)) + "..." }
        return title.isEmpty ? nil : title
    }

    // MARK: - Port Scanning

    private nonisolated static func scanPorts() -> [LocalPort] {
        let output = shell("/usr/sbin/lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null")
        var seen = Set<String>()
        var results: [LocalPort] = []

        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }

            let processName = String(parts[0])
            guard let pid = Int(parts[1]) else { continue }
            let nameField = String(parts[parts.count - 2])
            guard let colonIdx = nameField.lastIndex(of: ":") else { continue }
            let address = String(nameField[nameField.startIndex..<colonIdx])
            guard let port = Int(nameField[nameField.index(after: colonIdx)...]) else { continue }

            let key = "\(port)-\(pid)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(LocalPort(port: port, processName: processName, pid: pid, address: address))
        }

        return results.sorted { $0.port < $1.port }
    }

    private nonisolated static func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.standardError = nil
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch { return "" }
    }
}
