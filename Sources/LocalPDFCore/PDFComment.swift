import Foundation
import PDFKit

public struct PDFCommentReply: Codable, Identifiable, Equatable {
  public let id: String
  public var author: String
  public var createdAt: Date
  public var text: String

  public init(
    id: String = UUID().uuidString, author: String = "我", createdAt: Date = .now,
    text: String
  ) {
    self.id = id
    self.author = author
    self.createdAt = createdAt
    self.text = text
  }
}

public struct PDFComment: Identifiable, Equatable {
  public let id: String
  public let page: Int
  public let bounds: CGRect
  public var author: String
  public var createdAt: Date
  public var text: String
  public var replies: [PDFCommentReply]
  public var resolved: Bool
  public var anchorRects: [CGRect]

  public var isTextAnchor: Bool { !anchorRects.isEmpty }

  public init(
    id: String, page: Int, bounds: CGRect, author: String, createdAt: Date,
    text: String, replies: [PDFCommentReply] = [], resolved: Bool = false,
    anchorRects: [CGRect] = []
  ) {
    self.id = id
    self.page = page
    self.bounds = bounds
    self.author = author
    self.createdAt = createdAt
    self.text = text
    self.replies = replies
    self.resolved = resolved
    self.anchorRects = anchorRects
  }
}

struct PDFCommentThread: Codable {
  let version: Int
  let id: String
  let createdAt: Date
  var replies: [PDFCommentReply]
  var resolved: Bool
  var anchorRects: [CGRect]? = nil

  static let key = PDFAnnotationKey(rawValue: "/LocalPDFCommentThread")

  static func decode(_ annotation: PDFAnnotation) -> PDFCommentThread? {
    guard let raw = annotation.value(forAnnotationKey: key) as? String,
      let data = raw.data(using: .utf8),
      let thread = try? JSONDecoder().decode(PDFCommentThread.self, from: data),
      thread.version == 1
    else { return nil }
    return thread
  }

  func encoded() throws -> String {
    let data = try JSONEncoder().encode(self)
    guard data.count <= 128 * 1024, let raw = String(data: data, encoding: .utf8) else {
      throw PDFEditError.commentTooLong
    }
    return raw
  }
}
