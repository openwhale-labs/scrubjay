import Testing

@testable import ScrubJayKit

@Suite("Matcher")
struct MatcherTests {
  let chrome = AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")

  @Test func exactBundleIDIsCertain() {
    #expect(Matcher.match(entryName: "com.google.Chrome", identity: chrome) == .certain)
    #expect(Matcher.match(entryName: "COM.GOOGLE.CHROME", identity: chrome) == .certain)
  }

  @Test func bundleIDWithKnownSuffixIsCertain() {
    #expect(Matcher.match(entryName: "com.google.Chrome.plist", identity: chrome) == .certain)
    #expect(Matcher.match(entryName: "com.google.Chrome.savedState", identity: chrome) == .certain)
    #expect(
      Matcher.match(entryName: "com.google.Chrome.binarycookies", identity: chrome) == .certain)
  }

  @Test func bundleIDWithUnknownSuffixIsHigh() {
    #expect(Matcher.match(entryName: "com.google.Chrome.helper", identity: chrome) == .high)
    #expect(Matcher.match(entryName: "com.google.Chrome.canary.plist", identity: chrome) == .high)
  }

  @Test func siblingBundleIDDoesNotMatch() {
    // Shares the vendor prefix and even the leading characters of the last
    // component — must not match.
    #expect(Matcher.match(entryName: "com.google.Chromecast", identity: chrome) == nil)
    #expect(Matcher.match(entryName: "com.google.Keep", identity: chrome) == nil)
  }

  @Test func normalizedNameIsMedium() {
    #expect(Matcher.match(entryName: "Google Chrome", identity: chrome) == .medium)
    #expect(Matcher.match(entryName: "google-chrome", identity: chrome) == .medium)
    #expect(Matcher.match(entryName: "GoogleChrome", identity: chrome) == .medium)
  }

  @Test func partialNameDoesNotMatch() {
    #expect(Matcher.match(entryName: "Google", identity: chrome) == nil)
    #expect(Matcher.match(entryName: "Chrome Extensions", identity: chrome) == nil)
  }

  @Test func shortNamesAreDowngradedToLow() {
    let arc = AppIdentity(bundleID: "company.thebrowser.Browser", name: "Arc")
    #expect(Matcher.match(entryName: "Arc", identity: arc) == .low)
  }

  @Test func genericNamesNeverMatchByName() {
    let helper = AppIdentity(bundleID: "com.example.helper", name: "Helper")
    #expect(Matcher.match(entryName: "Helper", identity: helper) == nil)
  }

  @Test func unrelatedEntriesDoNotMatch() {
    #expect(Matcher.match(entryName: "org.mozilla.firefox.plist", identity: chrome) == nil)
    #expect(Matcher.match(entryName: "Slack", identity: chrome) == nil)
  }

  @Test func normalizeStripsExtensionsAndSeparators() {
    #expect(Matcher.normalize("Google Chrome.app") == "googlechrome")
    #expect(Matcher.normalize("google_chrome") == "googlechrome")
  }
}
