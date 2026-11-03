import SwiftUI

@main
struct Shot11App: App {
    @StateObject private var store = Store()
    @StateObject private var camera = CameraService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(camera)
                .onAppear { store.camera = camera }
                .onChange(of: scenePhase) { phase in
                    if phase == .active && store.screen.usesCamera {
                        camera.start()
                    }
                }
        }
    }
}
