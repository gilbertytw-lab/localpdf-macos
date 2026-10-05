# 現行工作清單

## M0：本地原型

頁面管理、閱讀搜尋、文字／選字註解／圖片、螢光標記、undo／redo、保存副本，以及可重跑 SDLC artifacts 和驗證。完成狀態與證據見 [plan](../intent/mac-mvp/plan.md)。

## M1：日常文件工具

- 實際 PDF corpus：繁中、英文、多欄、掃描、旋轉、混合尺寸、嵌入字型、500+ 頁。
- 拖曳排序、頁面裁切與範圍拆分、簽名圖片／手寫筆跡、舊便條／圖片 annotation 移動與縮放。
- 0.3 已完成新增富文字框的直接輸入、選區格式、移動、尺寸調整與重開編輯，證據見 [文字框計畫](../intent/editable-text-boxes/plan.md)。後續補舊版一般 FreeText 匯入及跨頁拖曳。
- Vision OCR：先文字辨識與匯出，再驗證可搜尋 PDF 層；顯示信心度与失敗頁。
- AcroForm 支援、密碼開啟／加密輸出、壓縮 quality preview、檔案大小差異。
- 關閉／當機恢復、非同步 parse 與大型文件 memory benchmark。

## M2：直接修改原有內容

使用者已指定本階段優先。0.2 已做頂層文字替換／刪除、圖片替換／刪除、共用資源單一出現位置、原檔保護與 undo。證據見 [內容編輯計畫](../intent/direct-content-edit/plan.md)。後續：

1. 字型嵌入與繁中新字元，保留 kerning／字距，擴展 subset 和 ToUnicode 驗證。
2. 真實 corpus 與段落／多欄重排；文字區塊 resize／移動。
3. Form XObject、裁切、透明混合效果與 Tagged PDF 保留。
4. 定義無法可靠處理時的明確 fallback；對嵌入 subset 字型、多欄重排不保證無差異。
5. 原有 ICC／CMYK 色彩描述與漸層／Pattern 保留；大型文件效能。引擎版本更新先重跑完整回歸。

## M3：敏感文件與格式互通

- 真正移除敏感文字、圖片、metadata 和殘留物件的安全遮蔽；輸出後獨立抽取／搜尋驗證。
- 數位憑證簽章、簽章有效性提示、PDF/A／PDF/UA：各自建立專門驗收，避免與圖片簽名混用。
- PDF ↔ 圖片／文字先做；PDF ↔ DOCX／XLSX 的 layout loss 與相依另評估。
- 跨平台策略、sandbox、簽章、公證、auto update（若有）、開源發行流程。

發布前：專案維護者確認 intent 與優先序、LICENSE、正式 app 名稱，完成 human review、真實 corpus 與發行驗證。此工作清單不承諾時程或未驗證功能。
