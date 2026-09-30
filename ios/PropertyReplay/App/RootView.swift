import SwiftUI

/// Three destinations (docs/14 §1). Phase 1 line B replaces the placeholders with the five-screen prototype.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { HomePlaceholder() }
            Tab("Properties", systemImage: "list.bullet.rectangle") { Placeholder(title: "Properties", note: "Shortlist and history.") }
            Tab("Compare", systemImage: "rectangle.split.2x1") { Placeholder(title: "Compare", note: "What you care about, side by side.") }
        }
    }
}

private struct HomePlaceholder: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("See beyond the inspection.").font(.title2.weight(.semibold))
                        Text("Remember what mattered. Replay what you couldn't see.").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Section("Phase 1 · line A") {
                    NavigationLink("Capture validator") { CaptureValidatorView() }
                }
                Section("Phase 1 · line B") {
                    Text("Five-screen prototype: Add → Prep → Inspect → Your inspection → Compare")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Property Replay")
        }
    }
}

private struct Placeholder: View {
    let title: String
    let note: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "hammer", description: Text(note))
                .navigationTitle(title)
        }
    }
}

#Preview { RootView() }
