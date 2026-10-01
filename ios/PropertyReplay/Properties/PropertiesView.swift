import MapKit
import PropertyModel
import SwiftData
import SwiftUI

/// Shortlist and history. List or Map are two views of the same homes: one search, one status filter and one selected
/// home drive both (UI/UX review U09). On a wide window the chosen home shows beside them; on a phone it is pushed
/// (review U07). The map is the buyer's own pins, nothing else.
struct PropertiesView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case list, map
        var id: String { rawValue }
        var title: String { self == .list ? "List" : "Map" }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Property.createdAt, order: .reverse) private var properties: [Property]
    @State private var mode: Mode = .list
    @State private var selectedID: PersistentIdentifier?
    /// Which column a narrow window shows. Set to `.detail` to open the selected home; the system sets it back.
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var search = ""
    @State private var statusFilter: PropertyStatus?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showingAdd = false
    @State private var deleteError: String?

    /// The homes that pass the search and the status filter; List and Map both show exactly these.
    private var visible: [Property] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return properties.filter { property in
            (statusFilter == nil || property.status == statusFilter)
                && (needle.isEmpty || property.address.lowercased().contains(needle) || (property.suburb ?? "").lowercased().contains(needle))
        }
    }

    private var selected: Property? { properties.first { $0.persistentModelID == selectedID } }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            sidebar
                .navigationTitle("Properties")
                .navigationBarTitleDisplayMode(mode == .map ? .inline : .large)
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 520)
                .toolbar { toolbar }
        } detail: {
            NavigationStack {
                if let selected {
                    PropertyDetailView(property: selected).id(selected.persistentModelID)
                } else {
                    ContentUnavailableView("Choose a home", systemImage: "house",
                                           description: Text("Its photos, notes and light scans show here."))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingAdd) { AddPropertyView() }
        .alert("Couldn't remove it", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(deleteError ?? "") }
    }

    @ViewBuilder
    private var sidebar: some View {
        if properties.isEmpty {
            ContentUnavailableView {
                Label("No properties yet", systemImage: "house")
            } description: {
                Text(StoreHealth.shared.mode == .iCloud
                     ? "Add the homes you plan to inspect. If you already use Property Replay on another device, your homes arrive here once iCloud catches up; that can take a few minutes."
                     : "Add the homes you plan to inspect. They stay on this device.")
            } actions: {
                Button("Add a property") { showingAdd = true }.buttonStyle(.borderedProminent)
                #if DEBUG
                Button("Add sample properties (fictional)") { try? SampleData.insert(into: context) }
                #endif
            }
        } else {
            Group {
                if mode == .list {
                    list
                } else {
                    PropertiesMapView(properties: visible, total: properties.count, selectedID: $selectedID, position: $mapPosition,
                                      showsCard: sizeClass == .compact, open: open, showList: { mode = .list })
                }
            }
            // List / Map sits in the content, not in the navigation bar: while a search is active iOS replaces the
            // bar with the search field, and the buyer must still be able to see the matches on the map.
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .searchable(text: $search, prompt: "Address or suburb")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Add", systemImage: "plus") { showingAdd = true }
                .keyboardShortcut("n", modifiers: .command)
        }
        ToolbarItem(placement: .secondaryAction) {
            Picker("Show", selection: $statusFilter) {
                Text("All statuses").tag(PropertyStatus?.none)
                ForEach(PropertyStatus.allCases, id: \.self) { Text($0.displayName).tag(PropertyStatus?.some($0)) }
            }
        }
    }

    private var list: some View {
        List {
            if visible.isEmpty {
                ContentUnavailableView.search
            }
            ForEach(PropertyStatus.allCases, id: \.self) { status in
                let group = visible.filter { $0.status == status }
                if !group.isEmpty {
                    Section(status.displayName) {
                        ForEach(group) { property in
                            Button { open(property.persistentModelID) } label: {
                                HStack {
                                    PropertyRow(property: property, showsInspection: status == .toInspect)
                                    if sizeClass == .compact {
                                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(sizeClass != .compact && selectedID == property.persistentModelID
                                               ? Color.accentColor.opacity(0.14) : nil)
                            .accessibilityAddTraits(selectedID == property.persistentModelID ? .isSelected : [])
                            .deleteWithConfirmation("Remove \(property.shortAddress) and everything recorded for it?", actionLabel: "Remove") {
                                remove([property])
                            }
                        }
                    }
                }
            }
            if statusFilter != nil || !search.isEmpty {
                Section {
                    Text("Showing \(visible.count) of \(properties.count).").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Selects a home and, in a narrow window, shows it.
    private func open(_ id: PersistentIdentifier) {
        selectedID = id
        compactColumn = .detail
    }

    private func remove(_ doomed: [Property]) {
        for property in doomed {
            if selectedID == property.persistentModelID { selectedID = nil }
            do { try PropertyStore.delete(property, in: context) } catch {
                deleteError = "\(error.localizedDescription) It is hidden now and will be removed the next time the library saves."
            }
        }
    }
}
