import SwiftUI
import Logging

@main
struct PublisherExampleSwiftUIApp: App {
    @State private var logger: Logger = {
        var logger = Logger(label: "com.ably.PublisherExampleSwiftUI")
        logger.logLevel = .info
        return logger
    }()
    @State private var s3Helper = try? S3Helper()
    
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationView {
                    CreatePublisherView(logger: logger, s3Helper: s3Helper)
                }
                .tabItem {
                    Label("Publisher", systemImage: "car")
                }
                /*
                This navigationViewStyle(.stack) prevents UINavigationBar-related "Unable to
                simultaneously satisfy constraints" log messages on iPhone simulators with iOS
                < 16 (specifically I saw it with 15.5).  I don’t know what caused this issue
                nor why this fixes it; it's just something I tried after seeing vaguely similar
                complaints on the Web, and it seems to do no harm.
                */
                .navigationViewStyle(.stack)
                NavigationView {
                    SettingsView()
                }
                // Same comment as above
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
    }
}
