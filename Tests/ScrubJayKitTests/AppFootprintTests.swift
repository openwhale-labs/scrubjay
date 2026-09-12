import Foundation
import Testing

@testable import ScrubJayKit

@Suite("App footprint snapshots")
struct AppFootprintTests {
  let bundleID = "com.example.App"

  @Test func freshSmallerScanSupersedesAnOlderLargerScan() {
    var cache = AppFootprintCache()
    let background = cache.beginScan(for: bundleID)
    let detail = cache.beginScan(for: bundleID)
    let current = AppFootprint(bundleSize: 1_320_000_000)

    let detailAccepted = cache.publish(current, for: detail)
    #expect(detailAccepted)
    let backgroundAccepted = cache.publish(AppFootprint(bundleSize: 12_430_000_000), for: background)
    #expect(!backgroundAccepted)
    #expect(cache[bundleID]?.totalSize == current.totalSize)
    #expect(!cache.isCurrent(background))

    // Freshness decides the winner, not whether the new number is smaller.
    let later = cache.beginScan(for: bundleID)
    let laterAccepted = cache.publish(AppFootprint(bundleSize: 14_000_000_000), for: later)
    #expect(laterAccepted)
    #expect(cache[bundleID]?.totalSize == 14_000_000_000)
  }

  @Test func lateBundleEstimateCannotReplaceDetail() {
    var cache = AppFootprintCache()
    let initial = cache.beginScan(for: bundleID)
    let detail = cache.beginScan(for: bundleID)
    #expect(!cache.isCurrent(initial)) // Skip the queued background full scan too.
    let detailAccepted = cache.publish(AppFootprint(bundleSize: 100_000), for: detail)
    #expect(detailAccepted)
    let estimate = AppFootprint(bundleSize: 10_000, isBundleOnly: true)
    let estimateAccepted = cache.publish(estimate, for: initial)
    #expect(!estimateAccepted)
    #expect(cache[bundleID]?.isBundleOnly == false)
    #expect(cache[bundleID]?.totalSize == 100_000)
  }

  @Test func inventoryReloadInvalidatesPendingScans() {
    var cache = AppFootprintCache()
    let old = cache.beginScan(for: bundleID)
    cache.reset()
    let new = cache.beginScan(for: bundleID)
    let staleAccepted = cache.publish(AppFootprint(bundleSize: 10_000), for: old)
    #expect(!staleAccepted)
    let freshAccepted = cache.publish(AppFootprint(bundleSize: 20_000), for: new)
    #expect(freshAccepted)
    #expect(cache[bundleID]?.totalSize == 20_000)
  }

  @Test func switchingAppsDoesNotInvalidateAnotherAppsSnapshot() {
    var cache = AppFootprintCache()
    let first = cache.beginScan(for: bundleID)
    let second = cache.beginScan(for: "com.example.Other")
    let firstAccepted = cache.publish(AppFootprint(bundleSize: 10_000), for: first)
    #expect(firstAccepted)
    let secondAccepted = cache.publish(AppFootprint(bundleSize: 20_000), for: second)
    #expect(secondAccepted)
    #expect(cache[bundleID]?.totalSize == 10_000)
  }

  @Test func totalsIncludeLowConfidenceItemsAndRetainReadFailures() {
    let item = LeftoverItem(
      url: URL(fileURLWithPath: "/fixture/Library/Group Containers/team.com.example.App"),
      kind: .groupContainers, confidence: .low, sizeBytes: 11_000_000_000)
    let footprint = AppFootprint(bundleSize: 1_000_000_000, items: [item])
    #expect(footprint.totalSize == 12_000_000_000)
    #expect(!footprint.isIncomplete)

    let failed = URL(fileURLWithPath: "/fixture/Library/Containers")
    let partial = AppFootprint(
      bundleSize: 1_000_000_000, items: [item], unreadableURLs: [failed])
    #expect(partial.isIncomplete)
    #expect(partial.formattedSize.hasPrefix("≥ "))
    #expect(partial.unreadableURLs == [failed])
    #expect(AppFootprint(bundleSize: nil).isIncomplete)
  }
}
