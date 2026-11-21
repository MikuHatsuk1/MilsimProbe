import CoreLocation
import UIKit

/// 定位测试：重点看锁屏/切后台后是否还在持续更新，以及最长断档多久。
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authStatus: CLAuthorizationStatus = .notDetermined
    @Published var fullAccuracy = true
    @Published var isRunning = false
    @Published var lastLocation: CLLocation?
    @Published var updateCount = 0
    @Published var backgroundUpdateCount = 0
    @Published var maxGapSeconds: Double = 0
    @Published var speakEnabled = false {
        // 在前台就把音频会话激活，否则到了后台再激活可能失败
        didSet { if speakEnabled { SpeechService.shared.prepareSession() } }
    }

    /// 每次拿到新位置时回调（用于推送到地图）
    var onLocation: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    private var lastTimestamp: Date?
    private var lastSpoken = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authStatus = manager.authorizationStatus
        fullAccuracy = manager.accuracyAuthorization == .fullAccuracy
    }

    var authText: String {
        switch authStatus {
        case .notDetermined: return "未申请"
        case .restricted: return "受限制"
        case .denied: return "已拒绝（去设置里打开）"
        case .authorizedWhenInUse: return "使用期间（后台会受限，建议改成“始终”）"
        case .authorizedAlways: return "始终允许 ✅"
        @unknown default: return "未知"
        }
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestAlwaysAuthorization()
        }
    }

    func start() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isRunning = true
        lastTimestamp = nil
        AppLog.shared.add("GPS", "开始定位")
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRunning = false
        AppLog.shared.add("GPS", "停止定位")
    }

    func resetStats() {
        updateCount = 0
        backgroundUpdateCount = 0
        maxGapSeconds = 0
        lastTimestamp = nil
        AppLog.shared.add("GPS", "统计已清零")
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authStatus = manager.authorizationStatus
        fullAccuracy = manager.accuracyAuthorization == .fullAccuracy
        AppLog.shared.add("GPS", "权限: \(authText)，精确位置: \(fullAccuracy ? "是" : "否")")
        // 第一次拿到“使用期间”后，再申请一次“始终”
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let inBackground = UIApplication.shared.applicationState == .background
        for loc in locations {
            updateCount += 1
            if inBackground { backgroundUpdateCount += 1 }

            var gapText = ""
            if let last = lastTimestamp {
                let gap = loc.timestamp.timeIntervalSince(last)
                if gap > maxGapSeconds { maxGapSeconds = gap }
                gapText = String(format: " 间隔%.1fs", gap)
            }
            lastTimestamp = loc.timestamp
            lastLocation = loc

            if inBackground || updateCount % 10 == 1 {
                AppLog.shared.add(
                    inBackground ? "GPS后台" : "GPS",
                    String(format: "%.6f, %.6f ±%.0fm%@",
                           loc.coordinate.latitude, loc.coordinate.longitude,
                           loc.horizontalAccuracy, gapText))
            }
            onLocation?(loc)
        }

        if speakEnabled, Date().timeIntervalSince(lastSpoken) >= 60 {
            lastSpoken = Date()
            let where_ = inBackground ? "后台" : "前台"
            SpeechService.shared.speak("\(where_)定位正常，第\(updateCount)次更新")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.shared.add("GPS", "错误: \(error.localizedDescription)")
    }
}
