import PropertyModel
import SwiftData
import SwiftUI

/// After: the homes you pick, against the priorities you set in You (UI/UX review U14). Rows are your priorities,
/// columns are the homes, and the home names stay pinned so nobody has to remember which column is which. A cell
/// only ever reports what you recorded there; it never scores (ADR-0005) and every kind of "nothing" is named.
struct CompareView: View {
    static let limit = 3

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Property.createdAt, order: .reverse) private var properties: [Property]
    @Query(sort: \UserPreferences.createdAt) private var preferencesRows: [UserPreferences]
    /// In the order they were picked, which is the column order.
    @State private var picked: [PersistentIdentifier] = []

    private var priorities: [PriorityDimension] { preferencesRows.first?.priorities ?? [] }
    private var pickedProperties: [Property] {
        picked.compactMap { id in properties.first { $0.persistentModelID == id } }
    }
    /// Columns need room: at accessibility sizes, or three homes on a narrow phone with large text, cells stack instead.
    private var stacked: Bool {
        typeSize.isAccessibilitySize || (sizeClass == .compact && pickedProperties.count == 3 && typeSize > .xLarge)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                    chooser
                    if priorities.isEmpty {
                        noPriorities
                    } else if pickedProperties.count >= 2 {
                        table
                    } else if !properties.isEmpty {
                        Text("Pick two or three homes to see them side by side.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))   // boxes read as boxes, like the grouped lists elsewhere
            .navigationTitle("Compare")
            .task { _ = try? PropertyStore.preferences(in: context) }
            .onChange(of: properties.map(\.persistentModelID)) { _, ids in picked.removeAll { !ids.contains($0) } }
        }
    }

    // MARK: - Choosing

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Homes").font(.title3.weight(.semibold))
            if properties.isEmpty {
                Text("Add properties first, in the Properties tab.").foregroundStyle(.secondary)
            } else {
                Text(picked.count >= Self.limit ? "Three chosen. Remove one to add another." : "Choose up to three.")
                    .font(.footnote).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(properties) { property in
                        let isPicked = picked.contains(property.persistentModelID)
                        let full = picked.count >= Self.limit && !isPicked
                        Button {
                            if isPicked { picked.removeAll { $0 == property.persistentModelID } } else { picked.append(property.persistentModelID) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isPicked ? Color.accentColor : Color.secondary)
                                PropertyRow(property: property)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(full)
                        .opacity(full ? 0.45 : 1)
                        .accessibilityAddTraits(isPicked ? .isSelected : [])
                        .accessibilityHint(full ? "Three homes are already chosen" : "")
                        if property.persistentModelID != properties.last?.persistentModelID { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var noPriorities: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compare shows the things you said you care about. You haven't chosen any yet.")
                .foregroundStyle(.secondary)
            if let preferences = preferencesRows.first {
                NavigationLink { PrioritiesView(preferences: preferences) } label: {
                    Label("Choose what you care about", systemImage: "slider.horizontal.3").font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Table

    private var table: some View {
        Section {
            ForEach(priorities) { dimension in
                VStack(alignment: .leading, spacing: 8) {
                    Label(dimension.displayName, systemImage: dimension.systemImage)
                        .font(.subheadline.weight(.semibold))
                    if stacked {
                        ForEach(pickedProperties) { property in cell(dimension, property, named: true) }
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(pickedProperties) { property in
                                cell(dimension, property, named: false).frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                }
            }
            Text("Each box is what you recorded at that home. Nothing here is a score.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            if !stacked { columnHeader }
        }
    }

    /// The homes' names, pinned while the rows scroll under them.
    private var columnHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(pickedProperties) { property in
                VStack(alignment: .leading, spacing: 1) {
                    Text(property.shortAddress).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let suburb = property.suburb { Text(suburb).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(.bar)
        .accessibilityHidden(true)   // every cell says its own home
    }

    @ViewBuilder
    private func cell(_ dimension: PriorityDimension, _ property: Property, named: Bool) -> some View {
        let summary = CompareSummary.cell(for: dimension, at: property)
        let content = CompareCellView(summary: summary, propertyName: named ? property.shortAddress : nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(property.shortAddress), \(dimension.displayName): \(summary.headline)\(summary.detail.map { ", \($0)" } ?? "")")
        if summary.hasEvidence {
            NavigationLink { CompareEvidenceView(property: property, dimension: dimension) } label: { content }
                .buttonStyle(PressScaleStyle(scale: 0.98))
                .accessibilityHint("Shows what you recorded")
        } else {
            content
        }
    }
}

/// One box of the table: a symbol for the kind of state as well as the words, so states do not differ by colour alone.
struct CompareCellView: View {
    let summary: CompareCell
    let propertyName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let propertyName {
                Text(propertyName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol).font(.footnote).foregroundStyle(tint)
                Text(summary.headline).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            if let detail = summary.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if summary.hasEvidence {
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(summary.hasEvidence ? Color.primary : Color.secondary)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var symbol: String {
        switch summary.state {
        case .noted: "text.bubble"
        case .scannedNotCalculated: "sun.max"
        case .measured: "checkmark.seal"
        case .notRecorded: "circle.dashed"
        case .noSource: "minus"
        }
    }

    private var tint: Color {
        switch summary.state {
        case .noted: .accentColor
        case .scannedNotCalculated: SunPathOverlay.sun
        case .measured: .green
        case .notRecorded, .noSource: .secondary
        }
    }
}

/// What is behind one box: the photos, notes and scans themselves.
struct CompareEvidenceView: View {
    let property: Property
    let dimension: PriorityDimension

    var body: some View {
        let items = CompareSummary.observations(for: dimension, at: property)
        List {
            Section {
                ForEach(items) { item in
                    NavigationLink { ObservationDetailView(observation: item) } label: { ObservationRow(observation: item) }
                }
            } header: {
                Text(property.shortAddress)
            } footer: {
                if items.isEmpty { Text("Nothing recorded for this yet.") }
            }
        }
        .navigationTitle(dimension.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
