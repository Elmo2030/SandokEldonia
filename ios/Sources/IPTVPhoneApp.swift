import SwiftUI

@main struct IPTVPhoneApp: App {
    @State private var model = PhoneModel()
    var body: some Scene {
        WindowGroup {
            RootTabs()
                .environment(model)
                .task {
                    await model.start()
                    #if DEBUG
                    await PlayerDebug.runIfRequested(model)   // -uiState player-*: opens the player on a generated test stream
                    #endif
                }
        }
    }
}
