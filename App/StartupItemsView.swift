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
      VStack(alignment: .leading, spacing: 4) {
        Text("Startup items").font(.title2.bold())
        Text(
          "Login items and background services registered by apps that are no longer installed."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
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
        Text("The list of startup items is readable only with elevated access.")
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
        HStack(spacing: 8) {
          Image(systemName: entry.item.isEnabled ? "power.circle.fill" : "power.circle")
            .foregroundStyle(entry.item.isEnabled ? .orange : .secondary)
            .help(entry.item.isEnabled ? "Still switched on" : "Switched off")
          VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
              Text(entry.item.name)
              Text(entry.item.kind)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                .foregroundStyle(.secondary)
            }
            Text(
              entry.reason == .appInTrash
                ? "Its app is in the Trash" : "Its app is gone"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          Spacer()
          if let developer = entry.item.developer {
            Text(developer)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func footer(_ stale: [StaleBackgroundItem]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "info.circle").foregroundStyle(.secondary)
        Text(
          "\(stale.count) of \(state.backgroundItemsTotal) items. These entries outlive the app and even an emptied Trash, and macOS offers no way to remove them one at a time."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      HStack(spacing: 6) {
        Text("Reset every startup item at once, then re-approve the apps you keep:")
          .font(.caption)
          .foregroundStyle(.secondary)
        CommandChip(command: "sudo sfltool resetbtm")
      }
      .padding(.leading, 22)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }
}
