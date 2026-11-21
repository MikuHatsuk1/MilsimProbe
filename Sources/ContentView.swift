import SwiftUI

enum Panel: String, CaseIterable, Identifiable {
    case gps = "定位"
    case ble = "蓝牙"
    case log = "日志"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var map: WebMapController
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel: Panel = .gps

    var body: some View {
        VStack(spacing: 0) {
            MapWebView(controller: map)
                .frame(maxHeight: .infinity)
            Picker("面板", selection: $panel) {
                ForEach(Panel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)
            Group {
                switch panel {
                case .gps: GPSPanel()
                case .ble: BLEPanel()
                case .log: LogPanel()
                }
            }
            .frame(height: 300)
        }
        .onAppear {
            let mapController = map
            location.onLocation = { loc in mapController.push(loc) }
            AppLog.shared.add("APP", "启动")
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: AppLog.shared.add("APP", "回到前台")
            case .inactive: AppLog.shared.add("APP", "非活跃")
            case .background: AppLog.shared.add("APP", "进入后台")
            @unknown default: break
            }
        }
    }
}

// MARK: - 定位面板

struct GPSPanel: View {
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var map: WebMapController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                row("权限", location.authText)
                row("精确位置", location.fullAccuracy ? "是" : "否（去设置里打开“精确位置”）")
                if let loc = location.lastLocation {
                    row("坐标", String(format: "%.6f, %.6f", loc.coordinate.latitude, loc.coordinate.longitude))
                    row("精度", String(format: "±%.0f 米", loc.horizontalAccuracy))
                    row("速度", loc.speed >= 0 ? String(format: "%.1f 米/秒", loc.speed) : "-")
                }
                row("更新次数", "\(location.updateCount)（后台 \(location.backgroundUpdateCount)）")
                row("最长断档", String(format: "%.1f 秒", location.maxGapSeconds))

                HStack {
                    Button("申请权限") { location.requestPermission() }
                    Button(location.isRunning ? "停止定位" : "开始定位") {
                        location.isRunning ? location.stop() : location.start()
                    }
                    Button("清零统计") { location.resetStats() }
                }
                .buttonStyle(.bordered)

                HStack {
                    Button("回到我的位置") { map.recenter() }
                    Button("清除轨迹") { map.clearTrack() }
                    Button("测试语音") { SpeechService.shared.speak("语音测试，一二三") }
                }
                .buttonStyle(.bordered)

                Toggle("每分钟语音播报（测锁屏能否出声）", isOn: $location.speakEnabled)
            }
            .font(.footnote)
            .padding(.horizontal)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            Text(v)
        }
    }
}

// MARK: - 蓝牙面板

struct BLEPanel: View {
    @EnvironmentObject var ble: BLEService
    @State private var hexInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("状态: \(ble.stateText)").font(.footnote)
                Spacer()
                if !ble.isActive {
                    Button("启动蓝牙") { ble.activate() }.buttonStyle(.bordered)
                } else {
                    Button(ble.scanning ? "停止扫描" : "扫描") { ble.toggleScan() }
                        .buttonStyle(.bordered)
                }
            }
            Toggle("只显示 FFF0 设备", isOn: $ble.onlyFFF0).font(.footnote)

            if let name = ble.connectedName {
                HStack {
                    Text("已连接: \(name)").font(.footnote).bold()
                    Spacer()
                    Button("断开") { ble.disconnect() }.buttonStyle(.bordered)
                }
                if !ble.writableChars.isEmpty {
                    HStack {
                        TextField("十六进制，如 A1 02 FF", text: $hexInput)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                        Button("写入") { ble.writeHex(hexInput) }.buttonStyle(.bordered)
                    }
                    .font(.footnote)
                }
            }

            List(ble.sortedDevices) { d in
                Button {
                    ble.connect(d)
                } label: {
                    HStack {
                        Text(d.name)
                        if d.hasFFF0 {
                            Text("FFF0").font(.caption2).padding(2)
                                .background(Color.orange.opacity(0.3)).cornerRadius(3)
                        }
                        Spacer()
                        Text("\(d.rssi) dBm").foregroundColor(.secondary)
                    }
                    .font(.footnote)
                }
            }
            .listStyle(.plain)
        }
        .padding(.horizontal)
    }
}

// MARK: - 日志面板

struct LogPanel: View {
    @EnvironmentObject var log: AppLog

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(log.lines.count) 行").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("清空") { log.clear() }
                Button("导出") { log.share() }
            }
            .padding(.horizontal)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.lines.enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.system(size: 10, design: .monospaced))
                                .id(item.offset)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: log.lines.count) { count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
    }
}
