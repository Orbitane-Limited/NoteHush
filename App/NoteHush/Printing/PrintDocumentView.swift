import AppKit

/// An immutable plain-text print snapshot. TextKit flows complete line fragments
/// through page-sized containers; editor wrap, zoom, colors and undo are untouched.
@MainActor
final class PrintDocumentView: NSView {
  private let storage: NSTextStorage
  private let layout = NSLayoutManager()
  private let minimumLineHeight: CGFloat
  private var pageSize = NSSize.zero
  private(set) var pageCount = 0
  private(set) var paginationFailed = false
  override var isFlipped: Bool { true }

  init(text: String, font: NSFont) {
    minimumLineHeight = max(1, font.ascender - font.descender + font.leading)
    storage = NSTextStorage(
      string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
    super.init(frame: .zero)
    appearance = NSAppearance(named: .aqua)
    storage.addLayoutManager(layout)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  enum PaginationError: Error { case pageTooSmall }

  func paginate(using info: NSPrintInfo) throws {
    let scale = info.scalingFactor
    guard scale.isFinite, scale > 0 else {
      paginationFailed = true
      pageCount = 0
      throw PaginationError.pageTooSmall
    }
    let imageable = info.imageablePageBounds
    let left = max(info.leftMargin, imageable.minX)
    let right = max(info.rightMargin, info.paperSize.width - imageable.maxX)
    let top = max(info.topMargin, info.paperSize.height - imageable.maxY)
    let bottom = max(info.bottomMargin, imageable.minY)
    info.leftMargin = left
    info.rightMargin = right
    info.topMargin = top
    info.bottomMargin = bottom
    let next = NSSize(
      width: (info.paperSize.width - left - right) / scale,
      height: (info.paperSize.height - top - bottom) / scale)
    guard next.width.isFinite, next.height.isFinite, next.width > 0,
      next.height >= minimumLineHeight
    else {
      paginationFailed = true
      pageCount = 0
      throw PaginationError.pageTooSmall
    }
    guard pageSize != next || pageCount == 0 else { return }
    pageSize = next
    pageCount = 0
    paginationFailed = false
    while !layout.textContainers.isEmpty { layout.removeTextContainer(at: 0) }
    var end = 0
    repeat {
      let container = NSTextContainer(containerSize: pageSize)
      container.lineFragmentPadding = 0
      layout.addTextContainer(container)
      let range = layout.glyphRange(for: container)
      let used = layout.usedRect(for: container)
      guard used.maxX <= pageSize.width + 0.5, used.maxY <= pageSize.height + 0.5 else {
        paginationFailed = true
        throw PaginationError.pageTooSmall
      }
      let nextEnd = NSMaxRange(range)
      // Guarantees termination if a pathological font cannot fit even one glyph.
      if nextEnd == end && end < layout.numberOfGlyphs {
        paginationFailed = true
        throw PaginationError.pageTooSmall
      }
      end = nextEnd
    } while end < layout.numberOfGlyphs
    pageCount = layout.textContainers.count
    setFrameSize(NSSize(width: pageSize.width, height: pageSize.height * CGFloat(pageCount)))
  }

  override func knowsPageRange(_ range: NSRangePointer) -> Bool {
    guard let info = NSPrintOperation.current?.printInfo else { return false }
    do { try paginate(using: info) } catch {
      range.pointee = NSRange(location: 1, length: 0)
      return true
    }
    range.pointee = NSRange(location: 1, length: pageCount)
    return true
  }

  override func rectForPage(_ page: Int) -> NSRect {
    NSRect(
      x: 0, y: CGFloat(page - 1) * pageSize.height, width: pageSize.width, height: pageSize.height)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.setFill()
    dirtyRect.fill()
    for (index, container) in layout.textContainers.enumerated() {
      let rect = rectForPage(index + 1)
      guard rect.intersects(dirtyRect) else { continue }
      let range = layout.glyphRange(for: container)
      layout.drawBackground(forGlyphRange: range, at: rect.origin)
      layout.drawGlyphs(forGlyphRange: range, at: rect.origin)
    }
  }
}
