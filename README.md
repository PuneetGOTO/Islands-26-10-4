# Islands UI

Islands 的介面改版：把原本的 **Fluent UI** 換成自寫的 **Identical UI** 引擎，並確保功能零遺漏。

## 直接執行（推薦）

把下面這行貼進執行器即可，**不需要任何本機檔案**：

```lua
loadstring(game:HttpGet('https://raw.githubusercontent.com/PuneetGOTO/Islands-26-10-4/main/IslandsUI.lua'))()
```

`IslandsUI.lua` 是單檔版，已把介面引擎與主腳本合併在一起。

### 想看新介面長怎樣

```lua
getgenv().FluentCompat.Demo
```

會開一個自我測試視窗，把所有控件跑一遍（開關、滑桿、單選／多選下拉、輸入框、數字框、按鍵綁定、顏色選擇、對話框、通知）。

## 檔案說明

| 檔案 | 用途 |
|---|---|
| `IslandsUI.lua` | **單檔版**，直接 `loadstring` 執行用（引擎已內嵌） |
| `IslandsScript.lua` | 主腳本，從外部載入引擎的版本 |
| `FluentCompat.lua` | 介面引擎本體 |
| `install-compat.lua` | 引擎安裝器（貼進執行器一次，供分檔版使用） |

### 分檔版怎麼用

若你想分開跑（例如自己改引擎）：

1. 把 `install-compat.lua` 整份貼進執行器執行一次 → 引擎會註冊到 `getgenv().FluentCompat`
2. 再執行 `IslandsScript.lua`（`loadstring` 讀本機或遠端都行）

`IslandsScript.lua` 的載入優先序：

```
0) getgenv().FluentCompat    ← 記憶體，不需要檔案
1) readfile 四個候選路徑      ← 執行器工作目錄
2) 遠端下載
3) 惰性空物件                ← 介面停用，但腳本其餘功能照常
```

## 為什麼需要新的引擎

原腳本用 Fluent UI，介面建構程式約 4700 行、175 個控件呼叫點。要換掉介面又不漏功能，可靠的做法不是手搬控件，而是**讓新引擎提供與 Fluent 完全相同的 API**，那 4700 行就能原封不動地跑在新引擎上。

已對照驗證的 API 表面：

| 控件 | 使用次數 |
|---|---|
| `AddToggle` | 40 |
| `AddButton` | 37 |
| `AddSection` | 28 |
| `AddTab` | 26 |
| `AddParagraph` | 16 |
| `AddDropdown` | 10 |
| `AddSlider` | 8 |
| `AddInput` | 6 |
| `AddColorpicker` | 3 |
| `AddKeybind` | 1 |

外加 15 個層級方法（`Fluent:CreateWindow` / `Fluent:Notify` / `Fluent.Options`、`Window:AddTab` / `SelectTab` / `Dialog`、`SaveManager` 與 `InterfaceManager` 的全部方法）。

## 驗證

```bash
node validate-release.js IslandsUI.lua
```

檢查項目：

- 檔案大小（適合 `HttpGet`）
- 引擎確實內嵌、無佔位字串殘留
- **頂層 local 數量 ≤ 200**（Luau 硬限制，超過就無法編譯）
- 括號全數配對
- **chunk 層級無非法 `return`**（Lua 只允許最後一個語句是 `return`）

### 一個容易踩的坑

Lua／Luau 對每個函式作用域有 **200 個 active local** 的上限。`IslandsScript.lua` 本身已有 198 個存活到檔尾的頂層 local，所以合併引擎時**不能直接串接**（引擎自己還會宣告約 16 個，加起來會爆掉）。

單檔版因此把引擎包在 `(function() ... end)()` 裡隔離作用域，最終落在 chunk 層級的是 199 個。

## 重新產生

單檔與安裝器都是產生的，請改來源後重新產生，不要直接編輯產物：

```bash
node build-single-file.js    # 產生 IslandsUI.lua
node build-installer.js      # 產生 install-compat.lua
node validate-release.js IslandsUI.lua
```

## 已知限制

- **未在 Roblox 實機驗證過。** 已驗證的是語法結構、頂層 local 數量、API 覆蓋對照、合併正確性（含位元組級一致性）。視覺呈現與互動手感需要實機確認——建議先用 `getgenv().FluentCompat.Demo` 檢查。
- **設定存檔是重新實作的**，不是原版 Fluent 的 SaveManager。內部格式不同，舊存檔不相容。
- 腳本本身原有的外部依賴（Hydroxide、verm 等）維持不變，與介面改版無關。
