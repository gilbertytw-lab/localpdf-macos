# Review

每次變更對照其 intent／spec／plan；留實際 finding、修正與證據，agent review 不代表人類 approve。

- Bugs：頁面順序、頁索引、座標、rotation、selection、undo／redo／dirty；錯誤時工作文件保持可用。
- Data：原檔 byte 是否不變；symlink／hardlink、merge input、儲存失敗與加密／簽章不被靜默處理。
- Security／privacy：沒有上傳／遙測／遠端字型；不執行 PDF script；外部連結先詢問；視覺方塊不被宣稱為 redaction。
- Scope：可見功能與測試一致，未完成能力清楚列工作清單；授權假設不被當成人類批准。
- Rollback：保留原檔、限制記憶體快照、失敗不覆寫；正式發布另做已簽章版本 rollback。
- Content engine：字型範圍、原物件／共用資源、rotation／CropBox、未選取區域外觀；RGB 轉換提示、拒絕未支援繪製。引擎與 headers 固定版本、checksum、完整 notices 與 bundle 動態載入。

Blocker：資料破壞、原檔覆寫、錯誤安全宣稱、未授權發布。Important：可用性或相容性缺陷。Nit：只報影響理解的維護問題。忽略生成 `.build` 與已由 deterministic check 覆蓋的樣式細节。

## editable-text-boxes：2026-10-05 agent 自審

- Important／已修正：PDFKit 保存會移除 `/NM`，改用可往返的 `/LocalPDFID`；保存重開、undo／redo 和原有內容引擎編輯均驗證保留。
- Important／已修正：字級輸入不應把焦點提前移回畫布；保留字級欄位焦點，實際輸入 22 pt 後文字內容不變。文字框已設獨立原生 UndoManager，文件操作先提交草稿。
- Bugs：四個旋轉角度的原生 overlay 座標自動檢查通過；90 度頁實際拖曳、尺寸調整與另存通過。框寬、字級、溢位與快照容量有回歸測試；不靜默截斷輸出。
- Data／privacy：原檔別名保護沿用，32 個測試通過；草稿保存／取消／空框與格式不加入網路或遠端字體。輸出 AP 使用內嵌字體，RTF 限制大小且只接受文字屬性，不使用 archive 解碼。
- Scope：新文字框是標準 FreeText 外觀加 LocalPDF 再編輯資料；舊一般註解轉換、跨頁拖曳與其他閱讀器的格式編輯未宣稱支援。
- Evidence：make verify、make ui-check、CUA 原生操作、Poppler 渲染及 pypdf annotation／字體／座標檢查；詳細結果見 [plan](intent/editable-text-boxes/plan.md)。沒有未修復的 blocker。agent 自審不代表人類批准。

## comment-threads：2026-10-05 agent 自審

- Important／已修正：便條原本在放置時即提交，PDFView 重建與縮圖 List 修訂識別使頁面可能跳回第一頁。現在先建立未發布草稿；發布前更新目前頁面，重建後恢復該頁，並避免每次修訂重建縮圖 List。原生滑鼠與合成第 3 頁流程均維持第 3／3 頁。
- Important／已修正：點既有錨點在便條工具下會再次新增。現在優先命中 Text 註解並選取討論；Popup 附屬註解不再顯示為另一個可刪物件。
- Data／rollback：根留言保留標準 PDF `/Contents`，討論串回覆與狀態以私有中繼資料儲存；新增／編輯／刪除均有復原快照，舊 Text 註解首次修改可升級，輸入原檔 byte 不變。未發布草稿不會被另存或切工具時靜默丟失。
- Scope：這是單機離線 Office 風格註解，不宣稱多人協作、@提及通知或其他閱讀器顯示回覆／解決狀態。
- Evidence：`make verify` 34／34，`make ui-check` 成功，見 [執行證據](intent/comment-threads/plan.md) 和 `.build/ui-check/comment-thread.png`、`pdf-page-3.png`。沒有未修復的 blocker。agent 自審不代表人類批准。

## selected-text-comments：2026-10-05 agent 自審

