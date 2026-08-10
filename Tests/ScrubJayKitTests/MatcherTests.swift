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

  @Test func helperSuffixIsHigh() {
    #expect(Matcher.match(entryName: "com.google.Chrome.helper", identity: chrome) == .high)
    #expect(
      Matcher.match(
        entryName: "com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm.plist",
        identity: chrome) == .high)
  }

  @Test func unknownSuffixIsLow() {
    // Could be an uninstalled sibling product sharing the prefix — never
    // worth preselecting.
    #expect(
      Matcher.match(entryName: "com.google.Chrome.LicenseManager", identity: chrome) == .low)
  }

  @Test func groupContainerMatching() {
    #expect(
      Matcher.matchGroupContainer(
        entryName: "5A4RE8SF68.com.google.Chrome", identity: chrome) == .low)
    #expect(
      Matcher.matchGroupContainer(
        entryName: "UBF8T346G9.group.com.google.Chrome.shared", identity: chrome) == .low)
    #expect(
      Matcher.matchGroupContainer(
        entryName: "5A4RE8SF68.com.tencent.xinWeChat", identity: chrome) == nil)
    #expect(Matcher.matchGroupContainer(entryName: "NoDotsHere", identity: chrome) == nil)
  }

  @Test func channelSuffixIsDowngradedToLow() {
    // These likely belong to a sibling channel app (Chrome Beta/Canary),
    // installed or not — never worth preselecting.
    #expect(Matcher.match(entryName: "com.google.Chrome.beta.plist", identity: chrome) == .low)
    #expect(Matcher.match(entryName: "com.google.Chrome.canary.plist", identity: chrome) == .low)
    #expect(Matcher.match(entryName: "com.google.Chrome.beta", identity: chrome) == .low)
  }

  @Test func vendorChildComposesAppName() {
    #expect(
      Matcher.matchVendorChild(vendorDir: "Google", entryName: "Chrome", identity: chrome)
        == .medium)
    #expect(
      Matcher.matchVendorChild(vendorDir: "Google", entryName: "Chrome Beta", identity: chrome)
        == nil)
    #expect(
      Matcher.matchVendorChild(vendorDir: "Google", entryName: "GoogleUpdater", identity: chrome)
        == nil)
    // Bundle-ID rules still apply to children.
    #expect(
      Matcher.matchVendorChild(
        vendorDir: "Google", entryName: "com.google.Chrome", identity: chrome) == .certain)
  }

  @Test func vendorTokenExtraction() {
    #expect(Matcher.vendorToken(bundleID: "com.google.Chrome") == "google")
    #expect(Matcher.vendorToken(bundleID: "org.mozilla.firefox") == "mozilla")
    #expect(Matcher.vendorToken(bundleID: "weirdapp") == nil)
    #expect(Matcher.vendorToken(bundleID: "com.app") == nil)
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

  @Test func alternateNamesParticipateInMatching() {
    // Visual Studio Code: file name differs from its CFBundleName "Code",
    // and the Application Support directory is keyed by the latter.
    let vscode = AppIdentity(
      bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", altNames: ["Code"])
    #expect(Matcher.match(entryName: "Code", identity: vscode) == .medium)
    #expect(Matcher.match(entryName: "Visual Studio Code", identity: vscode) == .medium)
    #expect(Matcher.match(entryName: "Codex", identity: vscode) == nil)
  }

  @Test func normalizeStripsExtensionsAndSeparators() {
    #expect(Matcher.normalize("Google Chrome.app") == "googlechrome")
    #expect(Matcher.normalize("google_chrome") == "googlechrome")
  }
}
