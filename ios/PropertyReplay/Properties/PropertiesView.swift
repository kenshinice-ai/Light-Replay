import PropertyModel
import SwiftData
import SwiftUI

/// Shortlist and history. List or Map of the same properties; the map is the buyer's own pins, nothing else.
struct PropertiesView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case list, map
        var id: String { rawValue }
        var title: String { self == .list ? "List" : "Map" }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Property.createdAt, order: .reverse) private var properties: [Property]
    @State private var mode: Mode = .list
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if properties.isEmpty {
                    ContentUnavailableView {
                        Label("No properties yet", systemImage: "house")
                    } description: {
                        Text("Add the homes you plan to inspect. They stay on this device.")
                    } actions: {
                        Button("Add a property") { showingAdd = true }.buttonStyle(.borderedProminent)
                        #if DEBUG
                        Button("Add sample properties (fictional)") { try? SampleData.insert(into: context) }
                        #endif
                    }
                } else if mode == .list {
                    list
                } else {
                    PropertiesMapView(properties: properties)
                }
            }
            .navigationTitle("Properties")
            .navigationBarTitleDisplayMode(mode == .map ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) { AddPropertyView() }
        }
    }

    private var list: some View {
        List {
            ForEach(PropertyStatus.allCases, id: \.self) { status in
                let group = properties.filter { $0.status == status }
                if !group.isEmpty {
                    Section(status.displayName) {
                        ForEach(group) { property in
                            NavigationLink { PropertyDetailView(property: property) } label: {
                                PropertyRow(property: property, showsInspection: status == .toInspect)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(group[index]) }
                        }
                    }
                }
            }
        }
    }
}
