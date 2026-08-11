import ScrubJayKit
import SwiftUI

/// Checklist of regenerable developer caches. Nothing is preselected; every
/// removal is confirmed and goes to the Trash.
struct DevCachesView: View {
  @Environment(AppState.self) private var state
  @State private var confirming = false

  var body: some View {
    @Bindable var state = state
    if let caches = state.devCaches {
      let selected = caches.filter(\.isSelected)
      let selectedSize = selected.compactMap(\.status.sizeBytes).reduce(0, +)
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
          Text("Developer caches").font(.title2.bold())
          Text("Everything here is re-downloaded or rebuilt on demand. Nothing is selected for you.")
            .font(.callout)
            .foregroundStyle(Theme.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        Divider()
        List {
          ForEach(caches) { cache in
            HStack(spacing: Theme.Space.md) {
              Toggle("", isOn: .init(
                get: { state.devCaches?.first(where: { $0.id == cache.id })?.isSelected ?? false },
                set: { value in
                  guard let index = state.devCaches?.firstIndex(where: { $0.id == cache.id })
                  else { return }
                  state.devCaches?[index].isSelected = value
                }))
                .labelsHidden()
                .toggleStyle(.checkbox)
              cacheRow(cache.status)
            }
          }
        }
        Divider()
        HStack {
          Text("\(selected.count) selected · \(FileSize.format(selectedSize))")
            .foregroundStyle(Theme.Palette.secondaryText)
          Spacer()
          Button("Move to Trash…") { confirming = true }
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty)
        }
        .padding()
        .confirmationDialog(
          "Move \(selected.count) cache directories (\(FileSize.format(selectedSize))) to the Trash?",
          isPresented: $confirming, titleVisibility: .visible
        ) {
          Button("Move to Trash", role: .destructive) {
            Task { await state.cleanSelectedCaches() }
          }
        } message: {
          Text("Caches are rebuilt when needed. You can restore items from the Trash.")
        }
      }
    } else {
      ProgressView("Measuring caches…")
    }
  }

  private func cacheRow(_ status: DevCacheStatus) -> some View {
    HStack(spacing: Theme.Space.md) {
      Image(systemName: "folder")
        .frame(width: Theme.IconSize.row)
        .foregroundStyle(Theme.Palette.secondaryText)
      VStack(alignment: .leading, spacing: 1) {
        Text(status.location.name)
        Text(status.location.detail)
          .font(.caption)
          .foregroundStyle(Theme.Palette.secondaryText)
      }
      Spacer()
      if let size = status.sizeBytes {
        Text(FileSize.format(size))
          .foregroundStyle(Theme.Palette.secondaryText)
          .monospacedDigit()
      }
      RevealButton(url: status.location.url)
    }
  }
}
