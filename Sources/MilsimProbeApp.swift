import SwiftUI

@main
struct MilsimProbeApp: App {
    @StateObject private var location = LocationService()
    @StateObject private var ble = BLEService()
    @StateObject private var map = WebMapController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(location)
                .environmentObject(ble)
                .environmentObject(map)
                .environmentObject(AppLog.shared)
        }
    }
}
