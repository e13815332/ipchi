import SwiftUI
import CryptoKit

// MARK: - Models
struct DCEntry: Codable { let dc: String; let label: String }

struct PoolIP: Codable { let ip: String; let port: Int; let tls: Bool; let dc: String }

struct ScanResult: Identifiable, Codable {
    var id = UUID()
    let ip: String; let bandwidth: Int; let realBandwidth: Int
    let maxSpeed: Int; let latencyMs: Int; let dataCenter: String
    let elapsed: Int; let error: String?
}

// MARK: - API
struct API {
    static let base = "https://cfip.989920.xyz"
    static let key = "cfip-2026"

    static func fetchDCs() async -> [DCEntry] {
        guard let url = URL(string: "\(base)/api/dcs") else { return [] }
        var req = URLRequest(url: url); req.setValue(key, forHTTPHeaderField: "X-API-Key")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return (try? JSONDecoder().decode([DCEntry].self, from: data)) ?? []
        } catch { return [] }
    }

    static func fetchPool(v4: Bool, useTLS: Bool, dc: String, count: Int) async -> [PoolIP] {
        guard let url = URL(string: "\(base)/api/pool") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "X-API-Key")
        let body: [String: Any] = ["v4": v4, "useTls": useTLS, "dc": dc, "count": count]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return (try? JSONDecoder().decode([PoolIP].self, from: data)) ?? []
        } catch { return [] }
    }

    // Speed test using CF speed test endpoint
    static func testSpeed(ip: String, port: Int, tls: Bool, timeout: TimeInterval) async -> (speed: Double, latency: Double) {
        let scheme = tls ? "https" : "http"
        let urlStr = "\(scheme)://\(ip):\(port)/__down?bytes=1000000"
        guard let url = URL(string: urlStr) else { return (0, 0) }
        let start = Date()
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0.1 {
                let speed = Double(data.count) * 8 / elapsed / 1_000_000
                return (speed, elapsed * 1000)
            }
            return (0, elapsed * 1000)
        } catch {
            return (0, 0)
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @State private var ipVersion = "IPv4"
    @State private var useTLS = true
    @State private var dataCenter = ""
    @State private var expectedBW = 50
    @State private var resultCount = 5
    @State private var dcList: [DCEntry] = []
    @State private var isScanning = false
    @State private var progress = ""
    @State private var results: [ScanResult] = []
    @State private var errorMsg: String?
    @State private var showPassword = false
    @State private var password = ""
    @State private var isUnlocked = UserDefaults.standard.bool(forKey: "unlocked")

    var body: some View {
        ZStack {
            Color(hex: "111827").ignoresSafeArea()
            if !isUnlocked && showPassword { lockView } else { mainView }
        }
        .onAppear {
            Task { dcList = await API.fetchDCs() }
            if !isUnlocked { showPassword = true }
        }
    }

    var lockView: some View {
        VStack(spacing: 20) {
            Text("CF 三方 IP").font(.title2).fontWeight(.bold).foregroundColor(.white)
            Text("每天限制优选20次，请勿滥用。").font(.caption).foregroundColor(.gray)
            SecureField("密码", text: $password)
                .textFieldStyle(.plain).padding()
                .background(Color(hex: "374151")).cornerRadius(8)
                .foregroundColor(.white).frame(maxWidth: 260)
            Button("解锁") {
                let hash = SHA256.hash(data: Data(password.utf8))
                let hashStr = hash.compactMap { String(format: "%02x", $0) }.joined()
                if hashStr == "ea9243ad55213dc096ebd8b639d583c70a27b627b464fa790c16cc96e9c4b20b" {
                    isUnlocked = true; showPassword = false
                    UserDefaults.standard.set(true, forKey: "unlocked")
                }
            }
            .padding(.horizontal, 40).padding(.vertical, 12)
            .background(Color(hex: "3b82f6")).foregroundColor(.white).cornerRadius(8)
        }
    }

    var mainView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("CF 三方 IP").font(.title2).fontWeight(.bold).foregroundColor(.white).padding(.top)
                settingsCard
                if isScanning { progressView }
                if let err = errorMsg { Text(err).foregroundColor(.red).font(.caption) }
                ForEach(Array(results.enumerated()), id: \.element.id) { i, r in
                    resultCard(r, rank: i + 1)
                }
            }.padding(.horizontal)
        }
    }

    var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("扫描设置").font(.caption).foregroundColor(.gray).textCase(.uppercase)
            HStack {
                Text("IP 版本").foregroundColor(Color(hex: "d1d5db")).frame(width: 80, alignment: .leading)
                Picker("", selection: $ipVersion) {
                    Text("IPv4").tag("IPv4"); Text("IPv6").tag("IPv6")
                }.pickerStyle(.segmented)
            }
            HStack {
                Text("TLS").foregroundColor(Color(hex: "d1d5db")).frame(width: 80, alignment: .leading)
                Toggle("", isOn: $useTLS).labelsHidden()
            }
            HStack {
                Text("数据中心").foregroundColor(Color(hex: "d1d5db")).frame(width: 80, alignment: .leading)
                Picker("", selection: $dataCenter) {
                    Text("全部").tag("")
                    ForEach(dcList, id: \.dc) { dc in Text(dc.label).tag(dc.dc) }
                }
                Button("刷新") { Task { dcList = await API.fetchDCs() } }
                    .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: "374151")).cornerRadius(6)
            }
            HStack {
                Text("期望带宽").foregroundColor(Color(hex: "d1d5db")).frame(width: 80, alignment: .leading)
                TextField("", value: $expectedBW, format: .number)
                    .keyboardType(.numberPad).padding(8)
                    .background(Color(hex: "374151")).cornerRadius(6).foregroundColor(.white)
                Text("Mbps").foregroundColor(.gray).font(.caption)
            }
            HStack {
                Text("结果数").foregroundColor(Color(hex: "d1d5db")).frame(width: 80, alignment: .leading)
                Picker("", selection: $resultCount) {
                    Text("1 个").tag(1); Text("5 个").tag(5)
                }.pickerStyle(.segmented)
            }
            Button(action: { Task { await startScan() } }) {
                Text(isScanning ? "扫描中..." : "开始扫描")
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
            .background(isScanning ? Color.gray : Color(hex: "3b82f6"))
            .foregroundColor(.white).cornerRadius(8).disabled(isScanning)
        }
        .padding().background(Color(hex: "1f2937")).cornerRadius(12)
    }

    var progressView: some View {
        VStack(spacing: 8) {
            ProgressView().tint(.blue)
            Text(progress).font(.caption).foregroundColor(.gray)
        }
    }

    func resultCard(_ r: ScanResult, rank: Int) -> some View {
        let ipParts = r.ip.components(separatedBy: ":")
        let ipOnly = ipParts.first ?? r.ip
        let portOnly = ipParts.count > 1 ? ipParts[1] : ""
        let below = r.realBandwidth < expectedBW

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(rank)").foregroundColor(Color(hex: "3b82f6")).fontWeight(.bold)
                Button(ipOnly) { UIPasteboard.general.string = ipOnly }
                    .foregroundColor(Color(hex: "3b82f6")).fontWeight(.bold)
                Text(":\(portOnly)").foregroundColor(Color(hex: "e36c2c")).fontWeight(.bold)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                metricRow("期望带宽", "\(r.bandwidth) Mbps", muted: false)
                metricRow("实测带宽", "\(r.realBandwidth) Mbps", muted: below)
                metricRow("峰值速度", "\(r.maxSpeed) kB/s", muted: false)
                metricRow("往返延迟", "\(r.latencyMs) ms", muted: false)
                metricRow("数据中心", r.dataCenter, muted: false)
                metricRow("总用时", "\(r.elapsed) 秒", muted: false)
            }
        }
        .padding().background(Color(hex: "1f2937")).cornerRadius(10)
    }

    func metricRow(_ label: String, _ value: String, muted: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption2).foregroundColor(Color(hex: "6b7280"))
            Text(value).font(.caption).fontWeight(.medium)
                .foregroundColor(muted ? Color(hex: "4b5563") : Color(hex: "d1d5db"))
        }
    }

    func loadDCs() {
        Task { dcList = await API.fetchDCs() }
    }

    func startScan() async {
        isScanning = true; errorMsg = nil; results = []
        progress = "正在获取 IP 池..."
        let v4 = ipVersion == "IPv4"
        let pool = await API.fetchPool(v4: v4, useTLS: useTLS, dc: dataCenter, count: 50)

        progress = "正在测试 \(pool.count) 个节点..."
        let startTime = Date()
        var scanned: [ScanResult] = []
        for ip in pool {
            let (speed, latency) = await API.testSpeed(ip: ip.ip, port: ip.port, tls: ip.tls, timeout: 5)
            if speed > 0 {
                scanned.append(ScanResult(
                    ip: "\(ip.ip):\(ip.port)",
                    bandwidth: expectedBW,
                    realBandwidth: Int(speed),
                    maxSpeed: Int(speed * 128),
                    latencyMs: Int(latency),
                    dataCenter: ip.dc,
                    elapsed: Int(Date().timeIntervalSince(startTime)),
                    error: nil))
            }
        }
        scanned.sort { $0.realBandwidth > $1.realBandwidth }
        results = Array(scanned.prefix(resultCount))
        let elapsed = Int(Date().timeIntervalSince(startTime))
        progress = "扫描完成，用时 \(elapsed) 秒，共 \(results.count) 个结果"
        isScanning = false
    }
}

// MARK: - Color Hex
extension Color {
    init(hex: String) {
        let start = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let scanner = Scanner(string: start)
        var hexNum: UInt64 = 0
        scanner.scanHexInt64(&hexNum)
        let r = Double((hexNum >> 16) & 0xFF) / 255
        let g = Double((hexNum >> 8) & 0xFF) / 255
        let b = Double(hexNum & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
