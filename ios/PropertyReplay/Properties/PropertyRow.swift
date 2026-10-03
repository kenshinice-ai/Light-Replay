import PropertyModel
import SwiftUI

struct PropertyRow: View {
    let property: Property
    var showsInspection = false
    var distanceText: String? = nil
    var activityText: String? = nil
    /// The status symbol grows with the text; in a fixed 24 pt column it ran into the address at large sizes.
    @ScaledMetric(relativeTo: .body) private var symbolWidth = 24.0

    var body: some View {
        // One line each when it all fits. When it does not (large text, a long address, the narrow iPad sidebar),
        // nothing is cut short: the address wraps, the details go one to a line and the marks go under them.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                symbol
                VStack(alignment: .leading, spacing: 2) {
                    title.lineLimit(1)
                    HStack(spacing: 6) { details(separated: true) }.lineLimit(1)
                }
                Spacer(minLength: 8)
                marks
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                symbol
                VStack(alignment: .leading, spacing: 2) {
                    title
                    details(separated: false)
                    marks
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)   // the whole row is the tap target in either layout
    }

    private var symbol: some View {
        Image(systemName: statusSymbol).foregroundStyle(statusColor).frame(width: symbolWidth)
    }

    private var title: some View {
        Text(property.shortAddress).font(.body.weight(.medium))
    }

    /// Side by side the details are separated by dots; one to a line they need none.
    @ViewBuilder
    private func details(separated: Bool) -> some View {
        let dot = separated ? "· " : ""
        Group {
            Text(property.suburb ?? property.status.displayName)
            if showsInspection, let at = property.inspectionAt { Text(dot + Formatting.inspectionDate.string(from: at)) }
            if let distanceText { Text(dot + distanceText) }
            if let activityText { Text(dot + activityText) }
        }
        .font(.footnote).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var marks: some View {
        if property.isSample || property.coordinate == nil {
            HStack(spacing: 8) {
                if property.isSample {
                    Text("SAMPLE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .lineLimit(1).fixedSize()   // a badge is one word: never wrapped, never hyphenated
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                        .accessibilityLabel("Sample property, fictional")
                }
                if property.coordinate == nil {
                    Image(systemName: "mappin.slash").foregroundStyle(.tertiary).accessibilityLabel("No location yet")
                }
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
