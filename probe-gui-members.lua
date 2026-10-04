--[[ ============================================================================
  Roblox GUI 成員探測器  (v2)
  ============================================================================
  用途：在 Roblox 中實際執行，確認每個 GUI 類別「真的有」哪些屬性／事件。
        用來事前抓出「在錯誤的物件上用不存在的成員」這類錯誤。

  v2 變更：輸出改為純 ASCII、不使用 tab、每項一行。
           前一版的 CJK 與對齊在部分執行器輸出視窗會被打亂，
           導致無法判讀。

  用法：整份貼進執行器執行即可。不需要遊戲載入。
============================================================================ ]]

local probe = {
	{ Class = "TextButton", Members = {
		"FocusLost", "Focused", "ClearTextOnFocus", "PlaceholderText", "PlaceholderColor3",
		"MultiLine", "TextEditable", "SelectionImageObject",
		"Text", "TextSize", "TextWrapped", "TextTruncate", "TextScaled", "RichText",
		"AutoButtonColor", "MouseButton1Click", "MouseEnter"
	}},
	{ Class = "TextBox", Members = {
		"TextTruncate", "TextScaled",
		"FocusLost", "Focused", "ClearTextOnFocus", "PlaceholderText", "MultiLine"
	}},
	{ Class = "Frame", Members = {
		"Text", "TextColor3", "TextSize", "Font", "TextWrapped", "TextTruncate",
		"TextScaled", "RichText", "PlaceholderText", "PlaceholderColor3",
		"TextXAlignment", "TextYAlignment",
		"BackgroundColor3", "AutomaticSize", "ClipsDescendants",
		"AbsolutePosition", "AbsoluteSize", "GetPropertyChangedSignal"
	}},
	{ Class = "ScrollingFrame", Members = {
		"Text", "TextSize", "Font", "PlaceholderText",
		"CanvasSize", "CanvasPosition", "AbsoluteCanvasSize", "AutomaticCanvasSize",
		"ScrollBarThickness", "ScrollBarImageColor3", "GetPropertyChangedSignal"
	}},
	{ Class = "TextLabel", Members = {
		"FocusLost", "Focused", "ClearTextOnFocus", "PlaceholderText",
		"Text", "TextSize", "TextWrapped", "TextTruncate", "AutomaticSize", "TextBounds"
	}},
	{ Class = "UIStroke", Members = {
		"CornerRadius", "BackgroundColor3",
		"Color", "Thickness", "Transparency", "ApplyStrokeMode"
	}},
	{ Class = "UICorner", Members = {
		"Color", "Thickness", "Transparency",
		"CornerRadius"
	}},
	{ Class = "UIGradient", Members = {
		"Color3",
		"Color", "Transparency", "Rotation", "Enabled"
	}},
	{ Class = "UIListLayout", Members = {
		"Padding", "FillDirection", "HorizontalAlignment", "VerticalAlignment",
		"SortOrder", "HorizontalFlex", "Wraps"
	}},
	{ Class = "UIPadding", Members = {
		"PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight"
	}},
	{ Class = "UISizeConstraint", Members = { "MaxSize", "MinSize" }},
	{ Class = "ScreenGui", Members = {
		"Enabled", "DisplayOrder", "ResetOnSpawn", "IgnoreGuiInset", "ZIndexBehavior"
	}},
}

local parent = Instance.new("Folder")
local out = {}
local totalMissing = 0

local function emit(s) table.insert(out, s) end

emit("=== GUI member probe (v2) ===")
emit("")

for _, group in ipairs(probe) do
	local ok, inst = pcall(Instance.new, group.Class)
	if not ok or not inst then
		emit("CLASS " .. group.Class .. " : CANNOT_CREATE")
		totalMissing = totalMissing + 1
	else
		inst.Parent = parent
		local missing = {}
		local present = 0
		for _, member in ipairs(group.Members) do
			local readOk, value = pcall(function() return inst[member] end)
			if readOk and value ~= nil then
				present = present + 1
			else
				table.insert(missing, member)
			end
		end

		if #missing == 0 then
			emit("CLASS " .. group.Class .. " : OK (all " .. tostring(#group.Members) .. " present)")
		else
			emit("CLASS " .. group.Class .. " : " .. tostring(present) .. "/" ..
				tostring(#group.Members) .. " present, MISSING -> " .. table.concat(missing, " "))
			totalMissing = totalMissing + #missing
		end
	end
end

emit("")
emit("TOTAL_MISSING=" .. tostring(totalMissing))
emit("")
emit("How to read this:")
emit("  A line 'MISSING -> X' lists members that class does NOT have.")
emit("  Those are exactly the member names that crash if you use them.")
emit("  'OK' means every probed member exists on that class.")

parent:Destroy()
print(table.concat(out, "\n"))
