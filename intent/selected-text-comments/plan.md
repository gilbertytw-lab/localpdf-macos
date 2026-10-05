# 實作與驗證

1. 擴充 `Sources/LocalPDFCore/PDFComment.swift` 與 `PDFWorkspace.swift`，新增選字錨點及紅底 Highlight 儲存，同時維持舊式 Text 註解讀取和討論資料。
2. 修改 `Sources/LocalPDF/DocumentController.swift`、`PDFCanvas.swift`、`EditorView.swift`，新增選區啟動、暫時高亮、45 度浮動框、Enter／框外確認及 hover 顯示。
3. 加入多頁選字、保存重開、復原／重做、無效選區測試，更新 `UIFixture.swift`、`README.md`、`evals/README.md`、`REVIEW.md`、`scripts/check-policy.sh`；跑 `make verify`、`make ui-check`，檢視畫面與輸出 PDF。

避免改動既有未提交工作。測試產物留 `.build/`；不 commit、不發布。

## 2026-10-05 執行證據

- Core：同頁多行矩形與紅色 Highlight、標準 `/Contents`、穩定 ID 和討論中繼資料可另存重開；復原／重做與來源 byte 不變。舊版無錨點的 Text 討論資料仍可讀、可編輯。
- UI：按鈕改名「新增註解」；有文字選區才進入草稿。斜指標兩軸位移相等（45 度），輸入框 Enter／點外確認；提交後隱藏，滑鼠進入紅底文字顯示、離開隱藏。頁面重繪後重算位置。
- `make verify`：格式、政策、36 個測試及 build 通過。`make ui-check`：產生 `comment-draft.png`、`comment-hover.png`、`comment-hidden.png`、`edited.pdf`、`pdf-page-3.png`，第 3 頁位置維持不變；Poppler 獨立渲染確認紅底。
- 隔離 `org.localpdf.hoverqa` 的原生滑鼠／鍵盤驗收：未選文字顯示錯誤；第 3 頁拖曳選字、點工具、輸入 Enter、移入／移出紅底文字，以及另一段文字點方塊外確認均成功。原始合成 PDF 未寫入，QA 暫存修改已放棄。
