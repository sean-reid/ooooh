import Billing
import Foundation
import Testing

@testable import Settings

@Suite struct SubscriptionLineTests {
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()
  static let us = Locale(identifier: "en_US")
  static let now = day(2026, 10, 27)

  static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
  }

  func line(_ entitlement: Entitlement, locale: Locale = us) -> String {
    entitlement.settingsLine(now: Self.now, calendar: Self.calendar, locale: locale)
  }

  @Test func aRenewalThisYearLeavesTheYearOut() {
    let renews = Self.day(2026, 11, 27)
    #expect(line(.subscribed(expires: renews, product: .monthly)) == "Monthly, renews November 27")
  }

  @Test func aRenewalInAnotherYearSpellsItOut() {
    let renews = Self.day(2027, 10, 27)
    #expect(
      line(.subscribed(expires: renews, product: .yearly)) == "Yearly, renews October 27, 2027")
  }

  @Test func theYearRuleFollowsTheCalendarYearNotTheDistance() {
    let renews = Self.day(2027, 1, 1)
    #expect(
      line(.subscribed(expires: renews, product: .monthly)) == "Monthly, renews January 1, 2027")
  }

  @Test func theDateFollowsTheLocale() {
    let renews = Self.day(2026, 11, 27)
    #expect(
      line(.subscribed(expires: renews, product: .monthly), locale: Locale(identifier: "en_GB"))
        == "Monthly, renews 27 November")
  }

  @Test func noExpiryNamesThePlanAlone() {
    #expect(line(.subscribed(expires: nil, product: .yearly)) == "Yearly")
  }

  @Test func graceEndedAndFreeHaveTheirOwnLines() {
    #expect(line(.inGrace(product: .monthly)) == "Monthly, payment being retried")
    #expect(line(.revoked) == "Subscription ended")
    #expect(line(.free(remainingSessions: 2)) == "Subscribe")
  }

  @Test func onlyThePaidStatesGetTheFooter() {
    #expect(
      Entitlement.subscribed(expires: Self.now, product: .monthly).settingsFooter
        == "Managed through the App Store.")
    #expect(
      Entitlement.inGrace(product: .yearly).settingsFooter == "Managed through the App Store.")
    #expect(Entitlement.revoked.settingsFooter == nil)
    #expect(Entitlement.free(remainingSessions: 3).settingsFooter == nil)
  }
}
