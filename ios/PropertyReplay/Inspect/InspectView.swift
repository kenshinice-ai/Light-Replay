import PropertyModel
import SwiftUI

/// Inspect mode contract (ADR-0015): three actions, no mode picker. Capture and Note arrive with line B;
/// Measure is the W1 capture validator today.
struct InspectView: View {
    let property: Property

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(property.shortAddress).font(.headline)
                Text("Walk, shoot, talk. Measure where you would sit.").font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            Spacer()
            ContentUnavailableView("Camera view", systemImage: "camera", description: Text("The camera-style Inspect screen is built in Phase 1 line B."))
            Spacer()
            HStack(spacing: 24) {
                action("Capture", "camera.fill") { Placeholder(title: "Capture", note: "One photo with room, heading, time and location. Line B.") }
                action("Note", "mic.fill") { Placeholder(title: "Note", note: "Hold to talk. Transcribed on device, structured, never stored as audio. Line B.") }
                action("Measure", "sun.max.fill") { CaptureValidatorView() }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .navigationTitle("Inspect")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func action<Destination: View>(_ title: String, _ symbol: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.caption)
            }
            .frame(width: 84, height: 64)
        }
        .buttonStyle(.bordered)
    }
}

struct Placeholder: View {
    let title: String
    let note: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text(note))
            .navigationTitle(title)
    }
}
