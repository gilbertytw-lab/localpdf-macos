---
id: direct-content-edit
status: draft
owner: LocalPDF maintainer
risk: low-local-prototype
---

# Specification

來源：[intent.md](intent.md)。agent 擬稿，尚未人類產品驗收。

- PDFKit 繼續負責原生顯示與既有操作；採 PDFium 公開 C API 解析及改寫原有頁面物件。使用 BSD 相容授權、無 V8 的固定 arm64 本地 binary，不整合 MuPDF。
- build 準備腳本下載固定版本、核對 SHA-256，依賴只在專案 `.build`；app 包含 dylib 和全部第三方 notices。執行期不下載或呼叫外部程序。
- 編輯模式點選物件或從清單選取。列出目前頁面的頂層文字與圖片；Form XObject 暫不展開。物件 token 包含 workspace revision，過期選取拒絕修改。
- 文字修改提供保留原字型（僅已驗證的原有字元）與使用 Helvetica（Latin 字元）的選擇。保持位置、大小、顏色；不自動重排其他物件。保留原字型的模式不默默補不存在的 glyph。複雜文字繪製與裁切拒絕，長文字超出頁面拒絕。
- 原圖替換沿用矩陣／顯示範圍，保留透明度，影響選取的出現位置而非共用資源的其他出現位置。可刪除原有文字或圖片；這是內容編輯，不提供安全遮蔽承諾。
- 所有 mutation 先生成完整候選 PDF，重開與校驗後才替換 workspace；失敗保留文件、dirty、undo。沿用有界快照、原檔別名保護。
- Widget、加密、無權限文件沿用阻擋。旋轉／非零 CropBox 的座標需驗證；物件保存矩陣不變。未支援內容提供明確錯誤；缺少引擎時 build 準備腳本停止，不產生缺少 dylib 的 app。
- PDFium 重建 stream 不支援原樣輸出 ICC／CMYK graphics 色彩。編輯此頁將文字／線條轉成引擎解析的 8-bit RGB，保持數位閱讀的近似外觀，介面與 README 明示失去原印刷色彩描述。含漸層／Pattern 頁面暫拒絕；未編輯頁面不經這個轉換。
- 保留原始與候選 PDF bytes 作為內容的正式資料，PDFKit 作為顯示與既有操作介面。一般 PDFKit mutation 後才重新序列化；內容 mutation、undo、save 不重複重建未更動 streams。
- 打包使用原子替換 binary 與本機 ad-hoc 簽章；不使用 Developer ID、不公證或發布。
- 候選 PDF 以 CoreGraphics 最長邊 1024 px 渲染前後頁面；只允許原選取 bounds 與新文字 bounds 的聯集（外擴 5 px）。其他區域 RGB 任一通道差 >24/255 的像素不得超過全圖 0.05%（最低容許 24 px），否則整次操作取消。用來攔截未選取字距／外觀變化；不是印刷精度或完整語意驗證。

驗收：原文字抽取結果確實更換；原圖物件的畫面更換／消失；其他頁與註解保留；undo／redo、過期 token、原檔不變；PDFKit 與 Poppler 交叉渲染；原生 UI 實際選取、編輯、保存。
