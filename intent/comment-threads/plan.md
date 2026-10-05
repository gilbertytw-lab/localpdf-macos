# 實作與驗證

1. 在 `Sources/LocalPDFCore/` 新增註解討論模型與 workspace CRUD；加入多頁、儲存重開、舊式便條、復原／重做測試。
2. 在 `Sources/LocalPDF/` 加入註解草稿與側欄卡片，調整 PDFCanvas 命中及頁面重建導航。
3. 更新 `README.md`、`evals/README.md`、`scripts/check-policy.sh`、`REVIEW.md`；執行 `make verify`、`make ui-check` 並檢視 UI 圖像與第 3 頁 PDF 內容。

此變更不含協作伺服器或對其他 PDF 閱讀器的回覆互通性承諾。驗證產物在 `.build/`，原始檔保留。

## 2026-10-05 執行證據

- 已完成核心討論模型與建立、編輯、回覆、刪除、解決和舊便條升級；新增兩個回歸測試，包含第 3 頁另存重開、復原／重做及來源 byte 不變。
- 已完成側欄草稿／發布與討論卡片、跨頁清單和錨點選取；移除縮圖清單依每次修訂重建的識別，渲染副本更換後恢復目前頁面。
- `make verify`：格式、政策、34 個測試及 build 通過。`make ui-check`：合成第 3 頁註解、回覆、解決後頁碼保持 3，產生 `comment-thread.png`、`edited.pdf` 及獨立 Poppler `pdf-page-3.png`。
- 隔離 `org.localpdf.qa` 原生滑鼠操作：第 3 頁點工具、點頁面、輸入、發布、重點同一個錨點、回覆；狀態列均為第 3／3 頁，清單只有一則討論。QA 暫存文件已放棄；未改使用者原始 PDF。
