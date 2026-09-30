import SwiftUI

/// Five destinations, ordered by the buyer's timeline (docs/14 §1): Home (before), Properties (the shortlist),
/// Inspect (during, centred so it is one tap from anywhere), Compare (after), You (priorities, settings, data).
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { HomeView() }
            Tab("Properties", systemImage: "list.bullet.rectangle") { PropertiesView() }
            Tab("Inspect", systemImage: "camera.viewfinder") { InspectTabView() }
            Tab("Compare", systemImage: "rectangle.split.2x1") { CompareView() }
            Tab("You", systemImage: "person.crop.circle") { YouView() }
        }
    }
}

#Preview { RootView() }
