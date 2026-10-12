---
title: 程式碼貢獻
---

# 參與程式碼貢獻

目前建置入口見[專案 README](https://github.com/Torrekie/Battman)和儲存庫約定。Battman 1.1.0 使用 Objective-C、C 和程式化介面，同時提供 Xcode 專案與基於 Make 的交叉建置路徑。

## 找到相關元件

| 目錄 | 用途 |
| --- | --- |
| `Battman/` | iOS 應用程式與裝置介面 |
| `Battman/Features/Analytics/` | 宿主資料服務、卡片版面與內建卡片 |
| `Battman/PluginHost/` | 原生外掛程式探索、驗證、信任與生命週期 |
| `PluginSDK/` | 公開 SDK v1 標頭檔、結構描述、範本、工具與範例 |
| `OfficialPlugins/` | Charge Gauge 開發者原始碼範例與公開信任輸入 |
| `Scripts/Build/`、`Scripts/Release/`、`Packaging/` | 建置收尾、套件產生與發行約定 |
| `Tests/` | 針對宿主、SDK、分析與發行的專項檢查 |
| `docs/battman-user-manuals/` | 本三語手冊 |

## 實作與驗證

保持變更集中，並保留宣告的 iOS 12 部署基線。外掛程式使用公開 SDK 約定，不依賴宿主私有控制器，也不在繪圖回呼中讀取硬體資料。獨立開發流程與簽署要求見[外掛程式開發指南](https://github.com/Torrekie/Battman/blob/master/docs/plugin-authoring.md)。

使用既有相依項目和建置路徑。Xcode 的 gettext 相依項目會下載固定封存檔、校驗摘要並建置，首次建置需要存取 GNU。不要為不相關變更新增自動相依套件升級或強制更換工具鏈。保持資源可攜性及既有程式化介面約定。

執行與變更相關的最小檢查，並明確說明驗證範圍。模擬器或編譯成功不能證明所有裝置的硬體行為。不要將憑證、私有簽署金鑰、裝置識別碼或私有發行記錄放入提交和公開診斷。

使用者可見行為發生變化時，同步英語、簡體中文和繁體中文手冊。在儲存庫根目錄使用隔離環境建置手冊：

```sh
Scripts/Docs/render-user-manual.sh /tmp/battman-manual-preview
```

輸出路徑必須尚不存在。該工具使用現有、固定版本和雜湊的 `Requirements/docs.txt`，執行嚴格建置而不部署網站。透過 HTTP 預覽結果以檢查導覽和搜尋。
