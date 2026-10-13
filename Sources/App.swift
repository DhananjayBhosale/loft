import SwiftUI

@main
struct LoftApp: App {
    @StateObject private var model = AppModel()
    init() { Typo.register() }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
