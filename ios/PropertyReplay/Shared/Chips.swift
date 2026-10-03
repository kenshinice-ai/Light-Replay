import PropertyModel
import SwiftUI

/// One look for every tag control (room, category, Like / Concern / Ask): at least 44 pt tall, wraps its text, and
/// shows selection with a filled symbol and a border as well as colour (review U18, apple-design review finding 8).
struct ChipLabel: View {
    let title: String
    let systemImage: String
    var selected = false
    var isMenu = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            if isMenu {
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(selected ? Color.accentColor : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        // An explicit fill: inside a Menu label a hierarchical style would pick up the accent tint and turn blue.
        .background(selected ? Color.accentColor.opacity(0.16) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}

/// Room and category as menus, Like / Concern / Ask as toggles. Used by the draft editor and the observation page so
/// tagging looks and behaves the same before and after saving.
struct TagControls: View {
    let rooms: [String]
    let room: String?
    let category: ObservationCategory
    let sentiment: Sentiment
    let setRoom: (String) -> Void
    let setCategory: (ObservationCategory) -> Void
    let setSentiment: (Sentiment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout {
                if !rooms.isEmpty {   // a note written away from the home has no room
                    Menu {
                        ForEach(rooms, id: \.self) { name in Button(name) { setRoom(name) } }
                    } label: {
                        ChipLabel(title: room ?? String(localized: "Room"), systemImage: "door.left.hand.open", isMenu: true)
                    }
                    .accessibilityLabel("Room")
                    .accessibilityValue(room ?? String(localized: "Not set"))
                }
                Menu {
                    ForEach(ObservationCategory.allCases) { c in
                        Button(c.displayName, systemImage: c.systemImage) { setCategory(c) }
                    }
                } label: {
                    ChipLabel(title: category.displayName, systemImage: category.systemImage, isMenu: true)
                }
                .accessibilityLabel("About")
                .accessibilityValue(category.displayName)
            }
            FlowLayout {
                ForEach([Sentiment.like, .concern, .ask]) { s in
                    let on = sentiment == s
                    Button {
                        setSentiment(on ? .neutral : s)
                    } label: {
                        ChipLabel(title: s.displayName, systemImage: on ? s.systemImage + ".fill" : s.systemImage, selected: on)
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// Immediate, physical press feedback for custom-drawn buttons: a slight scale on touch-down, back on release
/// (apple-design: respond on press; review U19 suggests about 0.97). No motion when Reduce Motion is on, only dimming.
struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
    }
}

/// A label and its value: side by side when they fit, stacked when the text is large (review U02).
struct AdaptiveRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.secondary)
                Text(value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
