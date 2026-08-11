import AppKit
import ScrubJayKit
import SwiftUI

struct DetailView: View {
  @Environment(AppState.self) private var state
  @State private var confirming = false
  @State private var sortBySize = false

  var body: some View {
    @Bindable var state = state
    if let scan = state.scan {
      VStack(spacing: 0) {
        header(scan)
        Divider()
        checklist(scan: scan, state: state)
        Divider()
        footer(scan, state: state)
      }
      .alert(
        "Some items could not be moved to the Trash",
        isPresented: .init(
          get: { state.removalError != nil },
          set: { if !$0 { state.removalError = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(state.removalError ?? "")
      }
    }
  }

  // MARK: Header

  private func header(_ scan: ScanResult) -> some View {
    VStack(alignment: .leading, spacing: Theme.Space.xs) {
      HStack(spacing: Theme.Space.md) {
        Text(scan.app.name).font(.title2.bold())
        if let version = scan.app.version {
          Text(version).foregroundStyle(Theme.Palette.secondaryText)
        }
        Spacer()
        Picker("", selection: $sortBySize) {
          Text("Confidence").tag(false)
          Text("Size").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
      }
      Text(scan.app.bundleID)
        .font(.callout)
        .foregroundStyle(Theme.Palette.secondaryText)
      if state.runningBundleIDs.contains(scan.app.bundleID) {
          Label(
            "This app is running. Quit it before uninstalling.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.callout)
          .foregroundStyle(Theme.Palette.caution)
          .padding(.top, Theme.Space.xs)
        }
        if scan.holdsChatHistory {
          Label(
            """
              This app keeps chat history on this Mac. Its data folders start unselected — back them \
              up first if you may ever need them.
            """,
            systemImage: "bubble.left.and.exclamationmark.bubble.right")
            .font(.callout)
            .foregroundStyle(Theme.Palette.danger)
            .padding(.top, Theme.Space.xs)
        }
        if let cask = scan.caskToken {
          brewHint(cask)
        }
        if scan.items.contains(where: { LeftoverCatalog.isSystemPath($0.item.url) }) {
          helperHint
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }

  private var helperHint: some View {
    HStack(spacing: Theme.Space.sm) {
      Image(systemName: "shield")
      if state.helper.status == .enabled {
        Text("System-level items are removed through the ScrubJay helper.")
      } else {
        Text("System-level items need the ScrubJay helper (\(state.helper.statusDescription)).")
        Button("Enable…") {
          if let message = state.helper.register() {
            state.removalError = "Helper registration failed: \(message)"
          }
        }
      }
    }
    .font(.callout)
    .foregroundStyle(Theme.Palette.secondaryText)
    .padding(.top, Theme.Space.xs)
  }

  private func brewHint(_ cask: String) -> some View {
    HStack(spacing: Theme.Space.sm) {
      Image(systemName: "shippingbox")
      Text("Installed via Homebrew — after removal, clear its records:")
      CommandChip(command: "brew uninstall --cask \(cask)")
    }
    .font(.callout)
    .foregroundStyle(Theme.Palette.secondaryText)
    .padding(.top, Theme.Space.xs)
  }

  // MARK: Checklist

  private func checklist(scan: ScanResult, state: AppState) -> some View {
    List {
      Section("Application") {
        row(
          isOn: .init(
            get: { state.scan?.appBundleSelected ?? false },
            set: { state.scan?.appBundleSelected = $0 }),
          url: scan.app.bundleURL, size: scan.appBundleSize, flagged: false, agent: nil,
          confidenceTag: nil)
      }
      if sortBySize {
        Section("Leftovers — largest first") {
          let ordered = scan.items.sorted {
            ($0.item.sizeBytes ?? 0) > ($1.item.sizeBytes ?? 0)
          }
          ForEach(ordered) { entry in
            leftoverRow(entry, state: state, showConfidence: true)
          }
        }
      } else {
        ForEach(Confidence.allCases.reversed(), id: \.self) { confidence in
          let group = scan.items.filter { $0.item.confidence == confidence }
          if !group.isEmpty {
            Section(sectionTitle(confidence)) {
              ForEach(group) { entry in
                leftoverRow(entry, state: state, showConfidence: false)
              }
            }
          }
        }
      }
    }
  }

  /// Selection is bound by item identity, never by array index: the items
  /// array shrinks during removal, and a stale index would trap.
  private func selectionBinding(for id: URL, state: AppState) -> Binding<Bool> {
    .init(
      get: { state.scan?.items.first(where: { $0.id == id })?.isSelected ?? false },
      set: { value in
        guard let index = state.scan?.items.firstIndex(where: { $0.id == id }) else { return }
        state.scan?.items[index].isSelected = value
      })
  }

  private func leftoverRow(
    _ entry: SelectableItem, state: AppState, showConfidence: Bool
  ) -> some View {
    let item = entry.item
    return row(
      isOn: selectionBinding(for: entry.id, state: state),
      url: item.url, size: item.sizeBytes,
      flagged: !showConfidence && item.confidence == .medium,
      agent: item.launchAgent,
      confidenceTag: showConfidence ? confidenceLabel(item.confidence) : nil)
  }

  /// One checklist row: the checkbox is its own column, vertically centered
  /// against the whole row, not against the label's first text line.
  private func row(
    isOn: Binding<Bool>, url: URL, size: Int64?, flagged: Bool,
    agent: LaunchAgentInfo?, confidenceTag: String?
  ) -> some View {
    HStack(spacing: Theme.Space.md) {
      Toggle("", isOn: isOn)
        .labelsHidden()
        .toggleStyle(.checkbox)
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        .resizable()
        .frame(width: Theme.IconSize.row, height: Theme.IconSize.row)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: Theme.Space.xs) {
          Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
          if let confidenceTag {
            Text(confidenceTag)
              .font(.caption2)
              .padding(.horizontal, Theme.Space.sm)
              .padding(.vertical, 1)
              .background(Theme.Palette.chipFill, in: Capsule())
              .foregroundStyle(Theme.Palette.secondaryText)
          }
          if flagged {
            Image(systemName: "questionmark.circle")
              .foregroundStyle(Theme.Palette.caution)
              .help("Matched by app name — double-check before removing.")
          }
          if let agent, agent.isLoaded {
            Label("active", systemImage: "bolt.fill")
              .font(.caption)
              .foregroundStyle(Theme.Palette.caution)
              .help("Launch agent \(agent.label) is loaded; it is unloaded before removal.")
          }
          if LeftoverCatalog.isSystemPath(url) {
            Image(systemName: "shield")
              .font(.caption)
              .foregroundStyle(Theme.Palette.secondaryText)
              .help("System item — removal goes through the privileged helper.")
          }
        }
        Text(abbreviatedParent(of: url))
          .font(.caption)
          .foregroundStyle(Theme.Palette.secondaryText)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      if let size {
        Text(FileSize.format(size))
          .foregroundStyle(Theme.Palette.secondaryText)
          .monospacedDigit()
      }
      RevealButton(url: url)
    }
  }

  // MARK: Footer

  private func footer(_ scan: ScanResult, state: AppState) -> some View {
    HStack {
      // Two honest checkboxes: "recommended" covers the preselection set
      // (medium and above), "all" really means everything including
      // loosely matched items.
      Toggle(
        "Recommended",
        isOn: .init(
          get: {
            guard let scan = state.scan else { return false }
            return scan.appBundleSelected
              && scan.items.filter { $0.item.confidence >= .medium }.allSatisfy(\.isSelected)
          },
          set: { on in
            state.scan?.appBundleSelected = on
            if let items = state.scan?.items {
              for index in items.indices where items[index].item.confidence >= .medium {
                state.scan?.items[index].isSelected = on
              }
            }
          })
      )
      .toggleStyle(.checkbox)
      .help("The app and every confidently matched leftover — the same set that starts selected.")
      Toggle(
        "All",
        isOn: .init(
          get: {
            guard let scan = state.scan else { return false }
            return scan.appBundleSelected && scan.items.allSatisfy(\.isSelected)
          },
          set: { on in
            state.scan?.appBundleSelected = on
            if let items = state.scan?.items {
              for index in items.indices {
                state.scan?.items[index].isSelected = on
              }
            }
          })
      )
      .toggleStyle(.checkbox)
      .help("Everything, including loosely matched items — review those before removing.")
      Text("\(scan.selectedCount) items · \(FileSize.format(scan.selectedSize))")
        .foregroundStyle(Theme.Palette.secondaryText)
        .padding(.leading, Theme.Space.md)
      Spacer()
      if state.isRemoving {
        ProgressView().controlSize(.small).padding(.trailing, Theme.Space.xs)
      }
      Button("Move to Trash…") { confirming = true }
        .keyboardShortcut(.defaultAction)
        .disabled(
          state.isRemoving || scan.selectedCount == 0
            || (scan.appBundleSelected
              && state.runningBundleIDs.contains(scan.app.bundleID)))
    }
    .padding()
    .confirmationDialog(
      "Move \(scan.selectedCount) items (\(FileSize.format(scan.selectedSize))) to the Trash?",
      isPresented: $confirming, titleVisibility: .visible
    ) {
      Button("Move to Trash", role: .destructive) {
        Task { await state.removeSelected() }
      }
    } message: {
      Text("Nothing is deleted permanently. You can restore items from the Trash.")
    }
  }

  private func abbreviatedParent(of url: URL) -> String {
    let parent = url.deletingLastPathComponent().path
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
  }

  private func sectionTitle(_ confidence: Confidence) -> String {
    switch confidence {
    case .certain: "Leftovers — certain"
    case .high: "Leftovers — high confidence"
    case .medium: "Leftovers — check these"
    case .low: "Possibly related — not selected"
    }
  }

  private func confidenceLabel(_ confidence: Confidence) -> String {
    switch confidence {
    case .certain: "certain"
    case .high: "high"
    case .medium: "check"
    case .low: "loose"
    }
  }
}
