# 風險政策

| 階段 | 必要證據與授權 |
|---|---|
| Low：本地合成資料原型、非破壞性開發 | 當次任務授權、intent／spec／plan、測試與 review；不額外要求逐階段批准 |
| Medium：修改真實文件工作副本、導入引擎或加密流程 | round trip corpus、資料保存／授權檢查、產品 owner 驗收後才能列為正式支援 |
| High：安全遮蔽、憑證簽章、覆寫原檔、格式合規承諾 | 技術與產品 owner 核准規格；獨立內容檢測、rollback 與外部 reader 證據 |
| Release：發布 repository／發行 app、簽章公證、remote 或系統安裝 | 專案維護者的明確批准、版本與來源紀錄、build／tests／review／授權與發布驗證 |

`make verify` deterministic 檢查 artifacts、計畫路徑、無第三方依賴的 offline 架構和測試；它不等同 production approval。原始碼託管於 GitHub；尚未驗證 branch protection／CODEOWNERS enforcement，未設定 required checks 與 human reviewer 前不可宣稱受保護。

這裡的高風險政策限制的是功能的正式承諾與發布；不要求每個可回復的本地實驗另行批准。Agent 的 review 不代表自我批准 PR。
