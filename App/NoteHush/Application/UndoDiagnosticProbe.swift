#if DEBUG && NOTEHUSH_REQUIRE_TEST_WORKSPACE
  import AppKit
  import Darwin

  /// Opt-in evidence for isolated native input, never a shipping logger.
  /// No event is consumed or changed. No typed character or key code is retained.
  @MainActor
  final class UndoDiagnosticProbe: NSObject {
    private enum Event: String, Codable, Sendable {
      case installed, commandZ, nextMainQueueTurn, willUndo, didUndo
      case becameActive, resignedActive, shutdownRequested, limitReached
      case nextTab, previousTab, otherKey
    }

    private enum FixtureState: String, Codable, Sendable {
      case noEditor, original, singleFirst, singleLast, caseSensitiveAll, caseInsensitiveAll, other
    }

    private struct Record: Codable, Sendable {
      let sequence: Int
      let elapsedSeconds: Double
      let event: Event
      let applicationActive: Bool
      let workspaceKey: Bool
      let editorFirstResponder: Bool
      let firstResponderIsFieldEditor: Bool
      let editorCanUndo: Bool
      let editorIsUndoing: Bool
      let notificationFromEditor: Bool?
      let fixtureState: FixtureState
      let keyEventIsRepeat: Bool?
      let keyEventTargetsWorkspace: Bool?
      let keyEventSourceProcessID: Int32?
    }

    private weak var workspace: WorkspaceWindowController?
    private var monitor: Any?
    private let writer: Writer
    private let started = ContinuousClock.now
    private var sequence = 0
    private var lastWrite: Task<Void, Never>?
    private var stopped = false

    static func installIfEnabled(
      workspace: WorkspaceWindowController, directory: URL
    ) -> UndoDiagnosticProbe? {
      guard ProcessInfo.processInfo.environment["NOTEHUSH_UNDO_DIAGNOSTICS"] == "1",
        Bundle.main.bundleIdentifier == "pk.codehub.NoteHush.UITesting",
        let value = ProcessInfo.processInfo.environment["NOTEHUSH_TEST_WORKSPACE"],
        let identifier = UUID(uuidString: value),
        directory.lastPathComponent == identifier.uuidString,
        directory.deletingLastPathComponent().lastPathComponent == "UITests"
      else { return nil }
      return UndoDiagnosticProbe(workspace: workspace, directory: directory)
    }

    private init(workspace: WorkspaceWindowController, directory: URL) {
      self.workspace = workspace
      writer = Writer(directory: directory)
      super.init()
      // AppKit dispatches local event monitors on the application's main thread.
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        MainActor.assumeIsolated {
          let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
          if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "z" {
            self?.record(.commandZ, keyEvent: event)
            // A queue turn does not guarantee nested event processing or display has finished.
            DispatchQueue.main.async { [weak self] in self?.record(.nextMainQueueTurn) }
          } else if modifiers == .control || modifiers == [.control, .shift],
            event.charactersIgnoringModifiers == "\t"
              || event.charactersIgnoringModifiers == "\u{19}"
          {
            self?.record(modifiers == .control ? .nextTab : .previousTab, keyEvent: event)
          } else {
            // "Other" deliberately does not identify letters, key codes or payloads.
            self?.record(.otherKey, keyEvent: event)
          }
        }
        return event
      }
      let center = NotificationCenter.default
      center.addObserver(
        self, selector: #selector(willUndo(_:)), name: .NSUndoManagerWillUndoChange, object: nil)
      center.addObserver(
        self, selector: #selector(didUndo(_:)), name: .NSUndoManagerDidUndoChange, object: nil)
      center.addObserver(
        self, selector: #selector(becameActive),
        name: NSApplication.didBecomeActiveNotification, object: NSApp)
      center.addObserver(
        self, selector: #selector(resignedActive),
        name: NSApplication.didResignActiveNotification, object: NSApp)
      record(.installed)
    }

    @objc private func willUndo(_ notification: Notification) {
      record(.willUndo, manager: notification.object as? UndoManager)
    }

    @objc private func didUndo(_ notification: Notification) {
      record(.didUndo, manager: notification.object as? UndoManager)
    }

    @objc private func becameActive() { record(.becameActive) }
    @objc private func resignedActive() { record(.resignedActive) }

    private func record(_ event: Event, manager: UndoManager? = nil, keyEvent: NSEvent? = nil) {
      guard !stopped, sequence < 256 else { return }
      let tab = workspace?.selectedTab
      let editor = tab?.editor
      let history = tab.flatMap { $0.undoManager(for: $0.editor) }
      let window = workspace?.window
      let sourceProcessID = keyEvent?.cgEvent.flatMap { event -> Int32? in
        let raw = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard let identifier = Int32(exactly: raw), identifier >= 0 else { return nil }
        return identifier
      }
      let elapsed = started.duration(to: .now).components
      let value = Record(
        sequence: sequence,
        elapsedSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
        event: sequence == 255 ? .limitReached : event,
        applicationActive: NSApp.isActive,
        workspaceKey: window?.isKeyWindow == true,
        editorFirstResponder: editor != nil && window?.firstResponder === editor,
        firstResponderIsFieldEditor: (window?.firstResponder as? NSTextView)?.isFieldEditor == true,
        editorCanUndo: history?.canUndo == true,
        editorIsUndoing: history?.isUndoing == true,
        notificationFromEditor: manager.map { $0 === history },
        fixtureState: fixtureState(editor),
        keyEventIsRepeat: keyEvent.map(\.isARepeat),
        keyEventTargetsWorkspace: keyEvent.map { window != nil && $0.window === window },
        keyEventSourceProcessID: sourceProcessID)
      sequence += 1
      let previous = lastWrite
      let writer = writer
      // Preserve observation order and keep diagnostic I/O off the main actor.
      // The fixed cap also bounds pending tasks and retained evidence.
      lastWrite = Task {
        await previous?.value
        await writer.append(value)
      }
    }

    private func fixtureState(_ editor: NSTextView?) -> FixtureState {
      guard let editor else { return .noEditor }
      // Compare only the bounded, published test oracle. Unexpected text is
      // classified as "other" and is never emitted, hashed or persisted here.
      guard (editor.textStorage?.length ?? 0) <= 128 else { return .other }
      let text = editor.string
      let original = "café CAFÉ café\r\n👩🏽‍💻 second\nlast"
      let candidates: [(FixtureState, String)] = [
        (.original, original),
        (.singleFirst, "tea CAFÉ café\r\n👩🏽‍💻 second\nlast"),
        (.singleLast, "café CAFÉ tea\r\n👩🏽‍💻 second\nlast"),
        (.caseSensitiveAll, "tea CAFÉ tea\r\n👩🏽‍💻 second\nlast"),
        (.caseInsensitiveAll, "tea tea tea\r\n👩🏽‍💻 second\nlast"),
      ]
      return candidates.first { text.utf8.elementsEqual($0.1.utf8) }?.0 ?? .other
    }

    func finish() async {
      guard !stopped else { return }
      record(.shutdownRequested)
      stopped = true
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      NotificationCenter.default.removeObserver(self)
      await lastWrite?.value
      await writer.finish()
    }

    private actor Writer {
      private let directory: URL
      private let filename = "undo-diagnostic-\(UUID().uuidString).jsonl"
      private var handle: FileHandle?
      private var failed = false

      init(directory: URL) { self.directory = directory }

      func append(_ value: Record) {
        guard !failed else { return }
        do {
          if handle == nil {
            try FileManager.default.createDirectory(
              at: directory, withIntermediateDirectories: true,
              attributes: [.posixPermissions: 0o700])
            // A fresh per-launch file must never truncate prior diagnostic evidence.
            let descriptor = open(
              directory.appending(path: filename).path,
              O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
            handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
          }
          var data = try JSONEncoder().encode(value)
          data.append(0x0A)
          guard let handle else { throw CocoaError(.fileWriteUnknown) }
          try handle.write(contentsOf: data)
        } catch { reportFailure() }
      }

      func finish() {
        do {
          try handle?.synchronize()
          try handle?.close()
          handle = nil
        } catch { reportFailure() }
      }

      private func reportFailure() {
        guard !failed else { return }
        failed = true
        // Never format the Error: it can contain a filesystem path.
        try? FileHandle.standardError.write(
          contentsOf: Data("NoteHush isolated undo diagnostic write failed\n".utf8))
      }
    }
  }
#endif
