import PropertyModel
import SwiftData
import SwiftUI

/// After: the properties you pick, against the priorities you set in You. Every cell carries an evidence level;
/// until something is measured or noted, it is Unknown, never blank (ADR-0013).
struct CompareView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Property.createdAt, order: .reverse) private var properties: [Property]
    @Query(sort: \UserPreferences.createdAt) private var preferencesRows: [UserPreferences]
    @State private var picked: Set<PersistentIdentifier> = []

    private var priorities: [PriorityDimension] { preferencesRows.first?.priorities ?? [] }
    private var pickedProperties: [Property] { properties.filter { picked.contains($0.persistentModelID) } }

    var body: some View {
        NavigationStack {
            List {
                Section("Your priorities") {
                    if priorities.isEmpty {
                        Text("Choose up to five in You › Priorities.").foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(priorities) { Label($0.displayName, systemImage: $0.systemImage).font(.footnote).padding(8).background(.thinMaterial, in: Capsule()) }
                            }
                        }
                    }
                }
                Section("Pick two or three") {
                    if properties.isEmpty {
                        Text("Add properties first.").foregroundStyle(.secondary)
                    }
                    ForEach(properties) { property in
                        Button {
                            if picked.contains(property.persistentModelID) { picked.remove(property.persistentModelID) }
                            else if picked.count < 3 { picked.insert(property.persistentModelID) }
                        } label: {
                            HStack {
                                Image(systemName: picked.contains(property.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                PropertyRow(property: property)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if pickedProperties.count >= 2 {
                    Section("Side by side") {
                        ForEach(priorities) { dimension in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(dimension.displayName, systemImage: dimension.systemImage).font(.subheadline.weight(.semibold))
                                ForEach(pickedProperties) { property in
                                    HStack {
                                        Text(property.shortAddress).font(.footnote)
                                        Spacer()
                                        Text("Unknown · not measured yet").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Compare")
            .task { _ = try? PropertyStore.preferences(in: context) }
        }
    }
}
