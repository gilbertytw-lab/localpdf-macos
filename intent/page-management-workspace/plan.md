# Plan

1. 在 `Sources/LocalPDFCore/PDFWorkspace.swift` 加入批次頁面排序，為選取順序、復原與輸出加上測試。
2. 在 `Sources/LocalPDF/` 建立專用頁面管理畫面，接入多選、批次操作與原生拖放。
3. 調整編輯器入口與返回流程，移除右側零散頁面操作，保留閱讀時的縮圖導覽。
4. 執行 `make verify`、`make ui-check`，用原生滑鼠驗收拖曳與多選，檢查截圖／輸出，記錄到 `REVIEW.md`。

## 執行證據（2026-10-05）

- `PDFWorkspace.movePages` 以一次 mutation 移動不連續的選取頁，保持相對順序；核心測試驗證頁序、復原與重做。
- `PageManagementView` 在同一視窗提供專用全頁網格；原生 AppKit 縮圖表面接收滑鼠拖曳。初版 SwiftUI drag/drop 在實機未完成排序，改用原生事件後，以滑鼠把第 3 頁拖到第 1 頁，狀態顯示「已移動 1 頁」，復原可用。
- 原生介面全選 3 頁並批次旋轉，三張縮圖同時顯示 90°，復原後角度標示消失。抽取 3 頁副本後用 PDFKit 重新開啟，頁面內容順序為 3／3、1／3、2／3，與拖曳結果一致。刪除 1 頁時顯示確認視窗，頁數由 3 變 2，復原後回到 3。
- 合成 UI 場景選第 1、3 頁並移到第 2 頁後，確認多頁順序與選取索引；再測復原／重做和兩頁旋轉。截圖 `.build/ui-check/page-management.png` 已人工檢視，縮圖、工具列、選取與狀態沒有裁切或重疊。
- `make verify` 通過（37／37 測試、嚴格格式、政策檢查與 build）；`make ui-check` 通過。所有操作只用合成 PDF；來源檔保留，抽取輸出在 `.build/ui-check/native-extract-all.pdf`。未做 commit、push、簽章發布或安裝。

## 拖曳預覽增量（2026-10-05）

1. 在現有原生滑鼠拖曳狀態中加入縮小頁面預覽和多頁紅色數量標示；預覽只負責呈現，不改動放置與排序規則。
2. 檢查游標追蹤、命中目標、單頁／多頁顯示、放下或取消時清理。使用合成文件執行 `make verify`、`make ui-check` 並檢視預覽畫面。

執行結果：拖曳開始後顯示 108 × 148 pt 的頁面預覽，滑鼠移動時由 AppKit 更新位置；多頁加一張疊頁與游標右上方紅色「N 頁」。預覽不接收滑鼠命中，放下或按 Escape 會清除。目標頁未變時不重繪網格，避免每次移動都重新產生 PDF 縮圖。

合成截圖 `.build/ui-check/page-drag-single.png` 與 `.build/ui-check/page-drag-preview.png` 已檢視：單頁無數字，多頁為紅色「2 頁」，預覽尺寸小於網格頁面。原生介面以 ⌘ 選取兩頁並拖到第 3 頁，順序與選取更新，放下後預覽消失。`make verify` 37／37、`make ui-check` 與 `git diff --check` 通過；只操作 `.build` 內的合成 PDF。
