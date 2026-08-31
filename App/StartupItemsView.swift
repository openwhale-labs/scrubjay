import AppKit
import ScrubJayKit
import SwiftUI

/// Login items and background daemons whose app is gone. macOS keeps these
/// registered — and often still switched on — after an app is removed, and
/// offers no way to delete them one at a time, so this pane reports rather
/// than removes.
struct StartupItemsView: View {
  @Environment(AppState.self) private var state

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: Theme.Space.xs) {
        Text("Startup items").font(.title2.bold())
        Text(
          "Login items and background services registered by apps that are no longer installed."
        )
        .font(.callout)
        .foregroundStyle(Theme.Palette.secondaryText)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
      Divider()
      content
    }
  }

  @ViewBuilder
  private var content: some View {
    if state.helper.status != .enabled {
      Spacer()
      ContentUnavailableView {
        Label("Reading this list needs the ScrubJay helper", systemImage: "shield")
      } description: {
        Text(
          "The list of startup items is readable only with elevated access. "
            + "Enabling opens System Settings › Login Items: turn on ScrubJay "
            + "under “Allow in the Background”. That switch approves the "
            + "helper — it does not launch ScrubJay at login.")
      } actions: {
        Button("Enable…") {
          if let message = state.helper.register() {
            state.removalError = "Helper registration failed: \(message)"
          } else {
            Task { await state.loadBackgroundItems() }
          }
        }
      }
      Spacer()
    } else if let stale = state.staleBackgroundItems {
      if stale.isEmpty {
        Spacer()
        ContentUnavailableView(
          "Nothing left behind", systemImage: "checkmark.circle",
          description: Text(
            "All \(state.backgroundItemsTotal) startup items belong to installed apps."))
        Spacer()
      } else {
        list(stale)
        Divider()
        footer(stale)
      }
    } else {
      Spacer()
      ProgressView("Reading startup items…")
      Spacer()
    }
  }

  private func list(_ stale: [StaleBackgroundItem]) -> some View {
    List {
      ForEach(stale) { entry in
        HStack(spacing: Theme.Space.md) {
          Image(systemName: entry.item.isEnabled ? "power.circle.fill" : "power.circle")
            .foregroundStyle(entry.item.isEnabled ? .orange : .secondary)
            .help(entry.item.isEnabled ? "Still switched on" : "Switched off")
          VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Theme.Space.sm) {
              Text(entry.item.name)
              Text(entry.item.kind)
                .font(.caption2)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, 1)
                .background(Theme.Palette.chipFill, in: Capsule())
                .foregroundStyle(Theme.Palette.secondaryText)
            }
            Text(
              entry.reason == .appInTrash
                ? "Its app is in the Trash" : "Its app is gone"
            )
            .font(.caption)
            .foregroundStyle(Theme.Palette.secondaryText)
          }
          Spacer()
          if let developer = entry.item.developer {
            Text(developer)
              .font(.caption)
              .foregroundStyle(Theme.Palette.secondaryText)
          }
        }
      }
    }
  }

  private func footer(_ stale: [StaleBackgroundItem]) -> some View {
    HStack(alignment: .top, spacing: Theme.Space.md) {
      Image(systemName: "info.circle").foregroundStyle(Theme.Palette.secondaryText)
      Text(
        "\(stale.count) of \(state.backgroundItemsTotal) items. These "
          + "entries are harmless — nothing behind them can launch. macOS "
          + "offers no way to remove one on its own; they only disappear "
          + "with a full startup-item reset, which would make you "
          + "re-approve every app on this list. Not worth it for a "
          + "cosmetic leftover.")
      .font(.caption)
      .foregroundStyle(Theme.Palette.secondaryText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }
}
