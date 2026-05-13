import SwiftUI

@main
struct AVPLoggerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .spatialConsoleWindowPresenter()
        }

        SpatialConsoleLoggerWindowScene()
    }
}
