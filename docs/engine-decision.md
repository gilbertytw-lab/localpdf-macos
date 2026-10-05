# PDF 引擎決策草案

日期：2026-10-05。目標與正式需求見 [intent](../intent/mac-mvp/intent.md)。

| 候選 | 角色 | 決策 |
|---|---|---|
| SwiftUI／AppKit + PDFKit | Mac 原生介面、PDF 閱讀、頁面與註解 | 首版工作假設；不增加 runtime 套件 |
| Apple Vision | 裝置內 OCR | 下一階段候選，需驗證繁中／英文字元及座標 |
| qpdf | 頁面、物件、加密等結構操作 | 需要時再整合；不能單獨提供內容語意編輯 |
| MuPDF | rendering、內容解析、annotations 與真正 redaction | 原有內容編輯的 spike 候選；需使用者先選定符合產品的授權路徑 |
| PDFium | 開源內容物件解析、修改與保存 | 0.2 本地切片採用無 V8／XFA 的固定版本；Mac 顯示繼續 PDFKit |
| PDF.js + 跨平台 UI | 其他平台的 viewer 候選 | 跨平台優先時再比較 |

首版 app 程式碼採 MIT 作為可修改的起點；它依賴 macOS 系統 framework。若希望包含完全開源的 engine 並在 Linux／Windows 同步運作，原生 PDFKit 不符合這個更強的要求，須調整架構。

官方資料顯示 PDFKit 提供 PDFDocument、PDFPage、PDFSelection 與 PDFAnnotation；本機 SDK 明確提供頁面 insert／remove、rotation、annotation 與 write APIs。本版範圍由這些公開 API 與測試決定，不承諾任意原有內容改字。[Apple PDFKit](https://developer.apple.com/documentation/pdfkit)

qpdf 的官方說明定位於保持內容的結構轉換，亦指出它不理解內容 stream 的語意；授權為 Apache 2.0。[qpdf overview](https://qpdf.readthedocs.io/en/stable/overview.html)、[license](https://qpdf.readthedocs.io/en/stable/license.html)

MuPDF 官方提供 AGPL 開源或商業授權路徑；PDFPage API 含 applyRedactions，不能把普通方塊註解當成相同能力。[MuPDF license](https://mupdf.readthedocs.io/en/latest/license.html)、[PDFPage](https://mupdf.readthedocs.io/en/latest/reference/javascript/types/PDFPage.html)

Vision 的官方文字識別說明涵蓋在裝置上處理及語言選擇；實際 OCR 品質與是否能生成搜尋層仍需另做驗證。[Apple Vision](https://developer.apple.com/documentation/vision/recognizing-text-in-images)

## 原有內容編輯：0.2 本地切片

PDFium 公開 API 提供 `FPDFText_SetText`、`FPDFImageObj_SetBitmap`、物件 remove／insert-at-index、`FPDFPage_GenerateContent` 與完整非增量保存；多項 API 標為 experimental，需固定版本。[官方 headers](https://github.com/chromium/pdfium/blob/main/public/fpdf_edit.h)

使用 [pdfium-binaries chromium/8076](https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium/8076) 的非 V8 arm64 binary（156.0.8076.0，最低 macOS 13）。這是獨立社群 build，不是 Google 官方發行。固定 archive SHA-256：`0d6781fe08906baff3d82c90953e519fbc4eb253fe76431e5ed53b157763b97c`。headers 與 notices 取自同一 archive；來源與 build workflow 見 [該專案](https://github.com/bblanchon/pdfium-binaries)。依賴保留 `.build/deps/pdfium`，app 複製 dylib 至 Frameworks，無 system-wide 安裝。

PDFium 為 BSD 授權，依賴 notices 各自保留在 [pdfium-licenses](pdfium-licenses/LICENSE)。app 原始碼維持 MIT；沒有引入 AGPL 引擎或改變使用者的產品授權。

實際整頁渲染發現 ICC graphics 顏色被重建為黑色。官方 generator 的 `WriteColorToStream` 只輸出 RGB／Gray，故先透過公開 color API 解析並明確轉為 RGB；這保留數位外觀的近似顏色，失去原印刷 profile，介面明示限制。Pattern／漸層先拒絕，不假裝完整保留。[generator 原始碼](https://github.com/chromium/pdfium/blob/main/core/fpdfapi/edit/cpdf_pagecontentgenerator.cpp)

保留原字型模式只用目標原文已有的字元，避免 subset 缺 glyph；另提供 Helvetica 基本英文。Form 群組、特殊繪製／裁切、透明混合與標記暫拒絕。保存會移除頁面中的目標繪製物件，但未提供清除所有殘留資源／metadata 的 redaction 能力。

這是已經實測的窄範圍工程切片，仍需繁中 font embedding、段落重排與真實 corpus；不能外推為 Acrobat 相容。

原生整頁比對又發現特殊字距可能被 generator 改寫，故候選文件通過 CoreGraphics 外觀比對後才進入 workspace。比較忽略選取區域與容許小量渲染噪音，拒絕其他區域的明顯改動；具體門檻見 [spec](../intent/direct-content-edit/spec.md)。此檢查不能證明小字、print profile 或全部 metadata 完整保留。
