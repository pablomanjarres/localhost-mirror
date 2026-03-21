import Foundation

struct LocalPort: Identifiable {
    let port: Int
    let processName: String
    let pid: Int
    let address: String

    var id: String { "\(port)-\(pid)" }
    var isLocalhostOnly: Bool { address == "127.0.0.1" || address == "localhost" }
}

@MainActor
class PortScanner: ObservableObject {
    @Published var ports: [LocalPort] = []
    @Published var portTitles: [Int: String] = [:]
    private var timer: Timer?
    private var fetchedPorts = Set<Int>()

    private let hiddenPorts: Set<Int> = [19099, 19100]

    private static let nonHTTPPorts: Set<Int> = [
        3306, 5432, 6379, 6380, 27017, 27018, 5984, 8529,
        9200, 9300, 7474, 7687, 26257, 8123,
        5672, 15672, 9092, 2181, 4222, 11211,
        2375, 2376, 2377, 11434, 11435,
        9229, 9230, 5858, 49152,
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
            let results = Self.scanPorts()
            await MainActor.run {
                guard let self = self else { return }
                let activePorts = Set(results.map(\.port))
                for port in self.fetchedPorts where !activePorts.contains(port) {
                    self.portTitles.removeValue(forKey: port)
                    self.fetchedPorts.remove(port)
                }
                self.ports = results.filter { !self.hiddenPorts.contains($0.port) }
                for p in self.ports where !self.fetchedPorts.contains(p.port) {
                    self.fetchTitle(for: p)
                }
            }
        }
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
