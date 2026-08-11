import SwiftUI

/// The app's design tokens. Views read sizes and colours from here rather
/// than writing literals, so the same element looks the same everywhere.
///
/// Colours are absolute (`NSColor` semantic colours), never SwiftUI's
/// hierarchical `.secondary`/`.quaternary` shape styles: those resolve
/// against whatever `foregroundStyle` an ancestor happens to set, so the
/// identical component renders differently depending on where it is placed.
enum Theme {
  /// A 4pt grid. Nothing in between — if a gap feels wrong it belongs in a
  /// different step.
  enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
  }

  enum Radius {
    static let sm: CGFloat = 5
    static let md: CGFloat = 8
  }

  enum Size {
    /// Filter fields in pane headers.
    static let filterField: CGFloat = 200
    /// The Dock-style dot marking a running app.
    static let statusDot: CGFloat = 5
  }

  /// Icon and thumbnail sizes used in lists.
  enum IconSize {
    static let row: CGFloat = 22
    static let sidebar: CGFloat = 28
  }

  enum Palette {
    /// Background for inline code, chips, and other quiet fills.
    static let chipFill = Color(nsColor: .quaternaryLabelColor).opacity(0.35)
    /// Zebra striping in lists.
    static let rowStripe = Color(nsColor: .labelColor).opacity(0.045)
    /// Body text that is not the primary label.
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    /// Captions, paths, and other supporting detail.
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    /// Something needs attention but nothing is broken.
    static let caution = Color(nsColor: .systemOrange)
    /// Irreversible-in-practice: chat history and the like.
    static let danger = Color(nsColor: .systemRed)
    /// An app is running.
    static let running = Color(nsColor: .systemGreen)
    /// Confirmation, e.g. a command was copied.
    static let confirmation = Color(nsColor: .systemGreen)
    /// Keeps the running dot legible on a selected (blue) row.
    static let dotRing = Color.white.opacity(0.6)
  }

  /// How long a transient confirmation stays visible.
  static let confirmationDuration: Duration = .seconds(2)
}
