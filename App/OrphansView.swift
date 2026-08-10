import AppKit
import ScrubJayKit
import SwiftUI

/// Leftovers of apps that are no longer installed. Nothing is preselected;
/// the magnifier on each row shows the item in Finder for inspection.
struct OrphansView: View {
  @Environment(AppState.self) private var state
  @State private var confirming = false
  @State private var filter = ""

  /// Indices of orphans passing the current filter.
  private func filteredIndices(_ orphans: [SelectableItem]) -> [Int] {
    guard !filter.isEmpty else { return Array(orphans.indices) }
    return orphans.indices.filter {
      orphans[$0].item.url.path.localizedCaseInsensitiveContains(filter)
    }
  }

  var body: some View {
    @Bindable var state = state
    if let orphans = state.orphans {
      let visible = filteredIndices(orphans)
      let selected = orphans.filter(\.isSelected)
      let selectedSize = selected.compactMap(\.item.sizeBytes).reduce(0, +)
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Orphaned leftovers").font(.title2.bold())
            Spacer()
            TextField("Filter", text: $filter)
              .textFieldStyle(.roundedBorder)
              .frame(width: 200)
          }
          Text(
            "Files keyed by bundle identifiers that no installed app claims — usually traces of uninstalled apps. Inspect with the magnifier; nothing is selected for you."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        Divider()
        if orphans.isEmpty {
          Spacer()
          ContentUnavailableView(
            "No orphaned leftovers", systemImage: "checkmark.circle",
            description: Text("Every bundle-identifier-keyed file belongs to an installed app."))
          Spacer()
        } else {
          list(orphans: orphans, visible: visible, state: state)
        }
        Divider()
        HStack {
          Toggle(
            filter.isEmpty ? "Select all" : "Select all filtered",
            isOn: .init(
              get: {
                !visible.isEmpty && visible.allSatisfy { state.orphans?[$0].isSelected ?? false }
              },
              set: { all in
                for index in visible {
                  state.orphans?[index].isSelected = all
                }
              })
          )
          .toggleStyle(.checkbox)
          Text("\(selected.count) selected · \(FileSize.format(selectedSize))")
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
          Spacer()
          Button("Move to Trash…") { confirming = true }
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty)
        }
        .padding()
        .confirmationDialog(
          "Move \(selected.count) items (\(FileSize.format(selectedSize))) to the Trash?",
          isPresented: $confirming, titleVisibility: .visible
        ) {
          Button("Move to Trash", role: .destructive) {
            Task { await state.cleanSelectedOrphans() }
          }
        } message: {
          Text("Nothing is deleted permanently. You can restore items from the Trash.")
        }
      }
    } else {
      ProgressView("Scanning for orphans…")
    }
  }

  private func list(orphans: [SelectableItem], visible: [Int], state: AppState) -> some View {
    List {
      ForEach(
        [
          (Confidence.medium, "No related app installed"),
          (Confidence.low, "Vendor apps still installed — often shared tooling"),
        ], id: \.0
      ) { confidence, title in
        let indices = visible.filter { orphans[$0].item.confidence == confidence }
        if !indices.isEmpty {
          Section(title) {
            ForEach(indices, id: \.self) { index in
              orphanRow(index, orphans: orphans, state: state)
            }
          }
        }
      }
    }
  }

  private func orphanRow(
    _ index: Int, orphans: [SelectableItem], state: AppState
  ) -> some View {
    let item = orphans[index].item
    return HStack(spacing: 8) {
      Toggle("", isOn: .init(
        get: { state.orphans?[index].isSelected ?? false },
        set: { state.orphans?[index].isSelected = $0 }))
        .labelsHidden()
        .toggleStyle(.checkbox)
      Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
        .resizable()
        .frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
        Text(abbreviatedParent(of: item.url))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      if let size = item.sizeBytes {
        Text(FileSize.format(size))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      RevealButton(url: item.url)
    }
  }

  private func abbreviatedParent(of url: URL) -> String {
    let parent = url.deletingLastPathComponent().path
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
  }
}
