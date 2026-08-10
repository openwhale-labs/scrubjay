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
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
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
          let order = scan.items.indices.sorted {
            (scan.items[$0].item.sizeBytes ?? 0) > (scan.items[$1].item.sizeBytes ?? 0)
          }
          ForEach(order, id: \.self) { index in
            leftoverRow(index, scan: scan, state: state, showConfidence: true)
          }
        }
      } else {
        ForEach(Confidence.allCases.reversed(), id: \.self) { confidence in
          let indices = scan.items.indices.filter { scan.items[$0].item.confidence == confidence }
          if !indices.isEmpty {
            Section(sectionTitle(confidence)) {
              ForEach(indices, id: \.self) { index in
                leftoverRow(index, scan: scan, state: state, showConfidence: false)
              }
            }
          }
        }
      }
    }
  }

  private func leftoverRow(
    _ index: Int, scan: ScanResult, state: AppState, showConfidence: Bool
  ) -> some View {
    let item = scan.items[index].item
    return row(
      isOn: .init(
        get: { state.scan?.items[index].isSelected ?? false },
        set: { state.scan?.items[index].isSelected = $0 }),
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
      Toggle(
        "Select all",
        isOn: .init(
          get: {
            guard let scan = state.scan else { return false }
            return scan.appBundleSelected && scan.items.allSatisfy(\.isSelected)
          },
          set: { all in
            state.scan?.appBundleSelected = all
            if let count = state.scan?.items.count {
              for index in 0..<count {
                state.scan?.items[index].isSelected = all
              }
            }
          })
      )
      .toggleStyle(.checkbox)
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
