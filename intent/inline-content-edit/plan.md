# Plan

1. 在 `Sources/LocalPDF/` 加入對齊 PDF 頁面座標的單行文字編輯浮層，接入 `PDFCanvas` 事件與縮放定位。
2. 在 `DocumentController` 集中處理開始、完成、取消與失敗保留，並確保其他動作先完成草稿。
3. 調整 `EditorView` 的原有內容面板說明與控制項，加入 UI fixture 覆蓋頁面內編輯。
4. 執行 `make verify`、`make ui-check`，檢視畫面及獨立 PDF 渲染，記錄到 `REVIEW.md`。

執行結果（2026-10-05，agent 自審）：`make verify` 36 項測試通過，`make ui-check` 通過並產出 `inline-content-editing.png` 與 `edited.pdf`。UI fixture 驗證實際點選文字、改寫、復原／重做及四個旋轉角度的編輯欄座標。隔離原生 app 實測 Enter、點頁面空白處、Escape、字元限制錯誤後保留草稿、切換 Helvetica 後完成；Poppler 獨立渲染確認輸出文字已改變。尚待人類產品驗收。
