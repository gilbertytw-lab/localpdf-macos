# LocalPDF

An offline, open-source PDF editor for macOS. Organize pages, annotate documents, and edit supported text and images—all on your Mac.

Mac 優先的本地 PDF 編輯器。這是第一個可執行的開發原型，長期目標是涵蓋 Acrobat 的常用 PDF 工作；目前尚未達到 Acrobat 的完整功能。

## 執行

需求：Apple Silicon、macOS 14 以上、Xcode／Swift 6 工具鏈。首次 build 下載固定 PDFium 8076 binary（SHA-256 驗證），之後可離線 build；應用程式執行完全在本機，無後端服務。

打包的 `.app` 為 arm64 debug build，帶本機 ad-hoc 開發簽章，未取得 Developer ID 簽章或公證。macOS 14 是 deployment target，仍需相容性實機測試；此依賴鎖定目前不支援 Intel。

```sh
make run       # 打包並開啟 .build/LocalPDF.app
make verify    # 格式、SDLC 規則、PDF 回歸測試、build
make ui-check  # 啟動合成文件場景，擷取應用程式窗口至 .build/ui-check/
```

## 目前功能

- 開啟、閱讀、縮放 PDF，頁面縮圖與文字搜尋。
- 獨立「頁面管理」畫面依順序展示全頁縮圖，可多選批次旋轉、刪除、抽取，並拖曳單頁或多頁調整順序；本地復原／重做。
- 點擊頁面顯示可直接輸入的文字框，支援多行與繁中、重新編輯、拖曳移動和調整大小。
- 文字框可選本機字體、6–144 pt 字級、顏色、粗體、斜體、底線與段落對齊，選區可使用混合格式。
- 選取 PDF 文字後點「新增註解」，文字顯示紅底並以 45 度指標連到註解文字方塊；按 Enter 或點框外確認。確認後只在滑鼠移至紅底文字時顯示註解方塊。也可新增圖片與螢光標記。
- 「編輯原有內容」：點選原有文字後直接在頁面原位置修改；圖片可替換或刪除物件。保存後底層頁面內容確實變更。
- 另存 PDF 副本並驗證可重開；避免覆寫任何輸入原檔。

選「新增文字」後在頁面點一下直接輸入，拖曳框上方把手移動，右下角調整大小。選取部分文字後調整格式；沒有選字時套用整框。按「完成」或點框外會保存一次修改，編輯中 ⌘Z 復原文字，完成後 ⌘Z 復原文件。另存、切換工具／頁面前會提交草稿；取消可還原這次草稿，空的新框不保存。位置限制在目前頁面的 CropBox 內。

文字框保存為有標準 appearance 的 FreeText 註解，並附 RTF 資料供 LocalPDF 重開編輯；其他 PDF 閱讀器可顯示外觀，但其註解編輯器未必保留混合格式或 LocalPDF 再編輯資料。使用這版建立的框可再編輯；舊版一般 FreeText 註解尚未轉換。文字超出頁面允許大小時會提示縮短內容或減小字級。

先在 PDF 中拖曳選取同一頁的一段或多行文字，再點「新增註解」。註解輸入框與紅底先顯示為草稿；按 Enter 或點方塊外確認，空白草稿會取消。正式註解保存為標準紅色 Highlight，首則留言放在 PDF `/Contents`；45 度指標與浮動框是 LocalPDF 的畫面效果，其他閱讀器不保證相同呈現。舊式便條仍可開啟、閱讀及編輯，其資料不被轉換或刪除。這是離線單機註解，不含共同編輯或通知。

點工具列「頁面管理」進入專用畫面。點擊縮圖選一頁，⌘ 點擊多選，Shift 點擊選連續頁；旋轉、抽取與刪除會套用到所有選中頁。拖曳時有縮小頁面預覽跟著游標，多頁時游標右上方以紅字顯示頁數。拖到目標頁會把整組頁面依原順序移到目標前或後；批次移動可一次復原。按「返回編輯」回到 PDF 編輯畫布。

修改既有文字請使用「編輯原有內容」，點選頁面文字即可在原位置輸入，按 Enter 或點頁面其他位置套用，按 Esc 取消。切換工具、換頁與另存前也會先嘗試套用；失敗時保留草稿供修正。每次處理一個頂層 PDF 物件，不自動重排段落。保留原字型時僅允許選取原文已有的字元；改用 Helvetica 可輸入英文、數字與基本標點。修改原有內容時，繁中新字元的字型嵌入尚未完成；新增文字框已支援繁中。

替換原圖維持原矩陣／位置／大小，可使用透明 PNG，僅改選取的出現位置。Form 群組、裁切、結構標記、特殊文字繪製、透明混合效果的原物件，以及含漸層／圖樣的頁面暫拒絕。物件清單顯示前 200 個，其他物件可在頁面點選。

編輯頁的文字與線條色彩轉為 RGB；不保留原有 ICC／CMYK 印刷色彩描述，介面會提示。內容刪除沒有安全遮蔽承諾。加密文件、widget／簽章欄位暫不支援編輯；OCR、表單、憑證數位簽章與格式轉換仍在工作清單。

保存進 workspace 前會以最長邊 1024 px 比對編輯頁面：選取區域以外若有明顯外觀差異，整次修改拒絕。這可攔截特殊字距被重建的問題；不是印刷精度或所有微小差異的保證。

## 設計與工作流程

- [需求](intent/mac-mvp/intent.md)、[規格](intent/mac-mvp/spec.md)、[實作計畫](intent/mac-mvp/plan.md)
- [原有內容編輯需求與驗收](intent/direct-content-edit/plan.md)
- [頁面內編輯原有文字需求與驗收](intent/inline-content-edit/plan.md)
- [獨立頁面管理需求與驗收](intent/page-management-workspace/plan.md)
- [可編輯文字框需求與驗收](intent/editable-text-boxes/plan.md)
- [前版便條討論（歷史紀錄）](intent/comment-threads/plan.md)
- [選字註解需求與驗收](intent/selected-text-comments/plan.md)
- [現行工作清單與產品路線](docs/roadmap.md)
- [引擎選擇與授權來源](docs/engine-decision.md)
- [風險與發布規則](docs/risk-policy.md)、[Review 規則](REVIEW.md)、[代表性驗收案例](evals/README.md)

app 原始碼以 MIT 授權提供。PDFKit 是 macOS 系統 framework；PDFium 與其依賴使用各自授權，完整 notices 在 [pdfium-licenses](docs/pdfium-licenses/LICENSE) 並隨 app 打包。原始碼公開於 [GitHub](https://github.com/gilbertytw-lab/localpdf-macos)；目前仍是開發原型，尚未發行經 Developer ID 簽章及公證的 app。

## 檔案與復原

原檔保留在使用者選擇的位置；編輯狀態留在記憶體。復原快照最多 24 次且總量限制 64 MiB，特別大的文件可能無法編輯，UI 會顯示原因。關閉前提示未儲存變更。此版沒有當機復原或自動儲存。

測試 fixture 在執行時合成，輸出與截圖只放 `.build/`。離屏 `editor-chrome.png` 僅驗證 UI 佈局，PDFKit 的繪圖層需要實際視窗截圖確認；有 Poppler 時 `make ui-check` 另產生獨立 PDF render。之後大型驗收資料使用 `LOCALPDF_DATA_DIR`（預設 `~/Data/local-pdf`）。回到原始 PDF 狀態的方法是重新開啟未變動的輸入檔；程式碼歷史由 Git commit 保留，回復前先檢查本地未提交變更。
