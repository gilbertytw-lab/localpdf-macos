---
id: mac-mvp
status: draft
owner: LocalPDF maintainer
risk: low-local-prototype
source: intent.md（本地未提交）
---

# Specification

來源：[intent.md](intent.md)。本規格是 agent 擬稿，尚未有人類產品批准。

## 首版行為

1. macOS 14+ 原生桌面視窗：左側頁面縮圖、中間 PDF、右側編輯工具與註解。
2. PDF 開啟、文字搜尋、縮放、縮圖導覽；顯示文件名稱、頁數、修改狀態。
3. 支援多頁選取、旋轉、前移／後移、刪除、合併及抽取；刪除最後一頁須阻擋。
4. PDF 座標點擊新增文字與便條；多行文字選取產生各行螢光標記；新增圖片產生持久化 stamp 外觀。
5. 所有 app 主動編輯經相同 mutation 入口，修改前保存快照；snapshot 最多 24 次、總量 64 MiB。單一 snapshot 超限或無法序列化時先阻擋 mutation。
6. 復原／重做恢復文件與未儲存狀態。成功另存後 undo history 清空，建立新的已保存基準。
7. 副本保存採原子寫入，先在記憶體確認輸出可由 PDFKit 重開且頁數一致。任何已開啟／合併的輸入路徑及其 symlink／hardlink 別名都不得作為輸出。
8. 抽取頁面只輸出選中頁，不修改工作文件；與編輯保存分開標示。
9. 加密／密碼文件暫阻擋，無效、無頁數、無權限、空內容有錯誤；開檔失敗保留原工作文件。保存失敗保留 dirty 狀態與 undo。
10. 使用者開啟另一份文件或關閉視窗時，遇到 dirty 狀態須確認放棄／儲存／取消；取消不做切換。
11. PDFView 使用獨立的唯讀展示副本，內建 annotation／form editor 無法改動實際 workspace。唯讀 flags 只用在展示副本，不改變輸出 PDF；頁面點擊與文字選取映射回 workspace 後才走正式 mutation 入口。外部連結開啟前確認。

## 分層

- `LocalPDFCore`：PDFKit 文件、頁面與註解操作、輸入保護、snapshot、錯誤。
- `LocalPDF`：SwiftUI 視窗、AppKit PDFView bridge、檔案 panels 與操作協調。
- SwiftPM：本地 package 與測試；不下載第三方 dependencies。
- `scripts/`：bundle 建立、SDLC policy check、app 自有 UI fixture screenshot 流程。

## 安全與品質界線

- 含憑證簽章／widget 的文件暫拒絕編輯，避免提供未驗證的保存承諾。
- 初期本機 app 未沙箱化；發行前需完成 sandbox、簽章、公證及實際文件 corpus 驗證。
- 首版不提供「安全遮蔽」或改寫原有文字的 UI，也不冒充已完成能力。新增圖片與文字可刪除、可復原。
- PDF parsing 與 snapshot 在主執行緒，大型文件效能是已知限制；後續以實測決定 worker 架構。
- 保存驗證不代表 PDF/A、PDF/UA、所有外部閱讀器或數位簽章相容性。

## 驗收

- [x] build／lint／policy check 成功。
- [x] 對合成 PDF 測試頁面序列、旋轉、註解、抽取、原檔不變、undo／redo、異常路徑。
- [x] 圖片 annotation 序列化重開後仍能 render。
- [x] 含原有文字的 PDF 在註解與頁面操作後仍可抽取文字。
- [x] app 截圖驗證 welcome 與打開文件後的編輯畫面。
- [ ] 人類試用與真實 PDF corpus：待執行，正式發布前必需。

驗證結果只記錄實際執行的命令和證據，不將結果當作人類接受。現行結果記錄在 [plan.md](plan.md)。