- Behavior：工具改名「新增註解」；只有有文字選區才建立草稿。同頁多行定位保存各行矩形，紅底的 Highlight 與註解 `/Contents` 一起輸出；45 度指標和浮動框只由本機檢視畫面繪製。
- Important／已修正：編輯中的空白草稿點外會取消；非空白草稿 Enter 或點外才提交。確認後框隱藏；實際滑鼠進入紅底文字才顯示，移開就隱藏。當文件 revision 改變時清除舊 hover，避免顯示已刪的註解。
- Data／rollback：新註解可復原／重做、另存重開；舊版 Text 註解及無錨點的討論 JSON 可讀、可編輯。來源 PDF byte 不變。跨頁選區拒絕而不修改文件。
- Scope：其他 PDF 閱讀器可讀紅底 Highlight 與首則 `/Contents`，45 度指標和浮動框不保證跨閱讀器顯示；此版一次選取限同頁。舊版便條不遷移或刪除。
- Evidence：`make verify` 36／36、`make ui-check`、Poppler 第 3 頁渲染、隔離 app 的滑鼠選字、Enter、點外、hover 進出驗收通過；詳細結果見 [plan](intent/selected-text-comments/plan.md)。沒有未修復的 blocker。agent 自審不代表人類批准。

## inline-content-edit：2026-10-05 agent 自審

- Behavior：點頁面原有文字後，原位置出現單行編輯欄；右側只保留字型與物件操作。Enter、點頁面其他位置與完成按鈕改寫底層文字，Escape 取消，未更動不產生新復原紀錄。
- Important／已修正：編輯時選取外框與輸入框重疊，現改為只顯示輸入框；取消後清除選取與錯誤的「已開啟」提示。字型驗證失敗時切換工具會保留原工具、選取與草稿。浮層在 CropBox 內定位，四個旋轉角度的頁面與視圖座標檢查通過。
- Data／rollback：原有 PDFium 驗證、原檔唯讀與復原快照沿用。不支援的字元顯示錯誤並保留草稿；切換字型後可修正。圖片替換仍由選檔器完成，原文字不自動重排。
- Evidence：`make verify` 36／36、`make ui-check`、隔離原生 app 的滑鼠點選、Enter、點外、Escape、限制錯誤與字型切換驗收，Poppler 對輸出第一頁獨立渲染；詳見 [plan](intent/inline-content-edit/plan.md)。沒有未修復的 blocker。agent 自審不代表人類批准。

## page-management-workspace：2026-10-05 agent 自審

- Behavior：頁面管理改為同一視窗中的專用畫面，展示全部頁面縮圖；⌘／Shift 多選、全選、批次旋轉／抽取／刪除及原生滑鼠拖曳排序均接入現有文件工作區。
- Important／已修正：SwiftUI drag/drop 在原生畫面未完成排序；改用 AppKit 滑鼠事件，實際把第 3 頁拖到第 1 頁成功。無選取時旋轉／抽取停用，復原／重做後狀態列更新，不再留下已刪除等過時文字。
- Data／rollback：多頁排序只建立一次復原紀錄，保存選取頁相對順序；刪除需確認且禁止刪除最後一頁。抽取寫到新路徑，不修改來源或工作文件。用合成檔驗證刪除及旋轉的復原；測試覆蓋拖曳後的復原／重做。
- Evidence：`make verify` 37／37、`make ui-check`、原生滑鼠拖曳、全選旋轉、抽取保存重開、刪除及復原通過；詳見 [plan](intent/page-management-workspace/plan.md) 與 `.build/ui-check/page-management.png`。沒有未修復的 blocker；agent 自審不代表人類批准。
- Drag preview／已驗收：縮小頁面預覽由原生拖曳事件跟隨滑鼠；多頁時紅字顯示「N 頁」，單頁無數字。預覽不攔截放置目標，Escape／放下即清除。單頁與多頁截圖經人工檢視，原生兩頁拖曳排序及放下後清除驗收通過；`make verify` 37／37、`make ui-check` 通過。

## public repository privacy：2026-10-05 agent 自審

- 發布前逐一檢查追蹤檔案與 Git 作者資料；將專案文件中的個人姓名改為「專案維護者」，MIT 署名改為公開的 `gilbertytw-lab`。
- 追蹤檔案未含本機使用者絕對路徑、私人郵件、電話、私鑰或常見憑證賦值；第三方 PDFium 授權 notices 中原有的貢獻者聯絡資訊依法保留。
- 遠端既有初始 commit 的個人作者資訊需獨立處理；在處理前不得宣稱 GitHub repository 的完整歷史沒有個人資訊。agent 自審不代表人類批准。
- 文件去識別化後，`make verify`（37／37、Swift build 與 policy／lint）及 `git diff --check` 通過；本次沒有 UI 變更。
