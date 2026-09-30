import PropertyModel
import SwiftUI

struct PropertyRow: View {
    let property: Property
    var showsInspection = false
    var distanceText: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(property.shortAddress).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(property.suburb ?? property.status.displayName)
                    if showsInspection, let at = property.inspectionAt { Text("· \(Formatting.inspectionDate.string(from: at))") }
                    if let distanceText { Text("· \(distanceText)") }
                }
                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if property.isSample {
                Text("SAMPLE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                    .accessibilityLabel("Sample property, fictional")
            }
            if property.coordinate == nil {
                Image(systemName: "mappin.slash").foregroundStyle(.tertiary).accessibilityLabel("No location yet")
            }
        }
    }

    private var statusSymbol: String {
        switch property.status {
        case .toInspect: "calendar"
        case .inspected: "checkmark.circle"
        case .shortlisted: "star.fill"
        case .dropped: "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch property.status {
        case .toInspect: .blue
        case .inspected: .green
        case .shortlisted: .orange
        case .dropped: .secondary
        }
    }
}
