import SwiftUI

enum CommonPorts {
    static let known: [Int: String] = [
        80: "HTTP", 443: "HTTPS", 8080: "HTTP Alt", 8443: "HTTPS Alt",
        1234: "Parcel", 1337: "Strapi", 2368: "Ghost",
        3000: "React / Next.js", 3001: "React / Next.js", 3002: "React / Next.js",
        3333: "Adonis / Node", 4000: "Remix / GraphQL", 4173: "Vite Preview",
        4200: "Angular", 4321: "Astro", 5173: "Vite", 5174: "Vite", 5175: "Vite",
        5500: "Live Server", 5555: "Prisma Studio", 6006: "Storybook", 6007: "Storybook",
        8081: "Metro Bundler", 8082: "Metro Bundler", 9000: "Webpack / PHP",
        9229: "Node Debugger", 9230: "Node Debugger", 24678: "Vite HMR",
        5000: "Flask / Python", 7860: "Gradio", 7861: "Gradio",
        8000: "Django / Uvicorn", 8001: "Django / Uvicorn",
        8501: "Streamlit", 8502: "Streamlit", 8888: "Jupyter", 8889: "Jupyter",
        1323: "Echo (Go)", 2345: "Delve (Go)", 3100: "Grafana Loki",
        4567: "Sinatra", 9003: "Xdebug",
        5858: "Electron Debug", 19000: "Expo", 19001: "Expo",
        19002: "Expo DevTools", 19006: "Expo Web",
        3306: "MySQL", 5432: "PostgreSQL", 5984: "CouchDB",
        6379: "Redis", 6380: "Redis", 7474: "Neo4j", 7687: "Neo4j Bolt",
        8123: "ClickHouse", 8529: "ArangoDB", 9200: "Elasticsearch",
        9300: "Elasticsearch", 26257: "CockroachDB", 27017: "MongoDB", 27018: "MongoDB",
        2181: "Zookeeper", 4222: "NATS", 5672: "RabbitMQ", 9092: "Kafka",
        11211: "Memcached", 15672: "RabbitMQ Mgmt",
        2375: "Docker API", 2376: "Docker TLS", 2377: "Docker Swarm",
        4317: "OpenTelemetry", 4318: "OpenTelemetry", 8200: "Vault",
        8500: "Consul", 9090: "Prometheus", 9411: "Zipkin", 16686: "Jaeger",
        8188: "ComfyUI", 11434: "Ollama", 11435: "Ollama",
        4566: "LocalStack", 5001: "Firebase Func", 8085: "Firebase Emu",
        9099: "Firebase Emu", 9443: "Keycloak", 54321: "Supabase", 54322: "Supabase DB",
    ]

    private static let processPatterns: [(pattern: String, label: String, color: Color)] = [
        ("node", "Node.js", .green), ("pnpm", "Node.js", .green), ("npm", "Node.js", .green),
        ("next", "Next.js", .green), ("nuxt", "Nuxt", .green),
        ("bun", "Bun", .green), ("deno", "Deno", .green),
        ("com.docke", "Docker", .blue), ("docker", "Docker", .blue), ("vpnkit", "Docker", .blue),
        ("python", "Python", .yellow), ("ruby", "Ruby", .red), ("java", "Java", .orange),
        ("go", "Go", .cyan), ("nginx", "Nginx", .orange), ("apache", "Apache", .orange),
        ("caddy", "Caddy", .orange), ("postgres", "PostgreSQL", .green),
        ("mysqld", "MySQL", .green), ("redis", "Redis", .green), ("mongo", "MongoDB", .green),
        ("ollama", "Ollama", .pink), ("stable", "Stable Diffusion", .pink),
        ("electron", "Electron", .cyan), ("swift", "Swift", .orange),
        ("cargo", "Rust", .orange), ("rustc", "Rust", .orange), ("php", "PHP", .purple),
    ]

    static func label(for port: Int, processName: String = "") -> String? {
        if let known = known[port] { return known }
        return matchProcess(processName)?.label
    }

    static func color(for port: Int, processName: String = "") -> Color {
        if let match = matchProcess(processName) { return match.color }
        if [3306, 5432, 6379, 6380, 27017, 27018, 5984, 8529, 9200, 9300, 7474, 7687, 26257, 8123].contains(port) { return .green }
        if [5672, 15672, 9092, 2181, 4222, 11211, 2375, 2376, 2377, 9090, 9411, 16686, 8200, 8500, 4317, 4318].contains(port) { return .mint }
        if [11434, 11435, 8188, 7860, 7861].contains(port) { return .pink }
        if (3000...3999).contains(port) { return .blue }
        if (4000...4999).contains(port) { return .cyan }
        if (5173...5175).contains(port) { return .purple }
        if (8000...8999).contains(port) { return .orange }
        if (19000...19006).contains(port) { return .indigo }
        return .secondary
    }

    private static func matchProcess(_ processName: String) -> (label: String, color: Color)? {
        let name = processName.lowercased()
        guard !name.isEmpty else { return nil }
        for entry in processPatterns {
            if name.contains(entry.pattern) {
                if entry.pattern == "java" && name.contains("javascript") { continue }
                return (entry.label, entry.color)
            }
        }
        return nil
    }
}
