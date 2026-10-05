---
id: direct-content-edit
status: draft
owner: LocalPDF maintainer
risk: low-local-prototype
---

# Implementation plan

依 [intent.md](intent.md)、[spec.md](spec.md) 連續本地開發，不新增外部操作。

計畫路徑：`Sources/CPDFium/`（官方 headers／小型 C bridge）、`Sources/LocalPDFCore/`（內容物件 API）、`Sources/LocalPDF/`（選取與 inspector）、`Tests/LocalPDFCoreTests/`（内容編輯 round trip）、`scripts/`（固定依賴準備／QA）、`Package.swift`、`Makefile`、`README.md`、`REVIEW.md`、`docs/`、`evals/`、`intent/`。

1. 核對 PDFium API、固定 binary 與授權；依賴準備可重跑，無 system-wide 安裝。
2. 加入內容引擎、字型限制、物件選取與候選文件原子替換；保持原快照與輸入防護。加入有界的編輯頁外觀比對，拒絕選取區域以外的明顯差異。
3. 原生編輯模式與 inspector，明確區分原內容與新增註解。
4. 合成 PDF 測試文字、圖片、共用資源、旋轉／裁切、拒絕路徑、混用註解和 undo。
5. `make verify`、`make ui-check`、獨立 PDF extraction／render 與原生 UI。記錄實際結果、限制與 review。

主要風險：PDFium 多項 API 為 experimental，固定版本降低漂移；保留原字型的字元集合採保守限制。不能將不再繪製的資源視為機密資料已清除。主執行緒与完整保存的效能仍待真實 corpus 評估。

## 證據

2026-10-05 本地執行（agent 自檢，不等同人類批准）：

- `make verify`：format lint、artifact／planned-path／offline policy、26 個測試（另含 2 個 shading／Pattern 參數案例）與 build 全部成功。輸出 `.build/verify-direct.log`。
- `make ui-check`：0.2 app 打包、plist lint、ad-hoc signature 驗證、welcome／內容 inspector 截圖、原文／原圖替換與副本輸出成功，日誌 `.build/ui-direct.log`。`.build/ui-check/edited.pdf` 包含新標題 `Edit your original PDF.`、藍色圖片和新增註解。離屏 `editor-chrome.png` 僅驗證介面佈局；PDFKit canvas tile layer 另以 PDF renderer 確認。
- 動態載入：`DYLD_PRINT_LIBRARIES=1` 執行相同 UI fixture，確認載入的是 app `Contents/Frameworks/libpdfium.dylib`，成功。證據 `.build/dyld-ui.log`；不是依靠 Codex runtime 或別的專案環境。
- 獨立 pypdf 解析：新文字可抽取、目標舊文不再呈現、原便條保留；藍色 replacement Image stream 僅在選取位置繪製，另外兩個共用出現位置仍為紅色；刪除後 page draw objects 減少。UI 輸出的第 2、3 頁原文字不變，沒有展示用 `/Square` 選取框。證據 `.build/independent-direct.json`。
- Poppler 渲染與人工圖像檢視：`content-image.png` 可見藍／紅圖片；`content-alpha.png` 上藍下綠、半邊透明；`pdf-page-1.png` 可見新文字、藍圖、白底與保留內容。相應 PDF 在 `.build/test-evidence/` 與 `.build/ui-check/`；PDFKit 原生 thumbnail 的方向／alpha／色彩 regression 也通過。
- 原生實際點選：CUA 回報 Mac 鎖定，已請使用者解鎖，尚未得到解鎖回覆。本次沒有宣稱完成實際滑鼠點選、面板另存驗收；自有 UI fixture 路徑已成功。
- 28 個本地 Markdown 連結、license symlink 與 `git diff --check` 通過。上游 libjpeg notice 的 `README.ijg` 引用以 symlink 指向唯一的 `libjpeg_turbo.ijg` 來源，打包包含相應 notice。原檔 byte、防止別名覆寫、dirty／undo／失敗狀態由原有與新增回歸覆蓋。

## Review 與修正

1. **Important／資料結構**：反覆 PDFKit 序列化會 flatten Form 並改變物件索引。保留原始／候選 bytes 作正式內容，普通 PDFKit mutation 後才重新序列化。內容操作用 revision＋物件 bounds／原文檢查，過期 token 拒絕。
2. **Blocker／外觀**：ICC 色彩在 generator 中變黑。改為明示的 RGB 轉換，增加白底／彩色 path regression，拒絕 Pattern／漸層頁面。仍不承諾原印刷 profile。
3. **Blocker／版面**：重建會改寫未選取文字的 tracking。加 CoreGraphics 有界 pixel 比對，候選外部區域明顯變化就拒絕；6 pt tracking fixture 驗證 workspace 身分、revision、dirty、undo 不變。UI 合成文件使用明確零字距 Helvetica。
4. **Important／打包**：直接複製 SwiftPM binary 的 signature 不涵蓋新增 bundle resources，app 被系統終止。改為原子換檔、完整本機 ad-hoc signature 與 verify；沒有 Developer ID、公證或發布。
5. **測試限制**：AppKit HDR／色彩管理的通道值不等於純 RGB 常數，圖片 assertions 用顏色優勢並以獨立 Poppler 檢視交叉確認。NSImage 的 Retina bitmap 解析度也可能高於 logical size，驗收以顯示矩陣／實際像素為準。

仍待：Mac 解鎖後實際點選驗收、繁中新字元字型嵌入、保留完整 kerning／profiles 的引擎路徑、真實 corpus、大文件效能、人類產品接受。程式與 artifacts 留在原本的本地 Git branch，不 commit／push。回復資料可用 undo 或重新開啟不變的輸入原檔；新依賴與所有輸出可由 `.build` 重建。
