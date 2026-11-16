import SwiftUI

@main
struct PhotoTidyApp: App {
    @State private var model: AppModel
    @State private var timeline: TimelineModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        _timeline = State(initialValue: TimelineModel(library: model.library))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .tabItem { Label("정리", systemImage: "sparkles.rectangle.stack") }
                TimelineView()
                    .tabItem { Label("타임라인", systemImage: "map") }
            }
            .environment(model)
            .environment(timeline)
            .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshAccess()
            }
        }
    }
}
