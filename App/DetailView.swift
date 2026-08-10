import ScrubJayKit
import SwiftUI

struct DetailView: View {
  @Environment(AppState.self) private var state
  @State private var confirming = false

  var body: some View {
    @Bindable var state = state
    if let scan = state.scan {
      VStack(spacing: 0) {
        header(scan)
        Divider()
        checklist(scan: scan, state: state)
        Divider()
        footer(scan)
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

  private func header(_ scan: ScanResult) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Text(scan.app.name).font(.title2.bold())
        if let version = scan.app.version {
          Text(version).foregroundStyle(.secondary)
        }
      }
      Text(scan.app.bundleID)
        .font(.callout)
        .foregroundStyle(.secondary)
      if scan.isAppRunning {
        Label("This app is running. Quit it before uninstalling.", systemImage: "exclamationmark.triangle")
          .font(.callout)
          .foregroundStyle(.orange)
          .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }

  private func checklist(scan: ScanResult, state: AppState) -> some View {
    @Bindable var state = state
    return List {
      Section("Application") {
        Toggle(isOn: .init(
          get: { state.scan?.appBundleSelected ?? false },
          set: { state.scan?.appBundleSelected = $0 })
        ) {
          itemLabel(
            path: scan.app.bundleURL.path, size: scan.appBundleSize, flagged: false)
        }
      }
      ForEach(Confidence.allCases.reversed(), id: \.self) { confidence in
        let indices = scan.items.indices.filter { scan.items[$0].item.confidence == confidence }
        if !indices.isEmpty {
          Section(sectionTitle(confidence)) {
            ForEach(indices, id: \.self) { index in
              Toggle(isOn: .init(
                get: { state.scan?.items[index].isSelected ?? false },
                set: { state.scan?.items[index].isSelected = $0 })
              ) {
                itemLabel(
                  path: scan.items[index].item.url.path,
                  size: scan.items[index].item.sizeBytes,
                  flagged: confidence == .medium)
              }
            }
          }
        }
      }
    }
    .toggleStyle(.checkbox)
  }

  private func footer(_ scan: ScanResult) -> some View {
    HStack {
      Text("\(scan.selectedCount) items selected · \(FileSize.format(scan.selectedSize))")
        .foregroundStyle(.secondary)
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

  private func itemLabel(path: String, size: Int64?, flagged: Bool) -> some View {
    HStack {
      Text(path).lineLimit(1).truncationMode(.middle)
      if flagged {
        Image(systemName: "questionmark.circle")
          .foregroundStyle(.orange)
          .help("Matched by app name — double-check before removing.")
      }
      Spacer()
      if let size {
        Text(FileSize.format(size))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
  }

  private func sectionTitle(_ confidence: Confidence) -> String {
    switch confidence {
    case .certain: "Leftovers — certain"
    case .high: "Leftovers — high confidence"
    case .medium: "Leftovers — check these"
    case .low: "Possibly related — not selected"
    }
  }
}
