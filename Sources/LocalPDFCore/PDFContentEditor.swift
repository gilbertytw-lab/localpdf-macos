import AppKit
import CPDFium
import PDFKit

public enum PDFContentKind: String, Sendable {
  case text, image, form
}

public enum PDFContentFont: String, CaseIterable, Identifiable, Sendable {
  case original = "保留原字型"
  case helvetica = "Helvetica（英文）"
  public var id: String { rawValue }
}

public struct PDFContentItem: Identifiable, Equatable, Sendable {
  public let page: Int
  public let object: Int
  public let revision: Int
  public let kind: PDFContentKind
  public let bounds: CGRect
  public let text: String
  public let restriction: String?
  public var id: String { "\(revision):\(page):\(object)" }
}

public enum PDFContentError: LocalizedError {
  case unsupported(String)
  case staleSelection, engineFailure

  public var errorDescription: String? {
    switch self {
    case .unsupported(let reason): reason
    case .staleSelection: "內容已變更，請重新選取物件。"
    case .engineFailure: "PDF 內容引擎無法完成此操作，工作文件未變更。"
    }
  }
}

// PDFium is single-threaded here. Every entry point runs on the workspace actor.
@MainActor
enum PDFContentEditor {
  private static let initialized: Bool = {
    FPDF_InitLibrary()
    return true
  }()

  private static func withPage<T>(
    _ data: Data, page index: Int, editing: Bool = false,
    _ body: (FPDF_DOCUMENT, FPDF_PAGE) throws -> T
  ) throws -> T {
    _ = initialized
    return try data.withUnsafeBytes { bytes in
      guard let document = FPDF_LoadMemDocument64(bytes.baseAddress, data.count, nil) else {
        throw PDFContentError.engineFailure
      }
      defer { FPDF_CloseDocument(document) }
      guard let page = FPDF_LoadPage(document, Int32(index)) else {
        throw PDFEditError.invalidSelection
      }
      defer { FPDF_ClosePage(page) }
      if editing, let reason = pageRestriction(data, index: index, page: page) {
        throw PDFContentError.unsupported(reason)
      }
      return try body(document, page)
    }
  }

  static func items(_ data: Data, page index: Int, revision: Int) throws -> [PDFContentItem] {
    try withPage(data, page: index) { _, page in
      let pageReason = pageRestriction(data, index: index, page: page)
      guard let textPage = FPDFText_LoadPage(page) else { throw PDFContentError.engineFailure }
      defer { FPDFText_ClosePage(textPage) }
      return (0..<FPDFPage_CountObjects(page)).compactMap { objectIndex in
        guard let object = FPDFPage_GetObject(page, objectIndex) else { return nil }
        let kind: PDFContentKind
        switch FPDFPageObj_GetType(object) {
        case FPDF_PAGEOBJ_TEXT: kind = .text
        case FPDF_PAGEOBJ_IMAGE: kind = .image
        case FPDF_PAGEOBJ_FORM: kind = .form
        default: return nil
        }
        guard let bounds = bounds(of: object) else { return nil }
        let text = kind == .text ? text(of: object, on: textPage) : ""
        return PDFContentItem(
          page: index, object: Int(objectIndex), revision: revision, kind: kind,
          bounds: bounds, text: text, restriction: pageReason ?? restriction(of: object, kind: kind)
        )
      }
    }
  }

