# LocalPDF

- 任務需求的正式來源是 `intent/<change-id>/intent.md`，技術規格與順序分別是同目錄的 `spec.md`、`plan.md`；先讀再修改程式。
- 原始 PDF 預設唯讀；輸出到新的路徑。任何破壞性編輯都必須可復原，不能把視覺遮蓋宣稱為安全遮蔽。
- 應用程式離線運作，不加入文件上傳、遙測或遠端字型。
- 本地原型可依任務授權連續開發與驗證；人類未確認的產品決策標成假設。發布、簽章、公證、commit、push、PR 與 remote 設定需有當次明確授權。
- 以 `make verify` 驗證；UI 變更另執行 `make ui-check` 並人工／工具檢視截圖。依 `REVIEW.md` 留下結果。
- 生成應用程式、測試輸出放 `.build/`；其他生成資料放環境變數 `LOCALPDF_DATA_DIR`，預設 `~/Data/local-pdf`。不依賴其他專案 runtime。
