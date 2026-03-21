import Foundation

struct Tunnel: Identifiable, Codable {
    let id: String
    let name: String
    let localPort: Int
    let remotePort: Int
    let token: String?
    let createdAt: String
    let status: String

    var isActive: Bool { status == "active" }
}

struct TunnelsResponse: Codable {
    let ok: Bool
    let tunnels: [Tunnel]
}

struct StatusResponse: Codable {
    let ok: Bool
    let daemon: Bool?
    let pid: Int?
    let tunnelCount: Int?
    let tailscale: TailscaleInfo?
}

struct TailscaleInfo: Codable {
    let ip: String
    let hostname: String
    let isRunning: Bool
}

struct ExposeResponse: Codable {
    let ok: Bool
    let url: String?
    let error: String?
    let remapped: Bool?
    let tunnel: Tunnel?
}

struct StopResponse: Codable {
    let ok: Bool
    let stopped: String?
    let error: String?
}
