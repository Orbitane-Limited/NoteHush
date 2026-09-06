import AppKit

@MainActor
final class WorkspacePrinter: NSObject {
  private lazy var printInfo = WorkspacePrinter.defaultPrintInfo()
  private var operation: NSPrintOperation?
  private var pageLayout: NSPageLayout?
  private weak var parentWindow: NSWindow?
  var isPresenting: Bool { operation != nil || pageLayout != nil }
  var onFailure: (() -> Void)?

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(sheetBecameKey(_:)), name: NSWindow.didBecomeKeyNotification,
      object: nil)
  }

  static func defaultPrintInfo() -> NSPrintInfo {
    let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
    info.topMargin = 36
    info.bottomMargin = 36
    info.leftMargin = 36
    info.rightMargin = 36
    info.isHorizontallyCentered = false
    info.isVerticallyCentered = false
    info.horizontalPagination = .automatic
    info.verticalPagination = .automatic
    return info
  }

  func showPageSetup(on window: NSWindow) {
    guard !isPresenting, window.attachedSheet == nil else { return }
    parentWindow = window
    let panel = NSPageLayout()
    pageLayout = panel
    guard let proposed = printInfo.copy() as? NSPrintInfo else {
      pageLayout = nil
      return
    }
    panel.beginSheet(using: proposed, on: window) { [weak self] result in
      guard let self else { return }
      if result == .changed { printInfo = proposed }
      pageLayout = nil
    }
    window.attachedSheet?.preventsApplicationTerminationWhenModal = false
  }

  func printText(_ text: String, font: NSFont, title: String, on window: NSWindow) {
    guard !isPresenting, window.attachedSheet == nil else { return }
    parentWindow = window
    let view = PrintDocumentView(text: text, font: font)
    do { try view.paginate(using: printInfo) } catch {
      onFailure?()
      return
    }
    let operation = NSPrintOperation(view: view, printInfo: printInfo)
    operation.jobTitle = title
    operation.printPanel.options.formUnion([
      .showsPaperSize, .showsOrientation, .showsScaling, .showsPreview,
    ])
    self.operation = operation
    // AppKit view/layout work stays on the main actor. The native panel owns job delivery.
    operation.runModal(
      for: window, delegate: self, didRun: #selector(printFinished(_:success:contextInfo:)),
      contextInfo: nil)
    window.attachedSheet?.preventsApplicationTerminationWhenModal = false
  }

  @objc private func printFinished(
    _ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
  ) {
    if (operation.view as? PrintDocumentView)?.paginationFailed == true { onFailure?() }
    self.operation = nil
  }

  @objc private func sheetBecameKey(_ notification: Notification) {
    guard isPresenting, let sheet = notification.object as? NSWindow else { return }
    var ancestor = sheet.sheetParent
    while let current = ancestor {
      if current === parentWindow {
        sheet.preventsApplicationTerminationWhenModal = false
        return
      }
      ancestor = current.sheetParent
    }
  }

  func cancelSheets(on window: NSWindow?) {
    guard isPresenting, let window else { return }
    dismissSheets(on: window)
  }

  private func dismissSheets(on window: NSWindow) {
    for sheet in window.sheets {
      dismissSheets(on: sheet)
      window.endSheet(sheet, returnCode: .cancel)
      sheet.orderOut(nil)
    }
  }
}
