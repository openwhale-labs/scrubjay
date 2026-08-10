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
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Text(scan.app.name).font(.title2.bold())
        if let version = scan.app.version {
          Text(version).foregroundStyle(.secondary)
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
        .foregroundStyle(.secondary)
      if scan.isAppRunning {
          Label(
            "This app is running. Quit it before uninstalling.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.callout)
          .foregroundStyle(.orange)
          .padding(.top, 4)
        }
        if scan.holdsChatHistory {
          Label(
            "This app keeps chat history on this Mac. Its data folders start unselected — back them up first if you may ever need them.",
            systemImage: "bubble.left.and.exclamationmark.bubble.right")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(.top, 4)
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
    HStack(spacing: 6) {
      Image(systemName: "shield")
      if state.helper.status == .enabled {
        Text("System-level items are removed through the ScrubJay helper.")
      } else {
        Text("System-level items need the ScrubJay helper (\(state.helper.statusDescription)).")
        Button("Enable…") {
          do {
            try state.helper.register()
          } catch {
            state.removalError = "Helper registration failed: \(error.localizedDescription)"
          }
        }
      }
    }
    .font(.callout)
    .foregroundStyle(.secondary)
    .padding(.top, 4)
  }

  private func brewHint(_ cask: String) -> some View {
    let command = "brew uninstall --cask \(cask)"
    return HStack(spacing: 6) {
      Image(systemName: "shippingbox")
      Text("Installed via Homebrew — after removal, clear its records:")
      Text(command)
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        .textSelection(.enabled)
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
      } label: {
        Image(systemName: "doc.on.doc")
      }
      .buttonStyle(.plain)
      .help("Copy command")
    }
    .font(.callout)
    .foregroundStyle(.secondary)
    .padding(.top, 4)
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
    HStack(spacing: 8) {
      Toggle("", isOn: isOn)
        .labelsHidden()
        .toggleStyle(.checkbox)
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        .resizable()
        .frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 4) {
          Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
          if let confidenceTag {
            Text(confidenceTag)
              .font(.caption2)
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.quaternary, in: Capsule())
              .foregroundStyle(.secondary)
          }
          if flagged {
            Image(systemName: "questionmark.circle")
              .foregroundStyle(.orange)
              .help("Matched by app name — double-check before removing.")
          }
          if let agent, agent.isLoaded {
            Label("active", systemImage: "bolt.fill")
              .font(.caption)
              .foregroundStyle(.orange)
              .help("Launch agent \(agent.label) is loaded; it is unloaded before removal.")
          }
          if LeftoverCatalog.isSystemPath(url) {
            Image(systemName: "shield")
              .font(.caption)
              .foregroundStyle(.secondary)
              .help("System item — removal goes through the privileged helper.")
          }
        }
        Text(abbreviatedParent(of: url))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      if let size {
        Text(FileSize.format(size))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      RevealButton(url: url)
    }
  }

  // MARK: Footer

  private func footer(_ scan: ScanResult, state: AppState) -> some View {
    HStack {
      // Deliberately leaves `low` untouched when selecting: those are weak
      // attributions and stay opt-in, one by one. Deselecting clears
      // everything.
      Toggle(
        "Select all",
        isOn: .init(
          get: {
            guard let scan = state.scan else { return false }
            return scan.appBundleSelected
              && scan.items.filter { $0.item.confidence >= .medium }.allSatisfy(\.isSelected)
          },
          set: { all in
            state.scan?.appBundleSelected = all
            if let items = state.scan?.items {
              for index in items.indices
              where all == false || items[index].item.confidence >= .medium {
                state.scan?.items[index].isSelected = all
              }
            }
          })
      )
      .toggleStyle(.checkbox)
      .help("Loosely matched items are never selected in bulk — tick them individually.")
      Text("\(scan.selectedCount) items · \(FileSize.format(scan.selectedSize))")
        .foregroundStyle(.secondary)
        .padding(.leading, 8)
      Spacer()
      Button("Move to Trash…") { confirming = true }
        .keyboardShortcut(.defaultAction)
        .disabled(scan.selectedCount == 0 || (scan.appBundleSelected && scan.isAppRunning))
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
