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
        VStack(alignment: .leading, spacing: 4) {
          Text("Developer caches").font(.title2.bold())
          Text("Everything here is re-downloaded or rebuilt on demand. Nothing is selected for you.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        Divider()
        List {
          ForEach(caches.indices, id: \.self) { index in
            Toggle(isOn: .init(
              get: { state.devCaches?[index].isSelected ?? false },
              set: { state.devCaches?[index].isSelected = $0 })
            ) {
              cacheRow(caches[index].status)
            }
          }
        }
        .toggleStyle(.checkbox)
        Divider()
        HStack {
          Text("\(selected.count) selected · \(FileSize.format(selectedSize))")
            .foregroundStyle(.secondary)
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
    HStack(spacing: 8) {
      Image(systemName: "folder")
        .frame(width: 22)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 1) {
        Text(status.location.name)
        Text(status.location.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if let size = status.sizeBytes {
        Text(FileSize.format(size))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
  }
}
