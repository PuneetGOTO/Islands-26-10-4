// 產生「自給自足」的部署器：把 FluentCompat.lua 完整內嵌進 install-compat.lua。
// 關鍵：產生後立即在記憶體中反向解析，驗證與原始檔「位元組完全相同」，
//       確保內嵌過程沒有破壞任何跳脫字元。
const fs = require("fs");

const SRC = "FluentCompat.lua";
const OUT = "install-compat.lua";

const raw = fs.readFileSync(SRC, "utf8");

// Lua 長括號字串 [==[ ... ]==] 不需要任何跳脫，但內容不得包含 ]==]
// 自動挑選足夠長的等號層級。
let level = 0;
while (raw.includes("]" + "=".repeat(level) + "]")) {
  level++;
}
const open = "[" + "=".repeat(level) + "[";
const close = "]" + "=".repeat(level) + "]";

if (raw.includes(open)) {
  throw new Error("無法安全內嵌：內容含有長括號開啟序列");
}

const banner = `-- ==============================================================================
--  Identical UI 引擎安裝器（自給自足版，由 build-installer.js 自動產生）
-- ==============================================================================
--  用途：把下方內嵌的 FluentCompat 引擎載入並註冊到 getgenv()，
--        讓 IslandsScript.lua 能直接取用 —— 不需要任何檔案讀寫。
--
--  用法（兩種都行）：
--
--    做法 A（推薦，不需要檔案）
--      1. 把本檔整份貼進執行器執行一次
--      2. 再執行 IslandsScript（用 loadstring 讀遠端或本機檔案都可以）
--      → IslandsScript 會從 getgenv().FluentCompat 取得引擎
--
--    做法 B（想從本機檔案載入時）
--      本檔同時會嘗試把引擎寫成 Nekohub/Islands/FluentCompat.lua，
--      IslandsScript 便能用 readfile 讀到。
--
--  想先看新介面長怎樣，執行這一行即可：
--
--      getgenv().FluentCompat.Demo
--
--  注意：本檔不會自動開視窗。這是刻意的 —— 若你接下來要跑
--        IslandsScript，自動開的測試視窗會跟主視窗打架。
--
--  請勿手動編輯本檔 —— 改 FluentCompat.lua 後重新產生即可。
-- ==============================================================================

local TARGET = "Nekohub/Islands/FluentCompat.lua"

-- 內嵌的 FluentCompat 原始碼（使用長括號字串，內容未經任何轉義）
local PAYLOAD = ${open}
`;

const footer = `
${close}

-- ==============================================================================
-- 健全性檢查：確認內嵌的是我們的引擎，而不是 404 頁面或別的檔案
-- ==============================================================================
local looksValid = PAYLOAD:find("FluentCompat", 1, true) ~= nil
	and PAYLOAD:find("CreateWindow", 1, true) ~= nil
	and PAYLOAD:find("AddToggle", 1, true) ~= nil
	and PAYLOAD:find("ApplyCommonMethods", 1, true) ~= nil

if not looksValid then
	warn("[安裝] 內嵌內容不完整，已中止。")
	return
end

-- 寫入 marker：讓 IslandsScript 可回報「引擎是以明確方式安裝的」，
-- 而不是悄悄退回遠端或直接停用介面。
if not isfile then
	warn("[安裝] 此執行器沒有 isfile/readfile，將只使用記憶體載入（做法 A）。")
end

-- ==============================================================================
-- 1) 載入引擎並註冊到 getgenv()
-- ==============================================================================
local library = nil

if loadstring then
	local ok, res = pcall(function()
		return loadstring(PAYLOAD)()
	end)
	if ok and type(res) == "table" and res.CreateWindow then
		library = res
	else
		warn("[安裝] 引擎執行失敗：" .. tostring(res))
	end
else
	warn("[安裝] 此執行器沒有 loadstring，無法載入引擎。")
end

if library and getgenv then
	local ok = pcall(function()
		local g = getgenv()
		g.FluentCompat = library
		g.IdenticalUI = library
	end)
	if ok then
		print("[安裝] 引擎已註冊到 getgenv().FluentCompat")
	else
		warn("[安裝] 註冊到 getgenv() 失敗。")
	end
end

-- ==============================================================================
-- 2) 另外寫一份到檔案（做法 B 用；失敗不影響做法 A）
-- ==============================================================================
if isfile and writefile then
	local function ensureFolder(path)
		local cur = ""
		for part in string.gmatch(tostring(path), "[^/]+") do
			cur = (cur == "") and part or (cur .. "/" .. part)
			if isfolder and not isfolder(cur) then
				pcall(makefolder, cur)
			end
		end
	end

	ensureFolder("Nekohub/Islands")

	local wrote = pcall(writefile, TARGET, PAYLOAD)
	if wrote then
		local verify = nil
		pcall(function()
			if isfile(TARGET) then verify = readfile(TARGET) end
		end)
		if verify and #verify == #PAYLOAD then
			print("[安裝] 亦已寫入 " .. TARGET .. "（做法 B 可用）")
		else
			warn("[安裝] 檔案寫入後長度不符，做法 B 可能不可用。")
		end
	else
		warn("[安裝] 無法寫入檔案（權限不足），做法 A 仍可使用。")
	end
end

-- ==============================================================================
-- 3) 結果
-- ==============================================================================
print("")
if library then
	print("[安裝] 完成。現在可以執行 IslandsScript，介面會使用 Identical UI 引擎。")
	print("[安裝] 想看新介面：getgenv().FluentCompat.Demo")
else
	warn("[安裝] 引擎未能載入，請確認 loadstring 可用。")
end
`;

const lua = banner + raw + footer;

// ---- 驗證：把長括號字串反向解析回來，必須與原始檔完全相同 ----
const startIdx = lua.indexOf(open + "\n");
if (startIdx === -1) throw new Error("找不到內嵌區段起點");
const contentStart = startIdx + open.length + 1;
const endIdx = lua.indexOf("\n" + close, contentStart);
if (endIdx === -1) throw new Error("找不到內嵌區段終點");
const extracted = lua.slice(contentStart, endIdx);

const identical = extracted === raw;
console.log("=== 內嵌驗證 ===");
console.log(`原始檔         ${raw.length} bytes / ${raw.split("\n").length} 行`);
console.log(`反向解析       ${extracted.length} bytes / ${extracted.split("\n").length} 行`);
console.log(`長括號層級     [${"=".repeat(level)}[`);
console.log(`位元組完全相同 ${identical ? "✅ 是" : "❌ 否"}`);

if (!identical) {
  for (let i = 0; i < Math.max(extracted.length, raw.length); i++) {
    if (extracted[i] !== raw[i]) {
      console.log(`第一個差異在第 ${i} 個位元組：`);
      console.log(`  原始: ${JSON.stringify(raw.slice(Math.max(0, i - 40), i + 40))}`);
      console.log(`  內嵌: ${JSON.stringify(extracted.slice(Math.max(0, i - 40), i + 40))}`);
      break;
    }
  }
  process.exitCode = 1;
} else {
  fs.writeFileSync(OUT, lua, "utf8");
  console.log("");
  console.log(`✅ 已寫出 ${OUT}（${lua.length} bytes / ${lua.split("\n").length} 行）`);
}
