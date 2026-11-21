import CoreBluetooth
import Foundation

struct BLEDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var hasFFF0: Bool
}

/// 蓝牙测试：扫描、连接、列出服务和特征、订阅通知、显示收到的原始数据。
/// 安卓版用的是 FFF0 服务（FFF1~FFF6 特征），常见的蓝牙串口模块就是这个布局。
final class BLEService: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let targetService = CBUUID(string: "FFF0")

    @Published var stateText = "未启动"
    @Published var isActive = false
    @Published var scanning = false
    @Published var onlyFFF0 = false
    @Published var devices: [UUID: BLEDevice] = [:]
    @Published var connectedName: String?
    @Published var writableChars: [String] = []

    private var central: CBCentralManager?
    private var connected: CBPeripheral?
    private var writeTargets: [CBCharacteristic] = []

    var sortedDevices: [BLEDevice] {
        devices.values
            .filter { !onlyFFF0 || $0.hasFFF0 }
            .sorted { $0.rssi > $1.rssi }
    }

    /// 首次点“启动蓝牙”才创建，避免一打开 App 就弹权限框。
    func activate() {
        guard central == nil else { return }
        central = CBCentralManager(
            delegate: self, queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "milsim-probe-central"])
        isActive = true
    }

    func toggleScan() {
        guard let central = central else { return }
        if scanning {
            central.stopScan()
            scanning = false
            AppLog.shared.add("BLE", "停止扫描")
        } else {
            guard central.state == .poweredOn else {
                AppLog.shared.add("BLE", "蓝牙未就绪: \(stateText)")
                return
            }
            // 注意：iOS 后台扫描必须指定服务 UUID；前台扫全部方便排查
            central.scanForPeripherals(
                withServices: onlyFFF0 ? [Self.targetService] : nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            scanning = true
            AppLog.shared.add("BLE", "开始扫描\(onlyFFF0 ? "（仅 FFF0）" : "（全部设备）")")
        }
    }

    func connect(_ device: BLEDevice) {
        guard let central = central else { return }
        if let old = connected { central.cancelPeripheralConnection(old) }
        AppLog.shared.add("BLE", "连接 \(device.name) …")
        connected = device.peripheral
        device.peripheral.delegate = self
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let central = central, let p = connected else { return }
        central.cancelPeripheralConnection(p)
    }

    /// 向第一个可写特征写入十六进制数据，例如 "A1 02 FF"
    func writeHex(_ text: String) {
        guard let p = connected, let ch = writeTargets.first else {
            AppLog.shared.add("BLE", "没有可写的特征")
            return
        }
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else {
            AppLog.shared.add("BLE", "十六进制格式不对")
            return
        }
        var bytes = [UInt8]()
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let b = UInt8(cleaned[idx..<next], radix: 16) else {
                AppLog.shared.add("BLE", "十六进制格式不对")
                return
            }
            bytes.append(b)
            idx = next
        }
        let type: CBCharacteristicWriteType =
            ch.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(Data(bytes), for: ch, type: type)
        AppLog.shared.add("BLE", "写入 \(ch.uuid.uuidString): \(Self.hex(Data(bytes)))")
    }

    // MARK: - Helpers

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func propsText(_ p: CBCharacteristicProperties) -> String {
        var s: [String] = []
        if p.contains(.read) { s.append("读") }
        if p.contains(.write) { s.append("写") }
        if p.contains(.writeWithoutResponse) { s.append("无响应写") }
        if p.contains(.notify) { s.append("通知") }
        if p.contains(.indicate) { s.append("指示") }
        return s.joined(separator: "/")
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: stateText = "已开启 ✅"
        case .poweredOff: stateText = "蓝牙已关闭"
        case .unauthorized: stateText = "没有蓝牙权限（去设置里打开）"
        case .unsupported: stateText = "设备不支持"
        case .resetting: stateText = "重置中"
        default: stateText = "未知"
        }
        AppLog.shared.add("BLE", "状态: \(stateText)")
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        AppLog.shared.add("BLE", "系统恢复了蓝牙状态（App 曾被后台杀掉）")
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name ?? "(无名称)"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let hasFFF0 = services.contains(Self.targetService)
        let isNew = devices[peripheral.identifier] == nil
        devices[peripheral.identifier] = BLEDevice(
            id: peripheral.identifier, peripheral: peripheral,
            name: name, rssi: RSSI.intValue,
            hasFFF0: hasFFF0 || (devices[peripheral.identifier]?.hasFFF0 ?? false))
        if isNew {
            AppLog.shared.add("BLE", "发现 \(name) RSSI \(RSSI)\(hasFFF0 ? " [FFF0]" : "")")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedName = peripheral.name ?? "(无名称)"
        AppLog.shared.add("BLE", "已连接 \(connectedName ?? "")，查找服务…")
        writeTargets = []
        writableChars = []
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        AppLog.shared.add("BLE", "连接失败: \(error?.localizedDescription ?? "未知")")
        connected = nil
        connectedName = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let reason = error?.localizedDescription ?? "正常断开"
        AppLog.shared.add("BLE", "已断开: \(reason)")
        connected = nil
        connectedName = nil
        writeTargets = []
        writableChars = []
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            AppLog.shared.add("BLE", "查找服务出错: \(error.localizedDescription)")
            return
        }
        for s in peripheral.services ?? [] {
            AppLog.shared.add("BLE", "服务 \(s.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            AppLog.shared.add("BLE", "查找特征出错: \(error.localizedDescription)")
            return
        }
        for c in service.characteristics ?? [] {
            AppLog.shared.add("BLE", "  特征 \(c.uuid.uuidString) [\(Self.propsText(c.properties))]")
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: c)
            }
            if c.properties.contains(.read) {
                peripheral.readValue(for: c)
            }
            if c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) {
                writeTargets.append(c)
                writableChars.append(c.uuid.uuidString)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            AppLog.shared.add("BLE", "订阅 \(characteristic.uuid.uuidString) 失败: \(error.localizedDescription)")
        } else {
            AppLog.shared.add("BLE", "已订阅 \(characteristic.uuid.uuidString)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        var text = "收到 \(characteristic.uuid.uuidString): \(Self.hex(data))"
        if let s = String(data: data, encoding: .utf8),
           !s.isEmpty, s.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0 == "\n" || $0 == "\r" }) {
            text += "  \"\(s)\""
        }
        AppLog.shared.add("BLE", text)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            AppLog.shared.add("BLE", "写入失败: \(error.localizedDescription)")
        }
    }
}
