import Design
import SwiftUI

/// A serif heading, a raised card of rows, and an optional footer line.
struct SettingsSection<Rows: View>: View {
  var title: String
  var footer: String?
  @ViewBuilder var rows: Rows

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(Typography.title)
        .foregroundStyle(Palette.ink)
        .accessibilityAddTraits(.isHeader)
      VStack(spacing: 0) { rows }
        .padding(.horizontal, 16)
        .background(Palette.skyRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      if let footer {
        Text(footer)
          .font(Typography.caption)
          .foregroundStyle(Palette.inkDim)
          .padding(.horizontal, 4)
      }
    }
  }
}

/// A title with an optional detail line, the shape every row shares.
struct RowLabel: View {
  var title: String
  var detail: String?
  var color: Color = Palette.ink

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(Typography.body)
        .foregroundStyle(color)
      if let detail {
        Text(detail)
          .font(Typography.caption)
          .foregroundStyle(Palette.inkDim)
      }
    }
    .multilineTextAlignment(.leading)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .padding(.vertical, 6)
  }
}

/// A row that performs an action, with a chevron or an outward arrow at the trailing edge.
struct ActionRow: View {
  var title: String
  var detail: String?
  var symbol = "chevron.right"
  var color: Color = Palette.ink
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        RowLabel(title: title, detail: detail, color: color)
        Image(systemName: symbol)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Palette.inkDim)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
  }
}

/// A row with three choices drawn as pills; the chosen one fills with amber.
struct ChoiceRow<Choice: Hashable>: View {
  var title: String
  var choices: [(value: Choice, title: String)]
  @Binding var selection: Choice
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(Typography.body)
        .foregroundStyle(Palette.ink)
      let layout =
        typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
      layout {
        ForEach(choices, id: \.value) { choice in
          let chosen = choice.value == selection
          Button {
            selection = choice.value
          } label: {
            Text(choice.title)
              .font(Typography.caption.weight(.medium))
              .foregroundStyle(chosen ? Palette.sky : Palette.ink)
              .padding(.horizontal, 12)
              .frame(maxWidth: .infinity, minHeight: 44)
              .background(chosen ? Palette.amber : Palette.sky.opacity(0.6), in: Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(chosen ? .isSelected : [])
        }
      }
    }
    .padding(.vertical, 12)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
  }
}

/// Amber when on, drawn in SwiftUI so it renders the same everywhere.
struct SkyToggleStyle: ToggleStyle {
  @ScaledMetric(relativeTo: .body) private var width = 51.0
  @ScaledMetric(relativeTo: .body) private var height = 31.0

  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: 12) {
        configuration.label
        Capsule()
          .fill(configuration.isOn ? Palette.amber : Palette.inkDim.opacity(0.35))
          .frame(width: width, height: height)
          .overlay(alignment: configuration.isOn ? .trailing : .leading) {
            Circle()
              .fill(Palette.sky)
              .padding(2)
          }
          .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

struct RowDivider: View {
  var body: some View {
    Rectangle()
      .fill(Palette.inkDim.opacity(0.18))
      .frame(height: 1)
  }
}
