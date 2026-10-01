import PropertyModel
import SwiftData
import SwiftUI

/// Before: the next inspection with its way in, and the homes you were last busy with (UI/UX review U08).
/// No feature menu (docs/14 §1).
struct HomeView: View {
    @Query(sort: \Property.createdAt, order: .reverse) private var properties: [Property]
    @State private var showingAdd = false
    @State private var inspecting: Property?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The soonest booked inspection that has not passed.
    private var next: Property? {
        properties.filter { ($0.inspectionAt ?? .distantPast) > Date() }
            .min { ($0.inspectionAt ?? .distantFuture) < ($1.inspectionAt ?? .distantFuture) }
    }

    /// Other homes, most recently recorded or added first. The next inspection is not repeated here.
    private var recent: [Property] {
        properties.filter { $0.persistentModelID != next?.persistentModelID }
            .sorted { Self.lastActivity($0) > Self.lastActivity($1) }
            .prefix(3)
            .map { $0 }
    }

    private static func lastActivity(_ property: Property) -> Date {
        property.allObservations.first?.capturedAt ?? property.createdAt
    }

    var body: some View {
        NavigationStack {
            List {
                if properties.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("See beyond the inspection.").font(.title2.weight(.semibold))
                            Text("Remember what mattered. Replay what you couldn't see.").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        Button("Add a property") { showingAdd = true }.font(.headline)
                    }
                } else {
                    Section("Next inspection") {
                        if let next {
                            NavigationLink { PropertyDetailView(property: next) } label: {
                                PropertyRow(property: next, showsInspection: true)
                            }
                            Button { inspecting = next } label: {
                                Label("Start inspecting", systemImage: "camera.viewfinder").font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 28)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Text("No inspection booked. Add a time to a home and it shows here.").foregroundStyle(.secondary)
                        }
                    }
                    if !recent.isEmpty {
                        Section("Recent") {
                            ForEach(recent) { property in
                                NavigationLink { PropertyDetailView(property: property) } label: {
                                    PropertyRow(property: property, activityText: Self.activityText(property))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Property Replay")
            // A large title does not wrap: on a phone at accessibility sizes it was cut to "Property Re…". Inline, it
            // fits. A wide window has room for it, and with tabs along the top an inline title is not shown at all.
            .navigationBarTitleDisplayMode(typeSize.isAccessibilitySize && sizeClass == .compact ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) { AddPropertyView() }
            .fullScreenCover(item: $inspecting) { property in
                NavigationStack { InspectView(property: property) }
            }
        }
    }

    /// "5 recorded" for a home with records, nothing otherwise.
    private static func activityText(_ property: Property) -> String? {
        let count = property.allObservations.count
        return count == 0 ? nil : "\(count) recorded"
    }
}
