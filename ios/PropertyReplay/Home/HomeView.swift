import PropertyModel
import SwiftData
import SwiftUI

/// Before: what is coming up, what was recent, add a property. No feature menu (docs/14 §1).
struct HomeView: View {
    @Query(sort: \Property.createdAt, order: .reverse) private var properties: [Property]
    @State private var showingAdd = false

    private var nextInspection: Property? {
        properties.filter { ($0.inspectionAt ?? .distantPast) > Date() }.min { ($0.inspectionAt ?? .distantFuture) < ($1.inspectionAt ?? .distantFuture) }
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
                        if let next = nextInspection {
                            NavigationLink { PropertyDetailView(property: next) } label: {
                                PropertyRow(property: next, showsInspection: true)
                            }
                        } else {
                            Text("No inspection booked. Add a time on a property to get a Prep here.").foregroundStyle(.secondary)
                        }
                    }
                    Section("Recent") {
                        ForEach(properties.prefix(3)) { property in
                            NavigationLink { PropertyDetailView(property: property) } label: { PropertyRow(property: property) }
                        }
                    }
                }
            }
            .navigationTitle("Property Replay")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) { AddPropertyView() }
        }
    }
}
