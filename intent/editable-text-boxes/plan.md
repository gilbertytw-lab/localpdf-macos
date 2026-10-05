# 實作計畫

依據：[spec.md](spec.md)。現有 feature/mac-mvp 分支持續開發，保留已 staged／unstaged 變更，不建立 commit。

1. Sources/LocalPDFCore/PDFTextBox.swift：富文字資料、RTF 序列化與 FreeText 外觀繪製。Sources/LocalPDFCore/PDFWorkspace.swift：查詢、新增／更新／刪除，以一個 mutation 保存文字框內容與位置。
2. Sources/LocalPDF/TextBoxEditor.swift：原生文字輸入、選區格式與移動／尺寸把手；Sources/LocalPDF/PDFCanvas.swift：命中與座標轉換，隔離顯示副本。
3. Sources/LocalPDF/DocumentController.swift、EditorView.swift、LocalPDFApp.swift：草稿生命週期、格式工具、文件／原生復原路由及保存保護。
4. Tests/LocalPDFCoreTests/PDFTextBoxTests.swift：混合格式、繁中、RTF 及 appearance 保存、undo/redo、幾何限制；UIFixture／ui-check 驗證原生編輯流程。make verify、make ui-check、獨立 PDF 渲染、REVIEW.md 自審。
5. README、evals 與本文件記錄結果／限制。回滾只移除本次新增文字框改動，不覆蓋原先工作。輸出均位於 .build。

風險：PDFKit 的自訂 appearance 保存、旋轉後 overlay 座標、草稿在其他操作前提交、字體／斜體 fallback；以保存重開、像素渲染與 UI 場景驗證。

## 實際證據

2026-10-05 本地完成，尚未人類產品驗收。

- `make verify`：32 項 Swift Testing 案例、strict lint、policy、build 通過，log `.build/verify-text.log`。新增富文字保存、混合格式、重開再編輯、undo／redo／刪除、CropBox／旋轉、無效草稿、容量回滾；既有內容引擎亦保留文字框資料。
- `make ui-check`：UI_CHECK_OK，原生文字框插入、選區格式、完成、undo／redo、重新開啟草稿，以及四個旋轉角度 overlay basis 檢查通過，log `.build/ui-text.log`。打包版本 0.3.0，本機 ad-hoc 簽章。
- CUA 使用獨立 `.build/LocalPDF-QA.app`／`org.localpdf.qa`，保留使用者原 `org.localpdf.dev` 視窗未儲存工作。實際點頁面→輸入／貼上繁中多行→選字粗體、斜體、底線→拖曳→未按完成另存→重開繼續編輯→22 pt／Georgia→旋轉 90° 後移動與調整大小→另存成功。另驗證藍色快捷選項與置中段落。實際視窗截圖 `.build/ui-check/native-text-box-editing.png`。
- pypdf 檢查 FreeText、AP、RTF、UUID、字體及移動前後 Rect；結果 `.build/ui-check/independent-text.json`。原生顏色副本的 Poppler 像素檢查找到 741 個藍色文字像素，且 RTF 含置中段落；輸入副本 SHA-256 保持不變。Poppler `.build/ui-check/pdf-page-1.png` 顯示繁中、粗體藍字、斜體與底線，`.build/ui-check/native-text-box-rotated.png` 顯示保存後 90° 外觀。
- Review 修正 `/NM` 遺失、格式欄位焦點與輸入框／AP 的行寬差異；結果見 [REVIEW](../../REVIEW.md)。一般快照容量測試改用便條以避免先被文字框溢位檢查攔截，另新增 rich AP 容量回滾案例。

限制：框限制在所在頁面的 CropBox；跨頁拖曳、舊 FreeText 轉換與外部 app 混合格式編輯不在本次範圍。文字框草稿不具當機復原。回復文件可取消草稿、使用 undo 或重新開啟未變動的輸入原檔；所有先前 staged／unstaged 檔案保留，未 commit／push。
