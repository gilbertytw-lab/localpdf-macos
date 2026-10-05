import Foundation
// swift-tools-version: 6.0
import PackageDescription

let nativeLibrary = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .appendingPathComponent(".build/deps/pdfium/lib").path

let package = Package(
  name: "LocalPDF",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "LocalPDF", targets: ["LocalPDF"]),
    .library(name: "LocalPDFCore", targets: ["LocalPDFCore"]),
  ],
  targets: [
    .target(
      name: "CPDFium",
      linkerSettings: [
        .linkedLibrary("pdfium"),
        .unsafeFlags([
          "-L", nativeLibrary,
          "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
          "-Xlinker", "-rpath", "-Xlinker", nativeLibrary,
        ]),
      ]),
    .target(name: "LocalPDFCore", dependencies: ["CPDFium"]),
    .executableTarget(name: "LocalPDF", dependencies: ["LocalPDFCore"]),
    .testTarget(name: "LocalPDFCoreTests", dependencies: ["LocalPDFCore"]),
  ],
  swiftLanguageModes: [.v6]
)
