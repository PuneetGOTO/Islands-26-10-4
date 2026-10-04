--[[ ============================================================================
  Roblox GUI 屬性探測器
  ============================================================================
  用途：在 Roblox 中實際執行，確認每個 GUI 類別「真的有」哪些屬性／事件。
        用來避免「在錯誤的物件上用不存在的成員」這類錯誤
        （例如 TextButton 沒有 FocusLost）。

  用法：把本檔貼進執行器執行即可，結果會印在輸出視窗。
        不需要遊戲載入、不需要任何權限。
============================================================================ ]]

local probe = {
	{ Class = "TextButton", Members = {
		"FocusLost", "Focused", "ClearTextOnFocus", "PlaceholderText", "PlaceholderColor3",
		"Text", "TextColor3", "TextSize", "Font", "TextWrapped", "TextTruncate", "TextScaled",
		"RichText", "AutoButtonColor", "MultiLine", "TextEditable",
		"MouseButton1Click", "MouseButton1Down", "MouseButton1Up",
		"MouseEnter", "MouseLeave", "Activated", "SelectionImageObject"
	}},
	{ Class = "TextBox", Members = {
		"FocusLost", "Focused", "ClearTextOnFocus", "PlaceholderText", "PlaceholderColor3",
		"Text", "TextColor3", "TextSize", "Font", "TextWrapped", "TextTruncate", "TextScaled",
		"RichText", "MultiLine", "TextEditable", "SelectionStart", "CursorPosition",
		"ReturnPressedFromOnScreenKeyboard"
	}},
	{ Class = "Frame", Members = {
		"Text", "TextColor3", "TextSize", "Font", "TextWrapped", "TextTruncate",
		"PlaceholderText", "BackgroundColor3", "BackgroundTransparency",
		"AbsolutePosition", "AbsoluteSize", "AutomaticSize", "ClipsDescendants",
		"GetPropertyChangedSignal", "InputBegan", "InputChanged", "InputEnded"
	}},
	{ Class = "ScrollingFrame", Members = {
		"CanvasSize", "CanvasPosition", "AbsoluteCanvasSize", "AutomaticCanvasSize",
		"ScrollBarThickness", "ScrollBarImageColor3", "ScrollBarImageTransparency",
		"Text", "GetPropertyChangedSignal"
	}},
	{ Class = "TextLabel", Members = {
		"Text", "TextColor3", "TextSize", "Font", "TextWrapped", "TextTruncate",
		"TextScaled", "RichText", "AutomaticSize", "TextBounds", "FocusLost"
	}},
	{ Class = "UIStroke", Members = {
		"Color", "Thickness", "Transparency", "ApplyStrokeMode", "LineJoinMode",
		"CornerRadius", "BackgroundColor3"
	}},
	{ Class = "UICorner", Members = {
		"CornerRadius", "Color", "Thickness", "Transparency"
	}},
	{ Class = "UIGradient", Members = {
		"Color", "Color3", "Transparency", "Rotation", "Offset", "Enabled"
	}},
	{ Class = "UIListLayout", Members = {
		"Padding", "FillDirection", "HorizontalAlignment", "VerticalAlignment",
		"SortOrder", "HorizontalFlex", "VerticalFlex", "Wraps"
	}},
	{ Class = "UIPadding", Members = {
		"PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight"
	}},
	{ Class = "UISizeConstraint", Members = {
		"MaxSize", "MinSize"
	}},
	{ Class = "ScreenGui", Members = {
		"Enabled", "DisplayOrder", "ResetOnSpawn", "IgnoreGuiInset", "ZIndexBehavior"
	}},
}

local parent = Instance.new("Folder")
local report = {}
local problems = 0

table.insert(report, "=== Roblox GUI 成員探測結果 ===")
table.insert(report, "")

for _, group in ipairs(probe) do
	local ok, inst = pcall(Instance.new, group.Class)
	if not ok or not inst then
		table.insert(report, string.format("%-16s ❌ 無法建立", group.Class))
		problems = problems + 1
	else
		inst.Parent = parent
		local missing = {}
		for _, member in ipairs(group.Members) do
			-- 屬性用 rawget 檢查較快，但事件是實例成員，統一用 pcall 讀取
			local readOk, value = pcall(function() return inst[member] end)
			if not readOk or value == nil then
				table.insert(missing, member)
			end
		end
		if #missing == 0 then
			table.insert(report, string.format("%-16s ✅ 全部存在（%d 項）", group.Class, #group.Members))
		else
			table.insert(report, string.format("%-16s ⚠️ 不存在：%s", group.Class, table.concat(missing, ", ")))
			problems = problems + #missing
		end
	end
end

table.insert(report, "")
table.insert(report, problems == 0
	and "結果：所有探測的成員都存在。"
	or ("結果：共 " .. tostring(problems) .. " 個成員不存在（對應的就是會出錯的用法）。"))
table.insert(report, "")
table.insert(report, "重點對照：")
table.insert(report, "  TextButton 不該有 FocusLost / Focused / ClearTextOnFocus")
table.insert(report, "  Frame 不該有 Text / Font / TextSize")
table.insert(report, "  TextBox 不該有 TextTruncate / TextScaled")

parent:Destroy()
print(table.concat(report, "\n"))
