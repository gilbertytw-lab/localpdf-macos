---
id: mac-mvp
status: draft
owner: LocalPDF maintainer
risk: low-local-prototype
source: intent.md + spec.md（本地未提交）
---

# Implementation plan

依 [intent.md](intent.md) 與 [spec.md](spec.md) 開發。沒有既有 repository、CI、issue tracker、remote 或部署管道，故本地 artifact 是唯一來源。

## 計畫路徑

- `AGENTS.md`、`REVIEW.md`、`README.md`、`LICENSE`、`.gitignore`：規則與使用入口。
- `intent/`、`docs/`、`evals/`：需求、技術決策、風險與驗收案例。
- `Package.swift`、`Makefile`：原生 build、test、lint、UI 驗證。
- `Sources/LocalPDFCore/`：實際 PDF 操作與保存保護。
- `Sources/LocalPDF/`：Mac UI 與 PDFView bridge。
- `Tests/LocalPDFCoreTests/`：round trip、狀態、權限及資料保存回歸。
- `scripts/`：打包與 deterministic workflow check。

## 順序

1. 查官方文件與本機 SDK，寫 artifacts、路線與風險規則。
2. 本地 Git isolated branch `feature/mac-mvp` 建立可打包 SwiftPM app；不 commit／push。
3. 先完成 PDF workspace、undo、輸入保護與資料 round trip 測試。
4. 加上頁面、註解、檔案操作 UI，UI smoke 驗證與截圖。
5. 執行 `make verify`、`make ui-check`，檢視 diff 與 review findings；修正實際問題。
6. 提供應用程式、啟動方式、限制與尚待決策項目。

## 風險與替代方案

- 原有文字直接修改需要內容解析、字型與定位，不用文字色塊覆蓋來假裝完成。後續用 fixture spike 決定引擎。
- 若用 MuPDF，需先確認 AGPL 路徑是否符合產品；本版只使用系統 PDFKit。
- snapshot 以簡單有界序列化換取可靠 undo；大文件先明確拒絕超限操作，後續才做增量 command history。
- 複雜 AcroForm／signature widgets 暫拒絕編輯；本版只保證測過的普通 PDF 路徑。
- unsigned local app 只作開發驗證；公開發布由專案維護者決定。

## 證據與 review

2026-10-05 本地原型驗證（agent 執行，不等同人類批准）：

- `make verify`：格式、artifact／planned-path／offline capability check、15 個 Swift Testing 回歸案例與 build 全部成功。原始輸出 `.build/verify.log`；invalid PDF 案例的 CoreGraphics parsing 訊息屬預期，沒有失敗 test。
- `make ui-check`：bundle plist lint 與 app fixture 流程成功，產生 `.build/ui-check/welcome.png`、`editor-chrome.png`、`edited.pdf`、`pdf-page-1.png`；最後 UI 同步改動後另外重跑 lint／policy，成功。
- 實際 Mac app：經檔案面板開啟 PDF、搜尋 `workflow`、螢光標記、新增繁中文字、復原兩次回到 clean state、縮放均確認成功；舊版退出時已驗證未儲存提示。實際窗口截圖為 `.build/ui-check/editor-live.png`。
- PDF 圖片 round trip：PDFKit bitmap 與 Poppler render 均可看到保存圖片，證據 `.build/test-evidence/image-roundtrip.pdf`、`image-native.png`、`image-roundtrip.png`。顏色檢查採紅色通道優勢，避免 Display P3／16-bit 色彩管理造成固定通道門檻誤判。
- Poppler 讀取輸出：3 頁 A4、未加密、無表單、無 JavaScript；文字、頁序與保存由回歸測試檢查。工具只用於驗證，不是 app runtime 依賴。
- 尚待：專案維護者試用、回答產品優先序與跨平台方向、真實 PDF corpus、正式發布批准。現有成果是本地開發原型，沒有 remote、commit、PR 或 release。

原型 review 發現 PDFView 的原生註解 AX editor 可能繞過 app mutation；改為獨立唯讀展示副本並映射 selection／點擊，讓 native presentation 改動不會進入輸出。新增 workspace 隔離與輸出 flags regression。快照在 mutation 前後皆檢查容量，超限立即回復，避免 undo 無法保存 redo 狀態。

其他 review：輸出圖片原先因測試提前釋放 PDFDocument，讓 thumbnail 驗證不完整；已保留文件生命週期，並以第二個 renderer 交叉檢查。驗收素材改用固定文字色，避免深色 appearance 影響輸出。離屏 bitmap 不包含 PDFKit tile layer，明確標為 UI chrome 證據，另保留真實窗口與獨立 render。

現階段限制：主執行緒序列化、展示副本與 snapshot 有額外記憶體成本；未驗證大型真實文件、sandbox、Intel 或 macOS 14 實機。加入 annotation 移動／修改、OCR 或原有內容編輯時需要更新 artifacts 與 regression。

## 授權

Engineer acceptance：此本地原型依當次需求連續開發，不額外要求 approval。產品假設尚未人類確認；正式發布由專案維護者批准。沒有 commit ID，檔案保留在 Git working tree 可審閱。
