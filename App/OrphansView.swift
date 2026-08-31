import AppKit
import ScrubJayKit
import SwiftUI

/// Leftovers of apps that are no longer installed. Nothing is preselected;
/// the magnifier on each row shows the item in Finder for inspection.
struct OrphansView: View {
  @Environment(AppState.self) private var state
  @State private var confirming = false
  @State private var filter = ""

  /// Orphans passing the current filter. Selection is bound by identity,
  /// never by index — the array shrinks after removal.
  private func visibleItems(_ orphans: [SelectableItem]) -> [SelectableItem] {
    guard !filter.isEmpty else { return orphans }
    return orphans.filter { $0.item.url.path.localizedCaseInsensitiveContains(filter) }
  }

  private func selectionBinding(for id: URL) -> Binding<Bool> {
    .init(
      get: { state.orphans?.first(where: { $0.id == id })?.isSelected ?? false },
      set: { value in
        guard let index = state.orphans?.firstIndex(where: { $0.id == id }) else { return }
        state.orphans?[index].isSelected = value
      })
  }

  var body: some View {
    @Bindable var state = state
    if let orphans = state.orphans {
      let visible = visibleItems(orphans)
      let selected = orphans.filter(\.isSelected)
      let selectedSize = selected.compactMap(\.item.sizeBytes).reduce(0, +)
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
          HStack {
            Text("Orphaned leftovers").font(.title2.bold())
            Spacer()
            FilterField(prompt: "Filter", text: $filter)
              .frame(width: Theme.Size.filterField)
          }
          Text(
            "Files keyed by bundle identifiers that no installed app claims "
              + "— usually traces of uninstalled apps. Inspect with the "
              + "magnifier; nothing is selected for you.")
          .font(.callout)
          .foregroundStyle(Theme.Palette.secondaryText)
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
                !visible.isEmpty
                  && visible.allSatisfy { entry in
                    state.orphans?.first(where: { $0.id == entry.id })?.isSelected ?? false
                  }
              },
              set: { all in
                let ids = Set(visible.map(\.id))
                if let orphans = state.orphans {
                  for index in orphans.indices where ids.contains(orphans[index].id) {
                    state.orphans?[index].isSelected = all
                  }
                }
              })
          )
          .toggleStyle(.checkbox)
          Text("\(selected.count) selected · \(FileSize.format(selectedSize))")
            .foregroundStyle(Theme.Palette.secondaryText)
            .padding(.leading, Theme.Space.md)
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

  private func list(orphans: [SelectableItem], visible: [SelectableItem], state: AppState)
    -> some View {
    List {
      ForEach(
        [
          (Confidence.medium, "No related app installed"),
          (Confidence.low, "Vendor apps still installed — often shared tooling")
        ], id: \.0
      ) { confidence, title in
        let group = visible.filter { $0.item.confidence == confidence }
        if !group.isEmpty {
          Section(title) {
            ForEach(group) { entry in
              orphanRow(entry)
            }
          }
        }
      }
    }
  }

  private func orphanRow(_ entry: SelectableItem) -> some View {
    let item = entry.item
    return HStack(spacing: Theme.Space.md) {
      Toggle("", isOn: selectionBinding(for: entry.id))
        .labelsHidden()
        .toggleStyle(.checkbox)
      Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
        .resizable()
        .frame(width: Theme.IconSize.row, height: Theme.IconSize.row)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
        Text(abbreviatedParent(of: item.url))
          .font(.caption)
          .foregroundStyle(Theme.Palette.secondaryText)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      if let size = item.sizeBytes {
        Text(FileSize.format(size))
          .foregroundStyle(Theme.Palette.secondaryText)
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
