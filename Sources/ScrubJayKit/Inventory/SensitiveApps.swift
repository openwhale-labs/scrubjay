import Foundation

/// Apps whose local data is irreplaceable personal history — chat archives
/// above all. Their data directories are never preselected: losing a cache
/// costs a re-download, losing chat history costs the history.
public enum SensitiveApps {
  /// Messaging apps that keep chat archives on disk.
  static let chatBundleIDs: Set<String> = [
    "com.tencent.xinWeChat",  // WeChat
    "com.tencent.qq",
    "com.tdesktop.Telegram",  // Telegram (tdesktop build)
    "ru.keepcoder.Telegram",  // Telegram (native macOS build)
    "net.whatsapp.WhatsApp",
    "com.hnc.Discord",
    "com.tinyspeck.slackmacgap",  // Slack
    "org.whispersystems.signal-desktop",
    "com.electron.lark",  // 飞书 Feishu
    "com.electron.lark.international",
    "com.larksuite.larkApp",  // Lark
    "com.tencent.WeWorkMac",  // 企业微信 WeCom
    "com.alibaba.DingTalkMac",  // 钉钉
  ]

  /// Kinds that hold user data (as opposed to regenerable caches) for a
  /// sensitive app.
  public static let dataKinds: Set<LeftoverKind> = [
    .containers, .groupContainers, .applicationSupport,
  ]

  public static func holdsChatHistory(bundleID: String) -> Bool {
    chatBundleIDs.contains(bundleID)
  }
}
