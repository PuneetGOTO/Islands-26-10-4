// 產生單檔版：把 FluentCompat 引擎與 IslandsScript 合併成一個可直接
// loadstring(game:HttpGet(url))() 執行的檔案。
//
// 為什麼需要「包成函式」而不是直接串接：
//   本 chunk 已有 198 個存活到檔尾的頂層 local，Luau 上限是 200。
//   引擎本身還會宣告約 16 個頂層 local，直接串接會變成 ~214 → 編譯失敗。
//   包進 (function() ... end)() 後，引擎的 local 活在函式作用域裡，
//   只有回傳值那一個 local 落在 chunk 作用域。
const fs = require("fs");

const ENGINE = "FluentCompat.lua";
const HOST = "IslandsScript.lua";
const OUT = "IslandsUI.lua";

const engine = fs.readFileSync(ENGINE, "utf8").replace(/\r\n/g, "\n");
const host = fs.readFileSync(HOST, "utf8").replace(/\r\n/g, "\n");

// 註：IslandsScript.lua 是 CRLF、FluentCompat.lua 是 LF。
//     這裡統一正規化為 LF 再處理，輸出也用 LF（Lua 兩者皆可）。

// ---- 1. 找出主腳本中的「載入引擎」區塊 ----
const startMarker = "--[[ ============================================================================\n     介面引擎替換";
const start = host.indexOf(startMarker);
if (start === -1) throw new Error("找不到載入區塊起點");

const blockEndToken = "\t}, {}, {}\nend)()";
const endIdx = host.indexOf(blockEndToken, start);
if (endIdx === -1) throw new Error("找不到載入區塊終點 (end)())");
const blockEnd = endIdx + blockEndToken.length;

const hostLineStart = host.slice(0, start).split("\n").length;
const hostLineEnd = host.slice(0, blockEnd).split("\n").length;
console.log("=== 載入區塊定位 ===");
console.log(`  第 ${hostLineStart} ~ ${hostLineEnd} 行（共 ${hostLineEnd - hostLineStart + 1} 行）`);

// ---- 2. 替換該區塊：直接使用內嵌引擎 ----
const newBlock = [
  "--[[ ============================================================================",
  "     介面引擎：Identical UI（FluentCompat，已內嵌於本檔最上方）",
  "     ----------------------------------------------------------------------------",
  "     這是「單檔版」。原本的 Fluent-master/main.lua 與兩個 Addon 已由內嵌的",
  "     Identical UI 引擎取代，它提供完全相同的 API 表面，因此本檔下方那約 4700 行",
  "     UI 建構程式不需要任何修改。",
  "",
  "     包成函式是必要的：引擎自己會宣告約 16 個 top-level local，若直接串接",
  "     會使本 chunk 的 local 數超過 Luau 的 200 上限而無法編譯。",
  "============================================================================ ]]",
  "",
  "local Fluent = __ENGINE__",
  "local SaveManager = Fluent.SaveManager or {}",
  "local InterfaceManager = Fluent.InterfaceManager or {}"
].join("\n");

const hostTail = host.slice(blockEnd);
const combined = host.slice(0, start) + newBlock + hostTail;

// ---- 3. 引擎置於最前，包成函式 ----
const banner = [
  "--[[ ============================================================================",
  "  Islands UI — 單檔版",
  "  ============================================================================",
  "  用法（不需要任何本機檔案）：",
  "",
  "      loadstring(game:HttpGet('https://raw.githubusercontent.com/PuneetGOTO/Islands-26-10-4/main/IslandsUI.lua'))()",
  "",
  "  本檔 = Identical UI 介面引擎 + Islands 主腳本，合併成單一檔案。",
  "",
  "  為什麼要合併：",
  "      loadstring(game:HttpGet(...))() 只有一次抓取機會，無法再載入第二個檔案。",
  "      內嵌後執行完全不依賴 readfile / writefile。",
  "",
  "  介面引擎：Identical UI (FluentCompat)",
  "      - 取代原 Fluent UI，提供完全相同的 API 表面",
  "      - 已對照驗證：主腳本 175 個控件呼叫點零遺漏",
  "      - 想看引擎自我測試介面： getgenv().FluentCompat.Demo",
  "",
  "  ============================================================================",
  "  注意：本檔由 build-single-file.js 自動產生，請勿手動編輯。",
  "        要改動請改 FluentCompat.lua 或 IslandsScript.lua 後重新產生。",
  "============================================================================ ]]",
  "",
  "-- ============================================================================",
  "-- 引擎：Identical UI (FluentCompat)",
  "-- 包在函式內以隔離 local 作用域（見上方說明）",
  "-- ============================================================================",
  "local __ENGINE__ = (function()",
  ""
].join("\n");

const epilogue = [
  "end)()",
  "",
  "-- ============================================================================",
  "-- 主腳本：Islands",
  "-- ============================================================================",
  ""
].join("\n");

const out = banner + engine + "\n" + epilogue + combined;

fs.writeFileSync(OUT, out, "utf8");

console.log("");
console.log("=== 輸出 ===");
console.log(`  ${OUT}: ${Buffer.byteLength(out, "utf8")} bytes / ${out.split("\n").length} 行`);
console.log(`  引擎區段:   ${engine.split("\n").length} 行`);
console.log(`  主腳本區段: ${combined.split("\n").length} 行`);
