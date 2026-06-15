import SwiftUI
import UIKit
import Cfip
import CryptoKit

struct ScanResult: Identifiable, Codable {
    let id = UUID()
    let ip: String
    let bandwidth: Int
    let realBandwidth: Int
    let maxSpeed: Int
    let latencyMs: Int
    let dataCenter: String
    let elapsed: Int
    let error: String?
}

struct ContentView: View {
    @State private var ipVersion = "IPv4"
    @State private var useTLS = true
    @State private var dataCenter = ""
    @State private var expectedBW = 50
    @State private var resultCount = 5
    @State private var dcList: [(code: String, label: String)] = []
    @State private var isScanning = false
    @State private var progress = ""
    @State private var results: [ScanResult] = []
    @State private var errorMsg: String?
    @State private var toast: String?
    @State private var showPassword = false
    @State private var password = ""
    @State private var isUnlocked = UserDefaults.standard.bool(forKey: "unlocked")

    var body: some View {
        ZStack {
            Color(hex: "111827").ignoresSafeArea()

            if !isUnlocked && showPassword {
                lockView
            } else {
                mainView
            }
        }
        .onAppear {
            loadDCs()
            if !isUnlocked { showPassword = true }
        }
    }

    var lockView: some View {
        VStack(spacing: 20) {
            Text("CF 三方 IP").font(.title2).fontWeight(.bold).foregroundColor(.white)
            Text("每天限制优选20次，请勿滥用。").font(.caption).foregroundColor(.gray)
            SecureField("密码", text: $password)
                .textFieldStyle(.plain)
                .padding()
                .background(Color(hex: "374151"))
                .cornerRadius(8)
                .foregroundColor(.white)
                .frame(maxWidth: 260)
            Button("解锁") {
                let hash = SHA256.hash(data: Data(password.utf8))
                let hashStr = hash.compactMap { String(format: "%02x", $0) }.joined()
                if hashStr == "ea9243ad55213dc096ebd8b639d583c70a27b627b464fa790c16cc96e9c4b20b" {
                    isUnlocked = true
                    showPassword = false
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

                // 设置卡片
                VStack(alignment: .leading, spacing: 12) {
                    Text("扫描设置").font(.caption).foregroundColor(.gray).textCase(.uppercase)

                    HStack {
                        Text("IP 版本").foregroundColor(Color(hex: "d1d5db")).frame(width: 80, alignment: .leading)
                        Picker("", selection: $ipVersion) {
                            Text("IPv4").tag("IPv4")
                            Text("IPv6").tag("IPv6")
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
                            ForEach(dcList, id: \.code) { dc in
                                Text(dc.label).tag(dc.code)
                            }
                        }
                        Button("刷新") { loadDCs() }
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color(hex: "374151")).cornerRadius(6)
                    }
                    HStack {
                        Text("期望带宽").foregroundColor(Color(hex: "d1d5db")).frame(width: 80, alignment: .leading)
                        TextField("", value: $expectedBW, format: .number)
                            .keyboardType(.numberPad)
                            .padding(8).background(Color(hex: "374151")).cornerRadius(6).foregroundColor(.white)
                        Text("Mbps").foregroundColor(.gray).font(.caption)
                    }
                    HStack {
                        Text("结果数").foregroundColor(Color(hex: "d1d5db")).frame(width: 80, alignment: .leading)
                        Picker("", selection: $resultCount) {
                            Text("1 个").tag(1)
                            Text("5 个").tag(5)
                        }.pickerStyle(.segmented)
                    }

                    Button(action: startScan) {
                        Text(isScanning ? "扫描中..." : "开始扫描")
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 12)
                    .background(isScanning ? Color.gray : Color(hex: "3b82f6"))
                    .foregroundColor(.white).cornerRadius(8)
                    .disabled(isScanning)
                }
                .padding()
                .background(Color(hex: "1f2937"))
                .cornerRadius(12)

                // 进度
                if isScanning {
                    VStack(spacing: 8) {
                        ProgressView().tint(.blue)
                        Text(progress).font(.caption).foregroundColor(.gray)
                    }
                }

                // 错误
                if let err = errorMsg {
                    Text(err).foregroundColor(.red).font(.caption)
                }

                // 结果
                ForEach(Array(results.enumerated()), id: \.element.id) { i, r in
                    resultCard(r, rank: i + 1, expectedBW: expectedBW)
                }
            }
            .padding(.horizontal)
        }
    }

    func resultCard(_ r: ScanResult, rank: Int, expectedBW: Int) -> some View {
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
        .padding()
        .background(Color(hex: "1f2937"))
        .cornerRadius(10)
    }

    func metricRow(_ label: String, _ value: String, muted: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption2).foregroundColor(Color(hex: "6b7280"))
            Text(value).font(.caption).fontWeight(.medium)
                .foregroundColor(muted ? Color(hex: "4b5563") : Color(hex: "d1d5db"))
        }
    }

    func loadDCs() {
        guard let json = BetterGetDataCenters() else { return }
        do {
            if let arr = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] {
                dcList = arr.map { ($0["dc"] as? String ?? "", $0["label"] as? String ?? "") }
            }
        } catch {}
    }

    func startScan() {
        isScanning = true
        errorMsg = nil
        results = []
        progress = "正在初始化..."

        let v4 = ipVersion == "IPv4"
        BetterSetDataCenterFilter(dataCenter)
        DispatchQueue.global().async {
            let json = BetterGetIPs(v4, useTLS, Int64(expectedBW), Int64(resultCount))
            DispatchQueue.main.async {
                isScanning = false
                guard let json = json, let data = json.data(using: .utf8) else { return }
                do {
                    if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let err = obj["error"] as? String, !err.isEmpty {
                            errorMsg = err
                        } else if let arr = obj["results"] as? [[String: Any]] {
                            results = arr.map { d in
                                ScanResult(ip: d["ip"] as? String ?? "",
                                           bandwidth: d["bandwidth"] as? Int ?? 0,
                                           realBandwidth: d["realBandwidth"] as? Int ?? 0,
                                           maxSpeed: d["maxSpeed"] as? Int ?? 0,
                                           latencyMs: d["latencyMs"] as? Int ?? 0,
                                           dataCenter: d["dataCenter"] as? String ?? "",
                                           elapsed: d["elapsed"] as? Int ?? 0,
                                           error: nil)
                            }
                        } else if let ip = obj["ip"] as? String {
                            results = [ScanResult(ip: ip,
                                                  bandwidth: obj["bandwidth"] as? Int ?? 0,
                                                  realBandwidth: obj["realBandwidth"] as? Int ?? 0,
                                                  maxSpeed: obj["maxSpeed"] as? Int ?? 0,
                                                  latencyMs: obj["latencyMs"] as? Int ?? 0,
                                                  dataCenter: obj["dataCenter"] as? String ?? "",
                                                  elapsed: obj["elapsed"] as? Int ?? 0,
                                                  error: nil)]
                        }
                    }
                } catch {
                    errorMsg = "解析失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let r, g, b: Double
        let start = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let scanner = Scanner(string: start)
        var hexNum: UInt64 = 0
        scanner.scanHexInt64(&hexNum)
        r = Double((hexNum >> 16) & 0xFF) / 255
        g = Double((hexNum >> 8) & 0xFF) / 255
        b = Double(hexNum & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
