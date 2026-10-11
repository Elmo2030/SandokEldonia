import SwiftUI

@main struct IPTVPhoneApp: App {
    @State private var model = PhoneModel()
    var body: some Scene {
        WindowGroup {
            RootTabs()
                .environment(model)
                .task { await model.start() }
        }
    }
}
