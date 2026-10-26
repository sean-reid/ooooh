import Design
import SwiftUI

/// The subscribe screen: one sentence, two plans, restore, the legal links, close.
public struct PaywallView<Header: View>: View {
  public var store: BillingStore
  public var onClose: () -> Void
  private let header: Header
  /// ImageRenderer draws a ScrollView empty, so snapshots render the content unscrolled.
  var scrolls = true
  @State private var failure: String?

  public static var privacyURL: URL { URL(string: "https://ooooh.app/privacy.html")! }
  public static var termsURL: URL { URL(string: "https://ooooh.app/terms.html")! }

  public init(
    store: BillingStore, onClose: @escaping () -> Void, @ViewBuilder header: () -> Header
  ) {
    self.store = store
    self.onClose = onClose
    self.header = header()
  }

  public var body: some View {
    ZStack {
      Palette.sky.ignoresSafeArea()
      VStack(spacing: 0) {
        bar
        if scrolls {
          ScrollView { content }
        } else {
          GeometryReader { _ in content.fixedSize(horizontal: false, vertical: true) }.clipped()
        }
      }
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 24) {
      header
      Text("Keep talking.")
        .font(Typography.display)
        .foregroundStyle(Palette.ink)
        .accessibilityAddTraits(.isHeader)
      Text("A subscription is unlimited sessions and every prompt.")
        .font(Typography.body)
        .foregroundStyle(Palette.ink)
      VStack(alignment: .leading, spacing: 12) {
        if !store.plans.isEmpty {
          ForEach(store.plans) { plan in
            PlanButton(plan: plan, disabled: store.isPurchasing) { buy(plan.id) }
          }
        } else if store.hasLoadedPlans {
          noPlans
        } else {
          loadingPlans
        }
      }
      .padding(.top, 8)
      if let failure {
        Text(failure)
          .font(Typography.caption)
          .foregroundStyle(Palette.accent)
      }
      Button("Restore purchases") { restore() }
        .font(Typography.body)
        .foregroundStyle(Palette.accent)
        .frame(minHeight: 44)
        .disabled(store.isPurchasing)
      HStack(spacing: 24) {
        Link("Privacy", destination: Self.privacyURL)
          .accessibilityLabel("Privacy policy")
        Link("Terms", destination: Self.termsURL)
          .accessibilityLabel("Terms of use")
      }
      .font(Typography.caption)
      .foregroundStyle(Palette.inkDim)
      .frame(minHeight: 44)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.bottom, 48)
  }

  private var noPlans: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("The plans couldn't be loaded.")
        .font(Typography.body)
        .foregroundStyle(Palette.ink)
      Button("Try again") { reload() }
        .font(Typography.body)
        .foregroundStyle(Palette.accent)
        .frame(minHeight: 44)
    }
  }

  /// Two cards the size of the plan buttons, so the sheet keeps its height when the plans arrive.
  private var loadingPlans: some View {
    VStack(spacing: 12) {
      PlanButton(plan: Plan(id: .monthly, price: "$0.00"), disabled: true) {}
      PlanButton(plan: Plan(id: .yearly, price: "$00.00", perMonth: "$0.00"), disabled: true) {}
    }
    .redacted(reason: .placeholder)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading the plans")
  }

  private var bar: some View {
    HStack {
      Spacer()
      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.body.weight(.medium))
          .frame(minWidth: 44, minHeight: 44)
      }
      .accessibilityLabel("Close")
    }
    .foregroundStyle(Palette.accent)
    .padding(.horizontal, 12)
    .padding(.top, 4)
  }

  private func buy(_ id: ProductID) {
    Task { await finish { try await store.purchase(id) } }
  }

  private func restore() {
    Task { await finish { try await store.restore() } }
  }

  private func reload() {
    Task { try? await store.load() }
  }

  private func finish(_ action: () async throws -> Entitlement) async {
    do {
      failure = nil
      if try await action().isPaid { onClose() }
    } catch {
      failure = error.localizedDescription
    }
  }
}

extension PaywallView where Header == EmptyView {
  public init(store: BillingStore, onClose: @escaping () -> Void) {
    self.init(store: store, onClose: onClose) { EmptyView() }
  }
}

struct PlanButton: View {
  var plan: Plan
  var disabled: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 4) {
        Text(plan.name)
          .font(Typography.title)
        Text("\(plan.price) \(plan.period)")
          .font(Typography.body)
        if let perMonth = plan.perMonth {
          Text("\(perMonth) a month")
            .font(Typography.caption)
            .foregroundStyle(Palette.inkDim)
        }
      }
      .foregroundStyle(Palette.ink)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .background(Palette.skyRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityLabel("\(plan.name), \(plan.priceLine)")
    .accessibilityHint("Subscribes")
  }
}
