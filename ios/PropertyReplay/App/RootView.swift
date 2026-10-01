import SwiftUI

/// Five destinations, ordered by the buyer's timeline (docs/14 §1): Home (before), Properties (the shortlist),
/// Inspect (during, centred so it is one tap from anywhere), Compare (after), You (priorities, settings, data).
struct RootView: View {
    var body: some View {
        VStack(spacing: 0) {
            if !StoreHealth.shared.isPersistent {
                Text("Storage problem: nothing you add will survive quitting the app. See You › About.")
                    .font(.footnote.weight(.medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(8).background(Color.red)
            }
            tabs
        }
    }

    private var tabs: some View {
        TabView {
            Tab("Home", systemImage: "house") { HomeView() }
            Tab("Properties", systemImage: "list.bullet.rectangle") { PropertiesView() }
            Tab("Inspect", systemImage: "camera.viewfinder") { InspectTabView() }
            Tab("Compare", systemImage: "rectangle.split.2x1") { CompareView() }
            Tab("You", systemImage: "person.crop.circle") { YouView() }
        }
        // iPhone: the tab bar. iPad: a tab bar that can become a sidebar, as the window allows (UI/UX review U07).
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview { RootView() }
