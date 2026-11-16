import SwiftUI

@main
struct PhotoTidyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshAccess()
            }
        }
    }
}