  private static func pageRestriction(_ data: Data, index: Int, page: FPDF_PAGE) -> String? {
    for objectIndex in 0..<FPDFPage_CountObjects(page) {
      if let object = FPDFPage_GetObject(page, objectIndex),
        FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_SHADING
      {
        return "此頁含漸層繪製，本版暫不重建內容。"
      }
    }
    if let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider),
      var dictionary = pdf.page(at: index + 1)?.dictionary
    {
      // Resources can be inherited from the page tree.
      for _ in 0..<32 {
        var resources: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources {
          var patterns: CGPDFDictionaryRef?
          if CGPDFDictionaryGetDictionary(resources, "Pattern", &patterns), let patterns,
            CGPDFDictionaryGetCount(patterns) > 0
          {
            return "此頁含圖樣色彩，本版暫不重建內容。"
          }
          break
        }
        var parent: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Parent", &parent), let parent else { break }
        dictionary = parent
      }
    }
    return nil
  }

  private static func bounds(of object: FPDF_PAGEOBJECT) -> CGRect? {
    var left: Float = 0
    var bottom: Float = 0
    var right: Float = 0
    var top: Float = 0
    guard FPDFPageObj_GetBounds(object, &left, &bottom, &right, &top) != 0 else { return nil }
    return CGRect(
      x: CGFloat(left), y: CGFloat(bottom), width: CGFloat(right - left),
      height: CGFloat(top - bottom))
  }

  private static func text(of object: FPDF_PAGEOBJECT, on page: FPDF_TEXTPAGE) -> String {
    let size = FPDFTextObj_GetText(object, page, nil, 0)
    guard size >= 2, size < 2 * 1024 * 1024 else { return "" }
    var buffer = [UInt16](repeating: 0, count: Int(size) / 2)
    let written = FPDFTextObj_GetText(object, page, &buffer, size)
    guard written == size else { return "" }
    return String(decoding: buffer.dropLast(), as: UTF16.self)
  }

  private static func restriction(of object: FPDF_PAGEOBJECT, kind: PDFContentKind) -> String? {
    if kind == .form { return "這是群組／Form XObject，本版暫不展開編輯。" }
    if let clip = FPDFPageObj_GetClipPath(object), FPDFClipPath_CountPaths(clip) > 0 {
      return "這個物件含裁切路徑，本版暫不編輯。"
    }
    if FPDFPageObj_CountMarks(object) > 0 {
      return "這個物件含結構標記，本版暫不編輯。"
    }
    if FPDFPageObj_HasTransparency(object) != 0 {
      return "這個物件含透明混合效果，本版暫不編輯。"
    }
    if kind == .text, FPDFTextObj_GetTextRenderMode(object) != FPDF_TEXTRENDERMODE_FILL {
      return "這段文字使用特殊繪製模式，本版暫不編輯。"
    }
    return nil
  }

  private static func target(_ item: PDFContentItem, in page: FPDF_PAGE) throws -> FPDF_PAGEOBJECT {
    guard let object = FPDFPage_GetObject(page, Int32(item.object)),
      let box = bounds(of: object), box == item.bounds
    else { throw PDFContentError.staleSelection }
    let expected: Int32
    switch item.kind {
    case .text: expected = FPDF_PAGEOBJ_TEXT
    case .image: expected = FPDF_PAGEOBJ_IMAGE
    case .form: expected = FPDF_PAGEOBJ_FORM
    }
    guard FPDFPageObj_GetType(object) == expected else { throw PDFContentError.staleSelection }
    if let reason = restriction(of: object, kind: item.kind) {
      throw PDFContentError.unsupported(reason)
    }
    return object
  }

  private static func save(_ document: FPDF_DOCUMENT, page: FPDF_PAGE) throws -> Data {
    // PDFium's generator emits only RGB/Gray graphics colors. ICC/CMYK colors
    // otherwise fall back to black when a stream is regenerated. Resolve the
    // existing colors through PDFium and explicitly write equivalent RGB.
    for index in 0..<FPDFPage_CountObjects(page) {
      guard let object = FPDFPage_GetObject(page, index) else { continue }
      var red: UInt32 = 0
      var green: UInt32 = 0
      var blue: UInt32 = 0
      var alpha: UInt32 = 0
      if FPDFPageObj_GetFillColor(object, &red, &green, &blue, &alpha) != 0 {
        guard FPDFPageObj_SetFillColor(object, red, green, blue, alpha) != 0 else {
          throw PDFContentError.engineFailure
        }
      }
      if FPDFPageObj_GetStrokeColor(object, &red, &green, &blue, &alpha) != 0 {
        guard FPDFPageObj_SetStrokeColor(object, red, green, blue, alpha) != 0 else {
          throw PDFContentError.engineFailure
        }
      }
    }
    guard FPDFPage_GenerateContent(page) != 0 else { throw PDFContentError.engineFailure }
    var buffer: UnsafeMutablePointer<UInt8>?
    var count = 0
    guard LPDF_Save(document, &buffer, &count) != 0, let buffer else {
      throw PDFContentError.engineFailure
    }
    defer { LPDF_Free(buffer) }
    return Data(bytes: buffer, count: count)
  }

  static func replaceText(
    _ data: Data, item: PDFContentItem, text newText: String, font: PDFContentFont,
    cropBox: CGRect
  ) throws -> Data {
    guard item.kind == .text else { throw PDFEditError.invalidSelection }
    guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PDFEditError.emptyText
    }
    guard newText.utf16.count <= 4096,
      !newText.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw PDFContentError.unsupported("請使用單行文字；每個物件最多 4096 個字元。") }
    if font == .original {
      let available = Set(item.text.unicodeScalars)
      guard newText.unicodeScalars.allSatisfy({ available.contains($0) }) else {
        throw PDFContentError.unsupported("原字型可能只嵌入部分字元。目前保留原字型只允許這段原文已有的字元；英文可選 Helvetica。")
      }
    } else {
      guard newText.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) else {
        throw PDFContentError.unsupported("Helvetica 模式目前支援英文、數字與基本標點。繁中新字元的字型嵌入尚待加入。")
      }
    }
    return try withPage(data, page: item.page, editing: true) { document, page in
      let old = try target(item, in: page)
      guard let textPage = FPDFText_LoadPage(page) else { throw PDFContentError.engineFailure }
      let actualText = text(of: old, on: textPage)
      FPDFText_ClosePage(textPage)
      guard actualText == item.text else { throw PDFContentError.staleSelection }
      let object: FPDF_PAGEOBJECT
      if font == .original {
        object = old
      } else {
        var size: Float = 0
        var matrix = FS_MATRIX()
        var red: UInt32 = 0
        var green: UInt32 = 0
        var blue: UInt32 = 0
        var alpha: UInt32 = 0
        guard FPDFTextObj_GetFontSize(old, &size) != 0,
          FPDFPageObj_GetMatrix(old, &matrix) != 0,
          FPDFPageObj_GetFillColor(old, &red, &green, &blue, &alpha) != 0,
          let replacement = FPDFPageObj_NewTextObj(document, "Helvetica", size)
        else { throw PDFContentError.engineFailure }
        guard FPDFPageObj_SetMatrix(replacement, &matrix) != 0,
          FPDFPageObj_SetFillColor(replacement, red, green, blue, alpha) != 0
        else {
          FPDFPageObj_Destroy(replacement)
          throw PDFContentError.engineFailure
        }
        // Insert at the old drawing position, retaining the stacking order.
        guard FPDFPage_InsertObjectAtIndex(page, replacement, item.object) != 0 else {
          FPDFPageObj_Destroy(replacement)
          throw PDFContentError.engineFailure
        }
        guard FPDFPage_RemoveObject(page, old) != 0 else { throw PDFContentError.engineFailure }
        FPDFPageObj_Destroy(old)
        object = replacement
      }
      var encoded = Array(newText.utf16) + [0]
      guard FPDFText_SetText(object, &encoded) != 0 else { throw PDFContentError.engineFailure }
      guard let box = bounds(of: object), cropBox.insetBy(dx: -1, dy: -1).contains(box)
      else { throw PDFContentError.unsupported("修改後文字超出頁面，請縮短文字。") }
      let output = try save(document, page: page)
      let result = try items(output, page: item.page, revision: item.revision)
      guard result.contains(where: { $0.object == item.object && $0.text == newText }) else {
        throw PDFContentError.engineFailure
      }
      return output
    }
  }

  static func remove(_ data: Data, item: PDFContentItem) throws -> Data {
    try withPage(data, page: item.page, editing: true) { document, page in
      let object = try target(item, in: page)
      guard FPDFPage_RemoveObject(page, object) != 0 else { throw PDFContentError.engineFailure }
      FPDFPageObj_Destroy(object)
      return try save(document, page: page)
    }
  }

  static func replaceImage(_ data: Data, item: PDFContentItem, image: NSImage) throws -> Data {
    guard item.kind == .image else { throw PDFEditError.invalidSelection }
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      cgImage.width > 0, cgImage.height > 0, cgImage.width <= 8192, cgImage.height <= 8192,
      cgImage.width * cgImage.height <= 16 * 1024 * 1024
    else { throw PDFContentError.unsupported("請使用不超過 1600 萬像素、邊長 8192 像素的圖片。") }
    let width = cgImage.width
    let height = cgImage.height
    let rowBytes = width * 4
    var pixels = Data(count: rowBytes * height)
    return try pixels.withUnsafeMutableBytes { bytes in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue)
      else { throw PDFContentError.engineFailure }
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      let values = bytes.bindMemory(to: UInt8.self)
      // PDFium expects straight BGRA; CoreGraphics renders premultiplied BGRA.
      for offset in stride(from: 0, to: values.count, by: 4) {
        let alpha = Int(values[offset + 3])
        if alpha > 0, alpha < 255 {
          for channel in 0..<3 {
            values[offset + channel] = UInt8(min(255, Int(values[offset + channel]) * 255 / alpha))
          }
        }
      }
      return try withPage(data, page: item.page, editing: true) { document, page in
        let old = try target(item, in: page)
        var matrix = FS_MATRIX()
        guard FPDFPageObj_GetMatrix(old, &matrix) != 0,
          let replacement = FPDFPageObj_NewImageObj(document)
        else { throw PDFContentError.engineFailure }
        guard
          let bitmap = FPDFBitmap_CreateEx(
            Int32(width), Int32(height), FPDFBitmap_BGRA, bytes.baseAddress, Int32(rowBytes))
        else {
          FPDFPageObj_Destroy(replacement)
          throw PDFContentError.engineFailure
        }
        defer { FPDFBitmap_Destroy(bitmap) }
        guard FPDFImageObj_SetBitmap(nil, 0, replacement, bitmap) != 0,
          FPDFPageObj_SetMatrix(replacement, &matrix) != 0
        else {
          FPDFPageObj_Destroy(replacement)
          throw PDFContentError.engineFailure
        }
        guard FPDFPage_InsertObjectAtIndex(page, replacement, item.object) != 0 else {
          FPDFPageObj_Destroy(replacement)
          throw PDFContentError.engineFailure
        }
        guard FPDFPage_RemoveObject(page, old) != 0 else { throw PDFContentError.engineFailure }
        FPDFPageObj_Destroy(old)
        return try save(document, page: page)
      }
    }
  }
}
