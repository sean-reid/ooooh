import StoreKit

/// One product as the paywall shows it, with the price strings already localized.
public struct Plan: Identifiable, Equatable, Sendable {
  public var id: ProductID
  public var price: String
  public var perMonth: String?

  public init(id: ProductID, price: String, perMonth: String? = nil) {
    self.id = id
    self.price = price
    self.perMonth = perMonth
  }

  init?(_ product: Product) {
    guard let id = ProductID(rawValue: product.id) else { return nil }
    self.init(
      id: id, price: product.displayPrice,
      perMonth: id == .yearly ? (product.price / 12).formatted(product.priceFormatStyle) : nil)
  }

  public var name: String { id.name }
  public var period: String { id.period }

  /// "$6.99 a month", or "$49.99 a year, $4.17 a month" for yearly.
  public var priceLine: String {
    let line = "\(price) \(period)"
    guard let perMonth else { return line }
    return "\(line), \(perMonth) a month"
  }
}
