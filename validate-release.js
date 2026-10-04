// 單檔版交付前的最終檢查（獨立於其他工具，可重複執行）
const fs = require("fs");
const file = process.argv[2] || "IslandsUI.lua";
const src = fs.readFileSync(file, "utf8");
const lines = src.split("\n");

const results = [];
function check(name, ok, detail) {
  results.push({ name, ok, detail });
}

// ---- 1. 基本資訊 ----
const bytes = Buffer.byteLength(src, "utf8");
check("檔案大小合理（< 2MB，適合 HttpGet）", bytes < 2 * 1024 * 1024,
  `${(bytes / 1024).toFixed(0)} KB / ${lines.length} 行`);

// ---- 2. 引擎內嵌 ----
check("引擎包裝存在", src.includes("local __ENGINE__ = (function()"), "IIFE 隔離 local 作用域");
check("引擎回傳值被使用", src.includes("local Fluent = __ENGINE__"), "");
check("無未替換佔位字串", !src.includes("__IDENTICAL_ENGINE__"), "");
check("引擎關鍵函式齊備",
  ["ApplyCommonMethods", "BuildElementHost", "CreateWindow", "BuildDemoWindow"]
    .every(k => src.includes(k)), "");

// ---- 3. 頂層 local 數量（Luau 上限 200）----
function countTopLocals(text) {
  let i = 0, depth = 0, count = 0;
  const isAlpha = c => /[A-Za-z_]/.test(c);
  const isWord = c => /[A-Za-z0-9_]/.test(c);
  const toks = [];
  let line = 1;
  while (i < text.length) {
    const c = text[i];
    if (c === "\n") { line++; i++; continue; }
    if (c === " " || c === "\t" || c === "\r") { i++; continue; }
    if (c === "-" && text[i + 1] === "-") {
      const lb = text.substr(i + 2).match(/^\[(=*)\[/);
      if (lb) {
        const close = "]" + lb[1] + "]";
        const e = text.indexOf(close, i + 2 + lb[0].length);
        i = e === -1 ? text.length : e + close.length;
      } else { while (i < text.length && text[i] !== "\n") i++; }
      continue;
    }
    const lbm = text.substr(i).match(/^\[(=*)\[/);
    if (lbm) {
      const close = "]" + lbm[1] + "]";
      const e = text.indexOf(close, i + lbm[0].length);
      i = e === -1 ? text.length : e + close.length; continue;
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < text.length) {
        if (text[j] === "\\") { j += 2; continue; }
        if (text[j] === c) { j++; break; }
        j++;
      }
      i = j; continue;
    }
    if (isAlpha(c)) {
      let j = i; while (j < text.length && isWord(text[j])) j++;
      toks.push({ type: "word", value: text.slice(i, j), line });
      i = j; continue;
    }
    toks.push({ type: "sym", value: c, line });
    i++;
  }
  for (let t = 0; t < toks.length; t++) {
    const tok = toks[t], v = tok.value;
    if (tok.type === "sym") continue;
    if (v === "do") {
      let k = t - 1, loopTail = false;
      while (k >= 0 && toks[k].line === tok.line) {
        if (toks[k].type === "word" && (toks[k].value === "for" || toks[k].value === "while")) { loopTail = true; break; }
        k--;
      }
      if (!loopTail) depth++;
      continue;
    }
    if (v === "function" || v === "if" || v === "for" || v === "while" || v === "repeat") { depth++; continue; }
    if (v === "end" || v === "until") { depth--; continue; }
    if (v === "local" && depth === 0) {
      let j = t + 1; const names = [];
      while (j < toks.length) {
        const tk = toks[j];
        if (tk.type !== "word") break;
        if (tk.value === "function") break;
        names.push(tk.value);
        const k = j + 1;
        if (k < toks.length && toks[k].type === "sym" && toks[k].value === ",") { j = k + 1; continue; }
        break;
      }
      if (names.length === 0) {
        let k = t + 1;
        while (k < toks.length && toks[k].type === "word" && toks[k].value !== "function") k++;
        if (k < toks.length && toks[k].value === "function") count++;
      } else count += names.length;
    }
  }
  return count;
}

const topLocals = countTopLocals(src);
check("頂層 local 未超過 Luau 上限 200", topLocals <= 200, `實際 ${topLocals} 個（剩餘 ${200 - topLocals}）`);

// ---- 4. 區塊與括號配對 ----
function blockBalance(text) {
  let round = 0, square = 0, curly = 0, i = 0;
  while (i < text.length) {
    const c = text[i];
    // 單行與長括號註解
    if (c === "-" && text[i + 1] === "-") {
      const lb = text.substr(i + 2).match(/^\[(=*)\[/);
      if (lb) {
        const close = "]" + lb[1] + "]";
        const e = text.indexOf(close, i + 2 + lb[0].length);
        i = e === -1 ? text.length : e + close.length;
      } else { while (i < text.length && text[i] !== "\n") i++; }
      continue;
    }
    // 長括號字串 [[ ]] / [=[ ]=] —— 必須跳過，否則結尾的 ] 會被誤算
    const lbm = text.substr(i).match(/^\[(=*)\[/);
    if (lbm) {
      const close = "]" + lbm[1] + "]";
      const e = text.indexOf(close, i + lbm[0].length);
      i = e === -1 ? text.length : e + close.length;
      continue;
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < text.length) {
        if (text[j] === "\\") { j += 2; continue; }
        if (text[j] === c) { j++; break; }
        j++;
      }
      i = j; continue;
    }
    if (c === "(") round++;
    else if (c === ")") round--;
    else if (c === "[") square++;
    else if (c === "]") square--;
    else if (c === "{") curly++;
    else if (c === "}") curly--;
    i++;
  }
  return { round, square, curly };
}
const bal = blockBalance(src);
check("括號全數配對", bal.round === 0 && bal.square === 0 && bal.curly === 0,
  `() ${bal.round}  [] ${bal.square}  {} ${bal.curly}`);

// ---- 5. 不得在 chunk 層級出現 return ----
let depth2 = 0, chunkReturns = 0;
{
  const toks2 = [];
  let i = 0, ln = 1;
  const isAlpha = c => /[A-Za-z_]/.test(c);
  const isWord = c => /[A-Za-z0-9_]/.test(c);
  while (i < src.length) {
    const c = src[i];
    if (c === "\n") { ln++; i++; continue; }
    if (c === " " || c === "\t" || c === "\r") { i++; continue; }
    if (c === "-" && src[i + 1] === "-") {
      const lb = src.substr(i + 2).match(/^\[(=*)\[/);
      if (lb) {
        const close = "]" + lb[1] + "]";
        const e = src.indexOf(close, i + 2 + lb[0].length);
        i = e === -1 ? src.length : e + close.length;
      } else { while (i < src.length && src[i] !== "\n") i++; }
      continue;
    }
    const lbm = src.substr(i).match(/^\[(=*)\[/);
    if (lbm) {
      const close = "]" + lbm[1] + "]";
      const e = src.indexOf(close, i + lbm[0].length);
      i = e === -1 ? src.length : e + close.length; continue;
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < src.length) {
        if (src[j] === "\\") { j += 2; continue; }
        if (src[j] === c) { j++; break; }
        j++;
      }
      i = j; continue;
    }
    if (isAlpha(c)) {
      let j = i; while (j < src.length && isWord(src[j])) j++;
      toks2.push({ type: "word", value: src.slice(i, j), line: ln });
      i = j; continue;
    }
    toks2.push({ type: "sym", value: c, line: ln });
    i++;
  }
  for (let t = 0; t < toks2.length; t++) {
    const tok = toks2[t], v = tok.value;
    if (tok.type === "sym") continue;
    if (v === "do") {
      let k = t - 1, loopTail = false;
      while (k >= 0 && toks2[k].line === tok.line) {
        if (toks2[k].type === "word" && (toks2[k].value === "for" || toks2[k].value === "while")) { loopTail = true; break; }
        k--;
      }
      if (!loopTail) depth2++;
      continue;
    }
    if (v === "function" || v === "if" || v === "for" || v === "while" || v === "repeat") { depth2++; continue; }
    if (v === "end" || v === "until") { depth2--; continue; }
    if (v === "return" && depth2 === 0) chunkReturns++;
  }
}
check("chunk 層級無非法 return", chunkReturns === 0, `實際 ${chunkReturns} 個`);

// ---- 6. 輸出 ----
console.log(`檔案：${file}`);
console.log("");
let failed = 0;
for (const r of results) {
  if (!r.ok) failed++;
  console.log(`${r.ok ? "✅" : "❌"} ${r.name}${r.detail ? "  —  " + r.detail : ""}`);
}
console.log("");
console.log(failed === 0
  ? `全部通過（${results.length} 項）`
  : `${failed} 項未通過`);
process.exitCode = failed ? 1 : 0;
