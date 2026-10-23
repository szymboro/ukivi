import SwiftUI

@main
struct KiviApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.red)
                .task { await model.onBecomeActive() }
                .onChange(of: scenePhase) { _, phase in
                    // Re-check every time the user comes back, e.g. from Settings.
                    if phase == .active {
                        Task { await model.onBecomeActive() }
                    }
                }
        }
        .backgroundTask(.appRefresh(FilterUpdateSchedule.taskID)) {
            await FilterUpdateSchedule.runInBackground()
        }
    }
}
