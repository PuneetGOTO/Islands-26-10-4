-- ==============================================================================
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
local PAYLOAD = [=[
--[[
================================================================================
  IDENTICAL UI — FLUENT 相容引擎  (FluentCompat)
================================================================================
  目的：提供與 Fluent / SaveManager / InterfaceManager 相同的 API 表面，
        讓既有呼叫端（IslandsScript.lua 約 4700 行 UI 建構程式）不必修改
        就能改跑到新的 Identical UI 引擎上。

  相容的 API 表面（依實際呼叫盤點，全部覆蓋）：
    Fluent:Notify{Title, Content, Duration}
    Fluent.Options / Fluent.Flags
    Fluent:CreateWindow{Title, SubTitle, TabWidth, Size, ToggleKey, MinimizeKey}
    Window:AddTab{Title, Icon} | Window:SelectTab(n) | Window:Dialog{...}
    Tab/Section:AddSection / AddParagraph / AddToggle / AddSlider / AddDropdown
                / AddButton / AddInput / AddKeybind / AddColorpicker
    控件: :OnChanged(fn) / :SetValue(v) / :SetValues(t) / :SetDesc(s)
          :SetTitle(s) / .Value / .Transparency

  設計原則：
    1. 完全不使用外部資源（無 require、無 HTTP），純 Instance 建立。
    2. 每個控件都以 Flag 名稱註冊到 Options，回呼可讀 Options.<Flag>.Value。
    3. 回呼一律以 pcall 保護，單一控件出錯不會讓整份 UI 建構中斷。
    4. 不汙染全域；只回傳一個表。
================================================================================
]]

local FluentCompat = {}

-- ==============================================================================
-- 服務
-- ==============================================================================
local cloneref = cloneref or function(o) return o end
local Players          = cloneref(game:GetService("Players"))
local RunService       = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TweenService     = cloneref(game:GetService("TweenService"))
local TextService      = cloneref(game:GetService("TextService"))
local CoreGui          = cloneref(game:GetService("CoreGui"))

local LocalPlayer = Players.LocalPlayer

-- ==============================================================================
-- 主題
-- ==============================================================================
local Theme = {
    Bg          = Color3.fromRGB(15, 12, 22),
    Sidebar     = Color3.fromRGB(11, 9, 17),
    Element     = Color3.fromRGB(24, 19, 35),
    ElementHov  = Color3.fromRGB(32, 25, 47),
    Border      = Color3.fromRGB(45, 33, 66),
    Divider     = Color3.fromRGB(36, 26, 54),
    Accent      = Color3.fromRGB(168, 85, 247),
    AccentSoft  = Color3.fromRGB(216, 160, 255),
    Muted       = Color3.fromRGB(130, 115, 160),
    Text        = Color3.fromRGB(243, 235, 255),
    TextSub     = Color3.fromRGB(186, 172, 212),
    TextDark    = Color3.fromRGB(80, 68, 100),
    On          = Color3.fromRGB(168, 85, 247),
    Off         = Color3.fromRGB(38, 30, 53),
    Danger      = Color3.fromRGB(255, 125, 125),
    DangerBg    = Color3.fromRGB(45, 20, 25),
    Overlay     = Color3.fromRGB(0, 0, 0)
}

local TweenFast = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ==============================================================================
-- 內部工具
-- ==============================================================================
local function RandName()
    return "FC_" .. tostring(math.random(100000, 999999))
end

local function Round(n)
    if n >= 0 then return math.floor(n + 0.5) end
    return -math.floor(-n + 0.5)
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[FluentCompat] callback error: " .. tostring(err))
    end
end

local function GetSafeParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok, res = pcall(function() return CoreGui end)
    if ok and res then return res end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function NewCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function NewStroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function NewLabel(parent, text, size, color, font)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.TextSize = size or 12
    l.TextColor3 = color or Theme.Text
    l.Font = font or Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

-- ==============================================================================
-- 根 ScreenGui（整個引擎只有一個）
-- ==============================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = RandName()
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 998 -- 略低於獨立版 Identical UI，避免互相蓋住
screenGui.Parent = GetSafeParent()

local uiConnections = {}
local function Track(conn)
    table.insert(uiConnections, conn)
    return conn
end

-- 目前展開的浮動面板（下拉選單 / 顏色選擇器），點空白處時統一關閉。
-- 必須在 CreateWindow 之前宣告：它會被多個控件閉包捕獲。
local OpenDropdowns = {}

-- ==============================================================================
-- 選項註冊表（Options / Flags）
-- ==============================================================================
local Options = {}
local Flags = {}
local registeredElements = {}

local function RegisterElement(id, element)
    -- 同名 Flag 重複註冊時保留最後一個（與 Fluent 行為一致）
    Options[id] = element
    Flags[id] = element
    table.insert(registeredElements, element)
    return element
end

-- 共用基底：所有控件都有 Value / OnChanged / SetValue / SetTitle / SetDesc
-- ctx.config 是原始 config 表；cfg.Callback 一律由 SetValue 統一觸發，
-- 這樣每個控件只要呼叫 el:SetValue(v) 就一定不會漏掉回呼。
local function ApplyCommonMethods(element, ctx)
    local config = ctx.config or {}
    element.Value = ctx.defaultValue
    element._listeners = {}
    element._firing = false

    element.OnChanged = function(self, fn)
        table.insert(self._listeners, fn)
        -- Fluent 的 OnChanged 會立刻以目前值呼叫一次
        if self.Value ~= nil then
            SafeCall(fn, self.Value)
        end
        return self
    end

    element.FireChanged = function(self, ...)
        for _, fn in ipairs(self._listeners) do
            SafeCall(fn, ...)
        end
    end

    element.SetValue = function(self, v, silent)
        self:SetValueInternal(v)
        if silent then return self end
        -- 防止回呼內又呼叫 SetValue 造成遞迴
        if self._firing then return self end
        self._firing = true
        SafeCall(config.Callback, self.Value)
        self:FireChanged(self.Value)
        self._firing = false
        return self
    end

    element.SetTitle = function(self, t)
        if self._titleLabel then
            self._titleLabel.Text = tostring(t)
        end
        self.Title = t
        return self
    end

    element.SetDesc = function(self, t)
        if self._descLabel then
            self._descLabel.Text = tostring(t)
            self._descLabel.Visible = true
        end
        self.Description = t
        return self
    end

    return element
end

-- ==============================================================================
-- 左側導覽按鈕（分頁）
-- ==============================================================================
local function CreateNavButton(parent, title, icon, order, onClick)
    local btn = Instance.new("TextButton")
    btn.Name = RandName()
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = Theme.ElementHov
    btn.BackgroundTransparency = 1
    btn.AutoButtonColor = false
    btn.Text = ""
    btn.LayoutOrder = order or 0
    btn.Parent = parent

    local indicator = Instance.new("Frame")
    indicator.Size = UDim2.new(0, 2.5, 0, 18)
    indicator.Position = UDim2.new(0, 0, 0.5, -9)
    indicator.BackgroundColor3 = Theme.Accent
    indicator.BorderSizePixel = 0
    indicator.Visible = false
    indicator.Parent = btn

    local iconLabel = NewLabel(btn, icon or "•", 13, Theme.Muted)
    iconLabel.Size = UDim2.new(0, 24, 1, 0)
    iconLabel.Position = UDim2.new(0, 10, 0, 0)
    iconLabel.TextXAlignment = Enum.TextXAlignment.Center

    local textLabel = NewLabel(btn, title or "Tab", 12, Theme.TextSub, Enum.Font.GothamMedium)
    textLabel.Size = UDim2.new(1, -48, 1, 0)
    textLabel.Position = UDim2.new(0, 38, 0, 0)
    textLabel.TextTruncate = Enum.TextTruncate.AtEnd

    btn.MouseEnter:Connect(function()
        if not btn:GetAttribute("Active") then
            TweenService:Create(btn, TweenFast, { BackgroundTransparency = 0.75 }):Play()
            TweenService:Create(textLabel, TweenFast, { TextColor3 = Theme.Text }):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        if not btn:GetAttribute("Active") then
            TweenService:Create(btn, TweenFast, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(textLabel, TweenFast, { TextColor3 = Theme.TextSub }):Play()
        end
    end)
    btn.MouseButton1Click:Connect(onClick)

    return {
        Button = btn,
        Indicator = indicator,
        Icon = iconLabel,
        Label = textLabel
    }
end

-- ==============================================================================
-- 標題列按鈕
-- ==============================================================================
local function CreateTitleButton(parent, text, order, hoverColor)
    local btn = Instance.new("TextButton")
    btn.Name = RandName()
    btn.Size = UDim2.new(0, 28, 0, 28)
    btn.Position = UDim2.new(1, -(34 + (order - 1) * 30), 0.5, -14)
    btn.BackgroundColor3 = hoverColor
    btn.BackgroundTransparency = 1
    btn.AutoButtonColor = false
    btn.Text = text
    btn.TextColor3 = Theme.TextSub
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamMedium
    btn.Parent = parent
    NewCorner(btn, 5)

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenFast, { BackgroundTransparency = 0, TextColor3 = Theme.Text }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenFast, { BackgroundTransparency = 1, TextColor3 = Theme.TextSub }):Play()
    end)
    return btn
end

-- ==============================================================================
-- 全域通知（Fluent:Notify）
-- ==============================================================================
local notifyHolder = Instance.new("Frame")
notifyHolder.Name = RandName()
notifyHolder.Size = UDim2.new(0, 300, 1, -40)
notifyHolder.Position = UDim2.new(1, -320, 0, 20)
notifyHolder.BackgroundTransparency = 1
notifyHolder.ZIndex = 900
notifyHolder.Parent = screenGui

local notifyLayout = Instance.new("UIListLayout")
notifyLayout.Padding = UDim.new(0, 8)
notifyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifyLayout.VerticalAlignment = Enum.VerticalAlignment.Top
notifyLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifyLayout.Parent = notifyHolder

local notifyOrder = 0

local function Notify(config)
    config = config or {}
    notifyOrder = notifyOrder + 1

    local toast = Instance.new("Frame")
    toast.Name = RandName()
    toast.Size = UDim2.new(1, 0, 0, 52)
    toast.BackgroundColor3 = Color3.fromRGB(20, 15, 30)
    toast.BackgroundTransparency = 1
    toast.BorderSizePixel = 0
    toast.LayoutOrder = notifyOrder
    toast.ZIndex = 901
    toast.Parent = notifyHolder
    NewCorner(toast, 6)

    local stroke = NewStroke(toast, Theme.Accent, 1)
    stroke.Transparency = 1

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 2, 1, -18)
    bar.Position = UDim2.new(0, 0, 0, 9)
    bar.BackgroundColor3 = Theme.Accent
    bar.BorderSizePixel = 0
    bar.ZIndex = 902
    bar.Parent = toast

    local titleLabel = NewLabel(toast, tostring(config.Title or ""), 12, Theme.Text, Enum.Font.GothamBold)
    titleLabel.Size = UDim2.new(1, -22, 0, 18)
    titleLabel.Position = UDim2.new(0, 12, 0, 7)
    titleLabel.TextTransparency = 1
    titleLabel.ZIndex = 902

    local contentLabel = NewLabel(toast, tostring(config.Content or ""), 11, Theme.TextSub)
    contentLabel.Size = UDim2.new(1, -22, 0, 18)
    contentLabel.Position = UDim2.new(0, 12, 0, 27)
    contentLabel.TextTransparency = 1
    contentLabel.TextTruncate = Enum.TextTruncate.AtEnd
    contentLabel.ZIndex = 902

    toast.Position = UDim2.new(1, 40, 0, 0)
    TweenService:Create(toast, TweenFast, {
        BackgroundTransparency = 0,
        Position = UDim2.new(0, 0, 0, 0)
    }):Play()
    TweenService:Create(stroke, TweenFast, { Transparency = 0 }):Play()
    TweenService:Create(titleLabel, TweenFast, { TextTransparency = 0 }):Play()
    TweenService:Create(contentLabel, TweenFast, { TextTransparency = 0 }):Play()

    local duration = tonumber(config.Duration) or 5
    task.delay(duration, function()
        if not toast.Parent then return end
        local out = TweenService:Create(toast, TweenFast, {
            BackgroundTransparency = 1,
            Position = UDim2.new(1, 40, 0, 0)
        })
        TweenService:Create(stroke, TweenFast, { Transparency = 1 }):Play()
        TweenService:Create(titleLabel, TweenFast, { TextTransparency = 1 }):Play()
        TweenService:Create(contentLabel, TweenFast, { TextTransparency = 1 }):Play()
        out:Play()
        out.Completed:Connect(function() toast:Destroy() end)
    end)

    return toast
end

-- ==============================================================================
-- 視窗
-- ==============================================================================
local function CreateWindow(root, config)
    config = config or {}

    local windowW = 720
    local windowH = 480
    local sidebarW = tonumber(config.TabWidth) or 180

    local main = Instance.new("Frame")
    main.Name = RandName()
    main.Size = UDim2.new(0, windowW, 0, windowH)
    main.Position = UDim2.new(0.5, -Round(windowW / 2), 0.5, -Round(windowH / 2))
    main.BackgroundColor3 = Theme.Bg
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = screenGui
    NewCorner(main, 10)
    local mainStroke = NewStroke(main, Theme.Accent, 1.2)

    -- 投影
    local shadow = Instance.new("Frame")
    shadow.Name = RandName()
    shadow.Size = UDim2.new(1, 16, 1, 20)
    shadow.Position = UDim2.new(0, -8, 0, -4)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.55
    shadow.BorderSizePixel = 0
    shadow.ZIndex = -1
    shadow.Parent = main
    NewCorner(shadow, 16)

    local TOPBAR = 40
    local FOOTER = 26

    -- 標題列
    local topBar = Instance.new("Frame")
    topBar.Name = RandName()
    topBar.Size = UDim2.new(1, 0, 0, TOPBAR)
    topBar.BackgroundTransparency = 1
    topBar.Parent = main

    local crest = Instance.new("Frame")
    crest.Size = UDim2.new(0, 22, 0, 22)
    crest.Position = UDim2.new(0, 14, 0.5, -11)
    crest.BackgroundColor3 = Theme.Element
    crest.BorderSizePixel = 0
    crest.Parent = topBar
    NewCorner(crest, 11)
    NewStroke(crest, Theme.Accent, 1)
    local crestLabel = NewLabel(crest, "I", 11, Theme.AccentSoft, Enum.Font.GothamBold)
    crestLabel.Size = UDim2.new(1, 0, 1, 0)
    crestLabel.TextXAlignment = Enum.TextXAlignment.Center

    local titleLabel = NewLabel(topBar, tostring(config.Title or "Interface"), 13,
        Color3.fromRGB(230, 205, 255), Enum.Font.GothamBold)
    titleLabel.Size = UDim2.new(1, -300, 1, 0)
    titleLabel.Position = UDim2.new(0, 46, 0, 0)
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local subTitleLabel = NewLabel(topBar, tostring(config.SubTitle or ""), 11, Theme.Muted)
    subTitleLabel.Size = UDim2.new(0, 160, 1, 0)
    subTitleLabel.Position = UDim2.new(1, -200, 0, 0)
    subTitleLabel.TextXAlignment = Enum.TextXAlignment.Right
    subTitleLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local closeBtn = CreateTitleButton(topBar, "✕", 1, Color3.fromRGB(70, 26, 36))
    local minBtn = CreateTitleButton(topBar, "—", 2, Color3.fromRGB(38, 28, 56))

    local topDivider = Instance.new("Frame")
    topDivider.Size = UDim2.new(1, 0, 0, 1)
    topDivider.Position = UDim2.new(0, 0, 0, TOPBAR)
    topDivider.BackgroundColor3 = Theme.Divider
    topDivider.BorderSizePixel = 0
    topDivider.Parent = main

    -- 內容裁切層
    local clip = Instance.new("Frame")
    clip.Name = RandName()
    clip.Size = UDim2.new(1, 0, 1, 0)
    clip.BackgroundTransparency = 1
    clip.ClipsDescendants = true
    clip.Parent = main
    local clipPad = Instance.new("UIPadding")
    clipPad.PaddingTop = UDim.new(0, 4)
    clipPad.PaddingBottom = UDim.new(0, 4)
    clipPad.PaddingLeft = UDim.new(0, 4)
    clipPad.PaddingRight = UDim.new(0, 4)
    clipPad.Parent = clip

    -- 側邊欄
    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, sidebarW, 1, 0)
    sidebar.BackgroundColor3 = Theme.Sidebar
    sidebar.BorderSizePixel = 0
    sidebar.Parent = clip

    local sideDivider = Instance.new("Frame")
    sideDivider.Size = UDim2.new(0, 1, 1, 0)
    sideDivider.Position = UDim2.new(0, sidebarW, 0, 0)
    sideDivider.BackgroundColor3 = Theme.Divider
    sideDivider.BorderSizePixel = 0
    sideDivider.Parent = clip

    local navScroll = Instance.new("ScrollingFrame")
    navScroll.Name = RandName()
    navScroll.Size = UDim2.new(1, 0, 1, -12)
    navScroll.Position = UDim2.new(0, 0, 0, 6)
    navScroll.BackgroundTransparency = 1
    navScroll.BorderSizePixel = 0
    navScroll.ScrollBarThickness = 3
    navScroll.ScrollBarImageColor3 = Theme.Accent
    navScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    navScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    navScroll.Parent = sidebar

    local navLayout = Instance.new("UIListLayout")
    navLayout.Padding = UDim.new(0, 2)
    navLayout.SortOrder = Enum.SortOrder.LayoutOrder
    navLayout.Parent = navScroll

    -- 內容區
    local bodyFrame = Instance.new("Frame")
    bodyFrame.Size = UDim2.new(1, -sidebarW, 1, -(TOPBAR + 1 + FOOTER))
    bodyFrame.Position = UDim2.new(0, sidebarW, 0, TOPBAR + 1)
    bodyFrame.BackgroundTransparency = 1
    bodyFrame.Parent = clip

    local footerBar = Instance.new("Frame")
    footerBar.Size = UDim2.new(1, 0, 0, FOOTER)
    footerBar.Position = UDim2.new(0, 0, 1, -FOOTER)
    footerBar.BackgroundColor3 = Theme.Bg
    footerBar.BorderSizePixel = 0
    footerBar.Parent = clip

    local footerDivider = Instance.new("Frame")
    footerDivider.Size = UDim2.new(1, 0, 0, 1)
    footerDivider.BackgroundColor3 = Theme.Divider
    footerDivider.BorderSizePixel = 0
    footerDivider.Parent = footerBar

    local footerLeft = NewLabel(footerBar, "Ready", 10, Theme.TextDark, Enum.Font.GothamMedium)
    footerLeft.Size = UDim2.new(0, 240, 1, 0)
    footerLeft.Position = UDim2.new(0, 12, 0, 0)

    local footerRight = NewLabel(footerBar, "IDENTICAL ENGINE", 10, Theme.TextDark, Enum.Font.GothamBold)
    footerRight.Size = UDim2.new(0, 220, 1, 0)
    footerRight.Position = UDim2.new(1, -232, 0, 0)
    footerRight.TextXAlignment = Enum.TextXAlignment.Right

    -- 拖曳
    local dragging, dragStart, startPos, dragInput
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
            dragInput = input
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    local p = main.Position
                    main.Position = UDim2.new(p.X.Scale, Round(p.X.Offset), p.Y.Scale, Round(p.Y.Offset))
                end
            end)
        end
    end)
    main.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    Track(UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and dragStart then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))

    -- 最小化
    local minimized = false
    local normalSize = main.Size
    local function setMinimized(v)
        if v == minimized then return end
        minimized = v
        if minimized then
            normalSize = main.Size
            bodyFrame.Visible = false
            footerBar.Visible = false
            topDivider.Visible = false
            TweenService:Create(main, TweenFast, {
                Size = UDim2.new(normalSize.X.Scale, normalSize.X.Offset, 0, TOPBAR)
            }):Play()
        else
            bodyFrame.Visible = true
            footerBar.Visible = true
            topDivider.Visible = true
            TweenService:Create(main, TweenFast, { Size = normalSize }):Play()
        end
    end
    minBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)

    local lastTopClick = 0
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local now = os.clock()
            if now - lastTopClick < 0.32 then
                setMinimized(not minimized)
                lastTopClick = 0
            else
                lastTopClick = now
            end
        end
    end)

    -- 分頁
    local tabs = {}
    local tabButtons = {}
    local tabOrder = 0
    local currentTab = nil

    local function SwitchTabByKey(key)
        if not tabs[key] then return end
        currentTab = key
        for k, page in pairs(tabs) do
            page.Visible = (k == key)
        end
        for k, data in pairs(tabButtons) do
            local active = (k == key)
            data.Button:SetAttribute("Active", active)
            data.Indicator.Visible = active
            data.Button.BackgroundTransparency = active and 0.65 or 1
            data.Label.TextColor3 = active and Theme.AccentSoft or Theme.TextSub
            data.Icon.TextColor3 = active and Theme.AccentSoft or Theme.Muted
        end
        footerLeft.Text = tostring(key)
    end

    -- 分頁排序索引，讓 SelectTab(n) 可用
    local tabIndexOrder = {}

    local function AddTab(tabConfig)
        tabConfig = tabConfig or {}
        tabOrder = tabOrder + 1
        local key = "Tab" .. tostring(tabOrder)

        local page = Instance.new("ScrollingFrame")
        page.Name = RandName()
        page.Size = UDim2.new(1, -24, 1, -16)
        page.Position = UDim2.new(0, 12, 0, 8)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 3
        page.ScrollBarImageColor3 = Theme.Accent
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false
        page.Parent = bodyFrame

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 8)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = page

        local pad = Instance.new("UIPadding")
        pad.PaddingBottom = UDim.new(0, 16)
        pad.Parent = page

        local navData = CreateNavButton(navScroll, tabConfig.Title or key,
            tabConfig.Icon, tabOrder, function() SwitchTabByKey(key) end)
        tabButtons[key] = navData
        tabs[key] = page

        local sectionOrder = 0
        local methods = {}

        methods.AddSection = function(self, sectionTitle)
            sectionOrder = sectionOrder + 1
            local section = Instance.new("Frame")
            section.Name = RandName()
            section.Size = UDim2.new(1, 0, 0, 0)
            section.AutomaticSize = Enum.AutomaticSize.Y
            section.BackgroundColor3 = Color3.fromRGB(19, 15, 28)
            section.BorderSizePixel = 0
            section.LayoutOrder = sectionOrder
            section.Parent = page
            NewCorner(section, 6)
            NewStroke(section, Theme.Border, 1)

            local spad = Instance.new("UIPadding")
            spad.PaddingTop = UDim.new(0, 10)
            spad.PaddingBottom = UDim.new(0, 10)
            spad.PaddingLeft = UDim.new(0, 10)
            spad.PaddingRight = UDim.new(0, 10)
            spad.Parent = section

            local slayout = Instance.new("UIListLayout")
            slayout.Padding = UDim.new(0, 6)
            slayout.SortOrder = Enum.SortOrder.LayoutOrder
            slayout.Parent = section

            local head = NewLabel(section, tostring(sectionTitle or ""):upper(), 11, Theme.Accent, Enum.Font.GothamBold)
            head.Size = UDim2.new(1, 0, 0, 18)
            head.LayoutOrder = 0

            return BuildElementHost(section, slayout)
        end

        methods.AddParagraph = function(self, paragraphConfig)
            paragraphConfig = paragraphConfig or {}
            sectionOrder = sectionOrder + 1
            local holder = Instance.new("Frame")
            holder.Name = RandName()
            holder.Size = UDim2.new(1, 0, 0, 0)
            holder.AutomaticSize = Enum.AutomaticSize.Y
            holder.BackgroundTransparency = 1
            holder.LayoutOrder = sectionOrder -- 與其他元素共用同一序號，保留插入順序
            holder.Parent = page

            local pl = Instance.new("UIListLayout")
            pl.Padding = UDim.new(0, 3)
            pl.SortOrder = Enum.SortOrder.LayoutOrder
            pl.Parent = holder

            local t = NewLabel(holder, tostring(paragraphConfig.Title or ""), 12, Theme.Text, Enum.Font.GothamMedium)
            t.Size = UDim2.new(1, 0, 0, 16)
            t.LayoutOrder = 1
            t.TextWrapped = true
            t.AutomaticSize = Enum.AutomaticSize.Y

            local d = NewLabel(holder, tostring(paragraphConfig.Content or paragraphConfig.Description or ""),
                11, Theme.TextSub)
            d.Size = UDim2.new(1, 0, 0, 14)
            d.LayoutOrder = 2
            d.TextWrapped = true
            d.AutomaticSize = Enum.AutomaticSize.Y

            local el = {
                Instance = holder,
                Title = paragraphConfig.Title,
                Description = paragraphConfig.Content,
                _titleLabel = t,
                _descLabel = d
            }
            el.SetDesc = function(self, v)
                d.Text = tostring(v)
                return self
            end
            el.SetTitle = function(self, v)
                t.Text = tostring(v)
                return self
            end
            el.SetValue = function(self) return self end
            return el
        end

        -- 分頁層級也直接具備控件方法（Tab:AddToggle 形式）
        local pageHost = BuildElementHost(page, layout)
        for k, v in pairs(methods) do
            pageHost[k] = v
        end
        pageHost._isTab = true
        pageHost.Title = tabConfig.Title

        table.insert(tabIndexOrder, key)
        return pageHost
    end

    -- 建立「控件宿主」：任何容器（分頁或區塊）都用同一組 Add* 方法
    local hostCache = {}
    function BuildElementHost(container, layoutInst)
        if hostCache[container] then return hostCache[container] end

        local order = 0
        local host = {}

        local function nextOrder()
            order = order + 1
            return order
        end

        -- 建立列的共用外框
        local function makeRow(height, hasFlag)
            local row = Instance.new("Frame")
            row.Name = RandName()
            row.Size = UDim2.new(1, 0, 0, height)
            row.BackgroundColor3 = Theme.Element
            row.BackgroundTransparency = 1
            row.BorderSizePixel = 0
            row.LayoutOrder = nextOrder()
            row.Parent = container
            if not hasFlag then
                NewCorner(row, 4)
            end
            return row
        end

        -- 標題 + 說明
        local function attachText(row, cfg, widthScale)
            local t = NewLabel(row, tostring(cfg.Title or cfg.Flag or ""), 12, Theme.Text, Enum.Font.GothamMedium)
            t.Size = UDim2.new(widthScale or 0.62, 0, 0, 16)
            t.Position = UDim2.new(0, 2, 0, 6)
            t.TextTruncate = Enum.TextTruncate.AtEnd

            local d = nil
            if cfg.Description and cfg.Description ~= "" then
                d = NewLabel(row, tostring(cfg.Description), 10, Theme.Muted)
                d.Size = UDim2.new(widthScale or 0.62, 0, 0, 12)
                d.Position = UDim2.new(0, 2, 0, 23)
                d.TextTruncate = Enum.TextTruncate.AtEnd
            end
            return t, d
        end

        -- ---------------- 開關 ----------------
        host.AddToggle = function(_, id, cfg)
            cfg = cfg or {}
            -- Fluent 的欄位名是 Default；同時容忍小寫 default
            local initialState = cfg.Default
            if initialState == nil then initialState = cfg.default end
            initialState = initialState and true or false

            local row = makeRow(40)
            attachText(row, cfg)

            local track = Instance.new("TextButton")
            track.Name = RandName()
            track.Size = UDim2.new(0, 36, 0, 18)
            track.Position = UDim2.new(1, -42, 0, 11)
            track.BackgroundColor3 = initialState and Theme.On or Theme.Off
            track.AutoButtonColor = false
            track.Text = ""
            track.Parent = row
            NewCorner(track, 9)
            local stroke = NewStroke(track, Theme.Border, 1)

            local knob = Instance.new("Frame")
            knob.Size = UDim2.new(0, 14, 0, 14)
            knob.Position = initialState and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
            knob.BackgroundColor3 = initialState and Color3.fromRGB(255, 255, 255) or Theme.Muted
            knob.BorderSizePixel = 0
            knob.Parent = track
            NewCorner(knob, 3)

            local el = {
                Instance = row,
                Type = "Toggle",
                Flag = id,
                Title = cfg.Title,
                Description = cfg.Description,
                _row = row,
                _titleLabel = row:FindFirstChildOfClass("TextLabel")
            }
            el._titleLabel = nil
            for _, c in ipairs(row:GetChildren()) do
                if c:IsA("TextLabel") then el._titleLabel = c break end
            end

            ApplyCommonMethods(el, { defaultValue = initialState, config = cfg })

            el.SetValueInternal = function(self, v)
                local on = v and true or false
                self.Value = on
                TweenService:Create(knob, TweenFast, {
                    Position = on and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7),
                    BackgroundColor3 = on and Color3.fromRGB(255, 255, 255) or Theme.Muted
                }):Play()
                TweenService:Create(track, TweenFast, {
                    BackgroundColor3 = on and Theme.On or Theme.Off
                }):Play()
            end

            track.MouseButton1Click:Connect(function()
                el:SetValue(not el.Value)
            end)

            RegisterElement(id, el)
            return el
        end

        -- ---------------- 滑桿 ----------------
        host.AddSlider = function(_, id, cfg)
            cfg = cfg or {}
            local minV = tonumber(cfg.Min) or 0
            local maxV = tonumber(cfg.Max) or 100
            if maxV <= minV then maxV = minV + 1 end
            local rounding = tonumber(cfg.Rounding) or 0
            local def = math.clamp(tonumber(cfg.Default) or minV, minV, maxV)

            local row = makeRow(48)
            attachText(row, cfg)

            local valueLabel = NewLabel(row, "", 11, Theme.Text, Enum.Font.GothamMedium)
            valueLabel.Size = UDim2.new(0, 90, 0, 16)
            valueLabel.Position = UDim2.new(1, -100, 0, 6)
            valueLabel.TextXAlignment = Enum.TextXAlignment.Right

            local holder = Instance.new("Frame")
            holder.Size = UDim2.new(1, -12, 0, 18)
            holder.Position = UDim2.new(0, 6, 0, 26)
            holder.BackgroundTransparency = 1
            holder.Parent = row

            local track = Instance.new("Frame")
            track.Size = UDim2.new(1, 0, 0, 3)
            track.Position = UDim2.new(0, 0, 0.5, -1.5)
            track.BackgroundColor3 = Color3.fromRGB(38, 30, 53)
            track.BorderSizePixel = 0
            track.Parent = holder
            NewCorner(track, 2)

            local fill = Instance.new("Frame")
            fill.Size = UDim2.new(0, 0, 1, 0)
            fill.BackgroundColor3 = Theme.Accent
            fill.BorderSizePixel = 0
            fill.Parent = track
            NewCorner(fill, 2)

            local knob = Instance.new("Frame")
            knob.Size = UDim2.new(0, 11, 0, 11)
            knob.AnchorPoint = Vector2.new(0.5, 0.5)
            knob.Position = UDim2.new(0, 0, 0.5, 0)
            knob.BackgroundColor3 = Theme.AccentSoft
            knob.BorderSizePixel = 0
            knob.Parent = fill
            NewCorner(knob, 6)

            local function fmt(v)
                if rounding > 0 then
                    local mult = 10 ^ rounding
                    return string.format("%." .. tostring(rounding) .. "f", v)
                end
                return tostring(Round(v))
            end

            local el = {
                Instance = row,
                Type = "Slider",
                Flag = id,
                Title = cfg.Title,
                Description = cfg.Description,
                _row = row,
                _titleLabel = nil
            }
            for _, c in ipairs(row:GetChildren()) do
                if c:IsA("TextLabel") then el._titleLabel = c break end
            end

            ApplyCommonMethods(el, { defaultValue = def, config = cfg })

            local function applyVisual()
                local pct = (el.Value - minV) / (maxV - minV)
                fill.Size = UDim2.new(pct, 0, 1, 0)
                valueLabel.Text = fmt(el.Value)
            end

            el.SetValueInternal = function(self, v)
                local num = tonumber(v) or minV
                if rounding > 0 then
                    local mult = 10 ^ rounding
                    num = Round(num * mult) / mult
                else
                    num = Round(num)
                end
                self.Value = math.clamp(num, minV, maxV)
                applyVisual()
            end

            local sliding = false
            local function setFromInput(input)
                local absPos = track.AbsolutePosition
                local width = track.AbsoluteSize.X
                if width <= 1 then return end
                local rel = math.clamp((input.Position.X - absPos.X) / width, 0, 1)
                -- 走統一的 SetValue，確保 cfg.Callback 與 OnChanged 都會被觸發
                el:SetValue(minV + rel * (maxV - minV))
            end

            local hit = Instance.new("TextButton")
            hit.Size = UDim2.new(1, 20, 1, 20)
            hit.Position = UDim2.new(0, -10, 0.5, -10)
            hit.BackgroundTransparency = 1
            hit.Text = ""
            hit.Parent = holder
            hit.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = true
                    setFromInput(input)
                end
            end)
            Track(UserInputService.InputChanged:Connect(function(input)
                if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch) then
                    setFromInput(input)
                end
            end))
            Track(UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    sliding = false
                end
            end))

            applyVisual()
            RegisterElement(id, el)
            return el
        end

        -- ---------------- 下拉選單 ----------------
        host.AddDropdown = function(_, id, cfg)
            cfg = cfg or {}
            local values = cfg.Values or {}
            local multi = cfg.Multi and true or false

            local row = makeRow(44)
            attachText(row, cfg)

            local selected = nil
            if multi then
                selected = {}
                local def = cfg.Default
                if type(def) == "table" then
                    for k, v in pairs(def) do selected[k] = v end
                    -- 陣列形式的預設值
                    for _, v in ipairs(def) do selected[v] = true end
                elseif type(def) == "string" then
                    selected[def] = true
                end
            else
                if type(cfg.Default) == "table" then
                    selected = cfg.Default[1]
                else
                    selected = cfg.Default
                end
                if selected == nil then selected = values[1] end
            end

            local box = Instance.new("TextButton")
            box.Name = RandName()
            box.Size = UDim2.new(0, sidebarW and 170 or 170, 0, 28)
            box.Position = UDim2.new(1, -176, 0, 8)
            box.BackgroundColor3 = Color3.fromRGB(13, 10, 20)
            box.AutoButtonColor = false
            box.Text = ""
            box.ZIndex = 6
            box.Parent = row
            NewCorner(box, 4)
            local boxStroke = NewStroke(box, Theme.Border, 1)

            local boxLabel = NewLabel(box, "", 11, Theme.Text)
            boxLabel.Size = UDim2.new(1, -30, 1, 0)
            boxLabel.Position = UDim2.new(0, 10, 0, 0)
            boxLabel.TextTruncate = Enum.TextTruncate.AtEnd
            boxLabel.ZIndex = 7

            local chevron = NewLabel(box, "▾", 12, Theme.Muted, Enum.Font.GothamBold)
            chevron.Size = UDim2.new(0, 20, 1, 0)
            chevron.Position = UDim2.new(1, -24, 0, 0)
            chevron.ZIndex = 7

            -- 浮動清單（掛在 main 上，才能蓋過捲動區）
            local list = Instance.new("Frame")
            list.Name = RandName()
            list.BackgroundColor3 = Color3.fromRGB(13, 10, 20)
            list.BorderSizePixel = 0
            list.Visible = false
            list.ZIndex = 500
            list.Parent = main
            NewCorner(list, 4)
            NewStroke(list, Theme.Accent, 1)

            local scroll = Instance.new("ScrollingFrame")
            scroll.Size = UDim2.new(1, -4, 1, -4)
            scroll.Position = UDim2.new(0, 2, 0, 2)
            scroll.BackgroundTransparency = 1
            scroll.BorderSizePixel = 0
            scroll.ScrollBarThickness = 3
            scroll.ScrollBarImageColor3 = Theme.Accent
            scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            scroll.ZIndex = 501
            scroll.Parent = list

            local listLayout = Instance.new("UIListLayout")
            listLayout.Padding = UDim.new(0, 1)
            listLayout.SortOrder = Enum.SortOrder.LayoutOrder
            listLayout.Parent = scroll

            local ITEM_H = 24
            local MAX_VISIBLE = 8

            local el = {
                Instance = row,
                Type = "Dropdown",
                Flag = id,
                Title = cfg.Title,
                Description = cfg.Description,
                Multi = multi,
                _row = row,
                _titleLabel = nil
            }
            for _, c in ipairs(row:GetChildren()) do
                if c:IsA("TextLabel") then el._titleLabel = c break end
            end

            local defaultValue
            if multi then
                defaultValue = {}
                for k, v in pairs(selected) do
                    if v then table.insert(defaultValue, k) end
                end
            else
                defaultValue = selected
            end
            ApplyCommonMethods(el, { defaultValue = defaultValue, config = cfg })

            local itemButtons = {}

            local function summarize()
                if multi then
                    local parts = {}
                    for _, v in ipairs(values) do
                        if selected[v] then table.insert(parts, tostring(v)) end
                    end
                    if #parts == 0 then return "(none)" end
                    if #parts <= 2 then return table.concat(parts, ", ") end
                    return parts[1] .. " +" .. tostring(#parts - 1)
                end
                return tostring(selected or "(none)")
            end

            local function refreshVisual(exceptKey)
                boxLabel.Text = summarize()
                for name, btn in pairs(itemButtons) do
                    if name ~= exceptKey then
                        local on = multi and selected[name] or (name == selected)
                        btn.TextColor3 = on and Theme.AccentSoft or Theme.TextSub
                        btn.BackgroundTransparency = 1
                    end
                end
            end

            local function currentValue()
                if multi then
                    local out = {}
                    for _, v in ipairs(values) do
                        if selected[v] then table.insert(out, v) end
                    end
                    return out
                end
                return selected
            end

            el.SetValueInternal = function(self, v)
                if multi then
                    selected = {}
                    if type(v) == "table" then
                        for k, val in pairs(v) do
                            if type(k) == "number" then selected[val] = true else selected[k] = val and true or false end
                        end
                    elseif type(v) == "string" then
                        selected[v] = true
                    end
                    self.Value = currentValue()
                else
                    if type(v) == "table" then v = v[1] end
                    selected = v
                    self.Value = v
                end
                refreshVisual()
            end

            local function layoutList()
                local count = math.max(#values, 1)
                local visible = math.min(count, MAX_VISIBLE)
                list.Size = UDim2.new(0, box.AbsoluteSize.X, 0, visible * ITEM_H + 6)
                scroll.CanvasSize = UDim2.new(0, 0, 0, count * ITEM_H)
                local absBox = box.AbsolutePosition
                local absMain = main.AbsolutePosition
                local x = absBox.X - absMain.X
                local y = absBox.Y - absMain.Y + box.AbsoluteSize.Y + 3
                local listH = list.AbsoluteSize.Y
                if y + listH > main.AbsoluteSize.Y - 6 then
                    local above = (absBox.Y - absMain.Y) - listH - 3
                    y = (above >= 4) and above or math.max(4, main.AbsoluteSize.Y - 6 - listH)
                end
                list.Position = UDim2.new(0, Round(x), 0, Round(y))
            end

            local function setOpen(open)
                list.Visible = open
                chevron.Text = open and "▴" or "▾"
                TweenService:Create(boxStroke, TweenFast, {
                    Color = open and Theme.Accent or Theme.Border
                }):Play()
                if open then
                    layoutList()
                    OpenDropdowns[list] = function() setOpen(false) end
                else
                    OpenDropdowns[list] = nil
                end
            end

            local function rebuildItems()
                for _, b in pairs(itemButtons) do b:Destroy() end
                itemButtons = {}
                for index, name in ipairs(values) do
                    local btn = Instance.new("TextButton")
                    btn.Size = UDim2.new(1, 0, 0, ITEM_H)
                    btn.BackgroundColor3 = Theme.ElementHov
                    btn.BackgroundTransparency = 1
                    btn.AutoButtonColor = false
                    btn.Text = "   " .. tostring(name)
                    btn.TextSize = 11
                    btn.Font = Enum.Font.Gotham
                    btn.TextXAlignment = Enum.TextXAlignment.Left
                    btn.TextTruncate = Enum.TextTruncate.AtEnd
                    btn.LayoutOrder = index
                    btn.ZIndex = 502
                    btn.Parent = scroll

                    btn.MouseEnter:Connect(function()
                        btn.BackgroundTransparency = 0
                        btn.TextColor3 = Theme.AccentSoft
                    end)
                    btn.MouseLeave:Connect(function()
                        btn.BackgroundTransparency = 1
                        local on = multi and selected[name] or (name == selected)
                        btn.TextColor3 = on and Theme.AccentSoft or Theme.TextSub
                    end)
                    btn.MouseButton1Click:Connect(function()
                        if multi then
                            selected[name] = not selected[name]
                            el:SetValue(currentValue())
                        else
                            selected = name
                            setOpen(false)
                            el:SetValue(name)
                        end
                    end)
                    itemButtons[name] = btn
                end
                refreshVisual()
            end

            el.SetValues = function(self, newValues)
                values = newValues or {}
                rebuildItems()
                layoutList()
                return self
            end

            rebuildItems()
            el.Value = currentValue()

            box.MouseButton1Click:Connect(function()
                setOpen(not list.Visible)
            end)

            -- 捲動／尺寸變化時重貼齊
            container:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
                if list.Visible then layoutList() end
            end)
            if container:IsA("ScrollingFrame") then
                container:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                    if list.Visible then layoutList() end
                end)
            end

            RegisterElement(id, el)
            return el
        end

        -- ---------------- 按鈕 ----------------
        host.AddButton = function(_, cfg)
            cfg = cfg or {}
            local row = makeRow(40)

            local btn = Instance.new("TextButton")
            btn.Name = RandName()
            btn.Size = UDim2.new(1, 0, 0, 34)
            btn.Position = UDim2.new(0, 0, 0, 0)
            btn.BackgroundColor3 = Theme.Element
            btn.AutoButtonColor = false
            btn.Text = ""
            btn.Parent = row
            NewCorner(btn, 5)
            local stroke = NewStroke(btn, Theme.Border, 1)

            local t = NewLabel(btn, tostring(cfg.Title or "Button"), 12, Theme.Text, Enum.Font.GothamMedium)
            t.Size = UDim2.new(1, -16, 0, 16)
            t.Position = UDim2.new(0, 10, 0, cfg.Description ~= "" and 4 or 9)
            t.TextTruncate = Enum.TextTruncate.AtEnd

            local d = nil
            if cfg.Description and cfg.Description ~= "" then
                d = NewLabel(btn, tostring(cfg.Description), 10, Theme.Muted)
                d.Size = UDim2.new(1, -16, 0, 12)
                d.Position = UDim2.new(0, 10, 0, 20)
                d.TextTruncate = Enum.TextTruncate.AtEnd
                row.Size = UDim2.new(1, 0, 0, 46)
            end

            btn.MouseEnter:Connect(function()
                TweenService:Create(btn, TweenFast, { BackgroundColor3 = Theme.ElementHov }):Play()
                TweenService:Create(stroke, TweenFast, { Color = Theme.Accent }):Play()
            end)
            btn.MouseLeave:Connect(function()
                TweenService:Create(btn, TweenFast, { BackgroundColor3 = Theme.Element }):Play()
                TweenService:Create(stroke, TweenFast, { Color = Theme.Border }):Play()
            end)
            btn.MouseButton1Click:Connect(function()
                SafeCall(cfg.Callback)
            end)

            local el = {
                Instance = row,
                Type = "Button",
                Title = cfg.Title,
                Description = cfg.Description,
                _row = row,
                _titleLabel = t,
                _descLabel = d,
                Value = nil,
                OnChanged = function(self) return self end,
                SetValue = function(self) return self end,
                SetTitle = function(self, v) t.Text = tostring(v) return self end,
                SetDesc = function(self, v)
                    if d then d.Text = tostring(v) end
                    return self
                end
            }
            return el
        end

        -- ---------------- 文字輸入 ----------------
        host.AddInput = function(_, id, cfg)
            cfg = cfg or {}
            local row = makeRow(44)
            attachText(row, cfg)

            local box = Instance.new("TextBox")
            box.Name = RandName()
            box.Size = UDim2.new(0, 170, 0, 28)
            box.Position = UDim2.new(1, -176, 0, 8)
            box.BackgroundColor3 = Color3.fromRGB(13, 10, 20)
            box.BorderSizePixel = 0
            box.Text = tostring(cfg.Default or "")
            box.PlaceholderText = tostring(cfg.Placeholder or "")
            box.PlaceholderColor3 = Theme.Muted
            box.TextColor3 = Theme.Text
            box.TextSize = 11
            box.Font = Enum.Font.Gotham
            box.TextXAlignment = Enum.TextXAlignment.Left
            box.ClearTextOnFocus = false
            box.Parent = row
            NewCorner(box, 4)
            local stroke = NewStroke(box, Theme.Border, 1)

            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0, 8)
            pad.PaddingRight = UDim.new(0, 8)
            pad.Parent = box

            box.Focused:Connect(function()
                TweenService:Create(stroke, TweenFast, { Color = Theme.Accent }):Play()
            end)
            box.FocusLost:Connect(function()
                TweenService:Create(stroke, TweenFast, { Color = Theme.Border }):Play()
            end)

            local el = {
                Instance = row,
                Type = "Input",
                Flag = id,
                Title = cfg.Title,
                Description = cfg.Description,
                _row = row,
                _titleLabel = nil
            }
            for _, c in ipairs(row:GetChildren()) do
                if c:IsA("TextLabel") then el._titleLabel = c break end
            end

            ApplyCommonMethods(el, { defaultValue = box.Text, config = cfg })

            -- Numeric：只允許數字（Fluent 同名選項）
            -- 以旗標避免在 Text 變更事件內再次設定 Text 造成遞迴
            local numeric = cfg.Numeric and true or false
            local sanitizing = false
            if numeric then
                box:GetPropertyChangedSignal("Text"):Connect(function()
                    if sanitizing then return end
                    local cleaned = box.Text:gsub("%D", "")
                    if cleaned ~= box.Text then
                        sanitizing = true
                        box.Text = cleaned
                        sanitizing = false
                    end
                end)
            end

            el.SetValueInternal = function(self, v)
                self.Value = tostring(v or "")
                box.Text = self.Value
            end

            box:GetPropertyChangedSignal("Text"):Connect(function()
                el.Value = box.Text
            end)

            box.FocusLost:Connect(function(enterPressed)
                -- Finished：只有在按 Enter 時才觸發回呼
                if cfg.Finished and not enterPressed then
                    return
                end
                SafeCall(cfg.Callback, box.Text)
            end)

            RegisterElement(id, el)
            return el
        end

        -- ---------------- 按鍵綁定 ----------------
        host.AddKeybind = function(_, id, cfg)
            cfg = cfg or {}
            local row = makeRow(40)
            attachText(row, cfg)

            local keyName = tostring(cfg.Default or "G")
            local btn = Instance.new("TextButton")
            btn.Name = RandName()
            btn.Size = UDim2.new(0, 110, 0, 26)
            btn.Position = UDim2.new(1, -116, 0, 7)
            btn.BackgroundColor3 = Color3.fromRGB(13, 10, 20)
            btn.AutoButtonColor = false
            btn.Text = keyName
            btn.TextColor3 = Theme.Text
            btn.TextSize = 11
            btn.Font = Enum.Font.GothamBold
            btn.Parent = row
            NewCorner(btn, 4)
            local stroke = NewStroke(btn, Theme.Border, 1)

            local listening = false
            local held = false

            local el = {
                Instance = row,
                Type = "Keybind",
                Flag = id,
                Title = cfg.Title,
                Description = cfg.Description,
                Mode = cfg.Mode or "Toggle",
                Key = keyName,
                _row = row,
                _titleLabel = nil
            }
            for _, c in ipairs(row:GetChildren()) do
                if c:IsA("TextLabel") then el._titleLabel = c break end
            end

            ApplyCommonMethods(el, { defaultValue = keyName, config = cfg })
            el.SetValueInternal = function(self, v)
                keyName = tostring(v)
                self.Key = keyName
                self.Value = keyName
                btn.Text = (listening and "..." or keyName)
            end

            local function isActiveInput(input)
                return input.KeyCode == Enum.KeyCode[keyName] or input.UserInputType.Name == keyName
            end

            btn.MouseButton1Click:Connect(function()
                listening = true
                btn.Text = "..."
                btn.TextColor3 = Theme.AccentSoft
                TweenService:Create(stroke, TweenFast, { Color = Theme.Accent }):Play()
            end)

            btn.FocusLost:Connect(function()
                listening = false
                btn.Text = keyName
                btn.TextColor3 = Theme.Text
                TweenService:Create(stroke, TweenFast, { Color = Theme.Border }):Play()
            end)

            Track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if listening then
                    if input.UserInputType == Enum.UserInputType.Keyboard then
                        keyName = input.KeyCode.Name
                    elseif input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.MouseButton2 then
                        keyName = input.UserInputType.Name
                    end
                    listening = false
                    el.Key = keyName
                    el.Value = keyName
                    btn.Text = keyName
                    btn.TextColor3 = Theme.Text
                    TweenService:Create(stroke, TweenFast, { Color = Theme.Border }):Play()
                    SafeCall(cfg.ChangedCallback, Enum.KeyCode[keyName] or input.UserInputType)
                    return
                end
                if gameProcessed then return end
                if not isActiveInput(input) then return end

                if el.Mode == "Always" or el.Mode == "Hold" then
                    if not held then
                        held = true
                        SafeCall(cfg.Callback, true)
                    end
                else -- Toggle
                    el.ToggleState = not el.ToggleState
                    SafeCall(cfg.Callback, el.ToggleState)
                end
            end))

            Track(UserInputService.InputEnded:Connect(function(input)
                if el.Mode == "Hold" and isActiveInput(input) and held then
                    held = false
                    SafeCall(cfg.Callback, false)
                end
            end))

            el.ToggleState = false
            RegisterElement(id, el)
            return el
        end

        -- ---------------- 顏色選擇器 ----------------
        host.AddColorpicker = function(_, id, cfg)
            cfg = cfg or {}
            local row = makeRow(40)

            local baseColor = cfg.Default or Color3.fromRGB(255, 255, 255)
            local curH, curS, curV = Color3.toHSV(baseColor)

            local t = NewLabel(row, tostring(cfg.Title or id), 12, Theme.Text, Enum.Font.GothamMedium)
            t.Size = UDim2.new(0.6, 0, 0, 16)
            t.Position = UDim2.new(0, 2, 0, 6)
            t.TextTruncate = Enum.TextTruncate.AtEnd

            local swatch = Instance.new("TextButton")
            swatch.Name = RandName()
            swatch.Size = UDim2.new(0, 44, 0, 24)
            swatch.Position = UDim2.new(1, -50, 0, 8)
            swatch.BackgroundColor3 = baseColor
            swatch.AutoButtonColor = false
            swatch.Text = ""
            swatch.Parent = row
            NewCorner(swatch, 4)
            NewStroke(swatch, Theme.Border, 1)

            local el = {
                Instance = row,
                Type = "Colorpicker",
                Flag = id,
                Title = cfg.Title,
                Description = cfg.Description,
                Transparency = tonumber(cfg.Transparency) or 0,
                _row = row,
                _titleLabel = t
            }
            ApplyCommonMethods(el, { defaultValue = baseColor, config = cfg })

            el.SetValueInternal = function(self, c)
                if typeof(c) ~= "Color3" then return end
                baseColor = c
                swatch.BackgroundColor3 = c
                self.Value = c
            end

            -- 簡潔的顏色選擇面板：H / S / V 三段滑桿
            local panel = Instance.new("Frame")
            panel.Name = RandName()
            panel.Size = UDim2.new(0, 200, 0, 118)
            panel.BackgroundColor3 = Color3.fromRGB(13, 10, 20)
            panel.BorderSizePixel = 0
            panel.Visible = false
            panel.ZIndex = 500
            panel.Parent = main
            NewCorner(panel, 5)
            NewStroke(panel, Theme.Accent, 1)

            local panelPad = Instance.new("UIPadding")
            panelPad.PaddingTop = UDim.new(0, 8)
            panelPad.PaddingBottom = UDim.new(0, 8)
            panelPad.PaddingLeft = UDim.new(0, 8)
            panelPad.PaddingRight = UDim.new(0, 8)
            panelPad.Parent = panel

            local panelLayout = Instance.new("UIListLayout")
            panelLayout.Padding = UDim.new(0, 6)
            panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
            panelLayout.Parent = panel

            local preview = Instance.new("Frame")
            preview.Size = UDim2.new(1, 0, 0, 20)
            preview.BackgroundColor3 = baseColor
            preview.BorderSizePixel = 0
            preview.LayoutOrder = 1
            preview.ZIndex = 501
            preview.Parent = panel
            NewCorner(preview, 3)

            local function makeChannel(labelText, order, getter, setter)
                local holder = Instance.new("Frame")
                holder.Size = UDim2.new(1, 0, 0, 20)
                holder.BackgroundTransparency = 1
                holder.LayoutOrder = order
                holder.ZIndex = 501
                holder.Parent = panel

                local lab = NewLabel(holder, labelText, 10, Theme.Muted)
                lab.Size = UDim2.new(0, 16, 1, 0)
                lab.ZIndex = 502

                local bar = Instance.new("Frame")
                bar.Size = UDim2.new(1, -20, 0, 6)
                bar.Position = UDim2.new(0, 20, 0.5, -3)
                bar.BackgroundColor3 = Color3.fromRGB(38, 30, 53)
                bar.BorderSizePixel = 0
                bar.ZIndex = 502
                bar.Parent = holder
                NewCorner(bar, 3)

                local f = Instance.new("Frame")
                f.Size = UDim2.new(getter(), 0, 1, 0)
                f.BackgroundColor3 = Theme.Accent
                f.BorderSizePixel = 0
                f.ZIndex = 503
                f.Parent = bar
                NewCorner(f, 3)

                local hb = Instance.new("TextButton")
                hb.Size = UDim2.new(1, 12, 1, 12)
                hb.Position = UDim2.new(0, -6, 0.5, -6)
                hb.BackgroundTransparency = 1
                hb.Text = ""
                hb.ZIndex = 504
                hb.Parent = bar

                local function update(input)
                    local w = bar.AbsoluteSize.X
                    if w <= 1 then return end
                    local rel = math.clamp((input.Position.X - bar.AbsolutePosition.X) / w, 0, 1)
                    setter(rel)
                    f.Size = UDim2.new(rel, 0, 1, 0)
                    local c = Color3.fromHSV(curH, curS, curV)
                    baseColor = c
                    preview.BackgroundColor3 = c
                    swatch.BackgroundColor3 = c
                    el.Value = c
                    SafeCall(cfg.Callback, c)
                    el:FireChanged(c)
                end

                local down = false
                hb.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch then
                        down = true
                        update(input)
                    end
                end)
                Track(UserInputService.InputChanged:Connect(function(input)
                    if down and (input.UserInputType == Enum.UserInputType.MouseMovement
                        or input.UserInputType == Enum.UserInputType.Touch) then
                        update(input)
                    end
                end))
                Track(UserInputService.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch then
                        down = false
                    end
                end))
                return f
            end

            makeChannel("H", 2, function() return curH end, function(v) curH = v end)
            makeChannel("S", 3, function() return curS end, function(v) curS = v end)
            makeChannel("V", 4, function() return curV end, function(v) curV = v end)

            local function placePanel()
                local absSwatch = swatch.AbsolutePosition
                local absMain = main.AbsolutePosition
                local w = panel.AbsoluteSize.X
                local h = panel.AbsoluteSize.Y
                local x = absSwatch.X - absMain.X + swatch.AbsoluteSize.X - w
                local y = absSwatch.Y - absMain.Y + swatch.AbsoluteSize.Y + 4
                if x < 4 then x = 4 end
                if x + w > main.AbsoluteSize.X - 4 then x = main.AbsoluteSize.X - 4 - w end
                if y + h > main.AbsoluteSize.Y - 4 then
                    y = math.max(4, (absSwatch.Y - absMain.Y) - h - 4)
                end
                panel.Position = UDim2.new(0, Round(x), 0, Round(y))
            end

            local function setOpen(open)
                panel.Visible = open
                if open then
                    placePanel()
                    OpenDropdowns[panel] = function() setOpen(false) end
                else
                    OpenDropdowns[panel] = nil
                end
            end

            swatch.MouseButton1Click:Connect(function()
                setOpen(not panel.Visible)
            end)

            container:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
                if panel.Visible then placePanel() end
            end)
            if container:IsA("ScrollingFrame") then
                container:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                    if panel.Visible then placePanel() end
                end)
            end

            RegisterElement(id, el)
            return el
        end

        hostCache[container] = host
        return host
    end

    -- 展開根宿主的方法到 window 物件
    local rootHost = BuildElementHost(bodyFrame, nil)

    -- Window:Dialog
    local function Dialog(cfg)
        cfg = cfg or {}
        local overlay = Instance.new("TextButton")
        overlay.Name = RandName()
        overlay.Size = UDim2.new(1, 0, 1, 0)
        overlay.BackgroundColor3 = Theme.Overlay
        overlay.BackgroundTransparency = 0.45
        overlay.AutoButtonColor = false
        overlay.Text = ""
        overlay.ZIndex = 800
        overlay.Parent = screenGui

        local panel = Instance.new("Frame")
        panel.Size = UDim2.new(0, 320, 0, 150)
        panel.Position = UDim2.new(0.5, -160, 0.5, -75)
        panel.BackgroundColor3 = Theme.Bg
        panel.BorderSizePixel = 0
        panel.ZIndex = 801
        panel.Parent = overlay
        NewCorner(panel, 8)
        NewStroke(panel, Theme.Accent, 1)

        local t = NewLabel(panel, tostring(cfg.Title or "Confirm"), 13, Theme.Text, Enum.Font.GothamBold)
        t.Size = UDim2.new(1, -24, 0, 20)
        t.Position = UDim2.new(0, 12, 0, 12)
        t.ZIndex = 802

        local c = NewLabel(panel, tostring(cfg.Content or ""), 11, Theme.TextSub)
        c.Size = UDim2.new(1, -24, 0, 40)
        c.Position = UDim2.new(0, 12, 0, 36)
        c.TextWrapped = true
        c.TextYAlignment = Enum.TextYAlignment.Top
        c.ZIndex = 802

        local function close()
            overlay:Destroy()
        end

        local buttons = cfg.Buttons or {}
        local count = math.max(#buttons, 1)
        local bw = (320 - 24 - (count - 1) * 8) / count

        for i, bcfg in ipairs(buttons) do
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(0, bw, 0, 30)
            b.Position = UDim2.new(0, 12 + (i - 1) * (bw + 8), 1, -42)
            b.BackgroundColor3 = Theme.Element
            b.AutoButtonColor = false
            b.Text = tostring(bcfg.Title or "OK")
            b.TextColor3 = Theme.Text
            b.TextSize = 11
            b.Font = Enum.Font.GothamBold
            b.ZIndex = 802
            b.Parent = panel
            NewCorner(b, 5)
            NewStroke(b, Theme.Border, 1)
            b.MouseEnter:Connect(function()
                TweenService:Create(b, TweenFast, { BackgroundColor3 = Theme.ElementHov }):Play()
            end)
            b.MouseLeave:Connect(function()
                TweenService:Create(b, TweenFast, { BackgroundColor3 = Theme.Element }):Play()
            end)
            b.MouseButton1Click:Connect(function()
                close()
                SafeCall(bcfg.Callback)
            end)
        end

        return overlay
    end

    -- 關閉：只隱藏，不銷毀（避免外部還持有控件參考）
    closeBtn.MouseButton1Click:Connect(function()
        main.Visible = false
    end)

    -- 快捷鍵：顯示/隱藏、最小化
    local toggleKey = config.ToggleKey and Enum.KeyCode[config.ToggleKey] or nil
    local minimizeKey = config.MinimizeKey and Enum.KeyCode[config.MinimizeKey] or nil

    if toggleKey or minimizeKey then
        Track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if toggleKey and input.KeyCode == toggleKey then
                main.Visible = not main.Visible
            end
            if minimizeKey and input.KeyCode == minimizeKey then
                setMinimized(not minimized)
            end
        end))
    end

    -- 點空白處關閉浮動面板
    Track(UserInputService.InputBegan:Connect(function(_, gameProcessed)
        if gameProcessed then return end
        -- OpenDropdowns[panelInstance] = closeFn —— key 是面板、value 是關閉函式
        for panelInstance, closeFn in pairs(OpenDropdowns) do
            if type(closeFn) == "function" then
                pcall(closeFn, false)
            end
            OpenDropdowns[panelInstance] = nil
        end
    end))

    local window = {
        Instance = main,
        Tabs = tabs,
        Dialog = Dialog,
        SelectTab = function(_, n)
            local key = tabIndexOrder[tonumber(n) or 1]
            if key then SwitchTabByKey(key) end
            return window
        end,
        AddTab = AddTab,
        SetTitle = function(_, v)
            titleLabel.Text = tostring(v)
        end,
        SetSubTitle = function(_, v)
            subTitleLabel.Text = tostring(v)
        end,
        Minimize = function() setMinimized(true) end,
        Restore = function() setMinimized(false) end
    }

    for k, v in pairs(rootHost) do
        if window[k] == nil then window[k] = v end
    end

    -- 預設選中第一個分頁
    if #tabIndexOrder > 0 then
        SwitchTabByKey(tabIndexOrder[1])
    end

    -- 進場動畫
    main.BackgroundTransparency = 1
    mainStroke.Transparency = 1
    TweenService:Create(main, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0
    }):Play()
    TweenService:Create(mainStroke, TweenInfo.new(0.26), { Transparency = 0 }):Play()

    return window
end

-- 浮動面板註冊表（下拉選單 / 顏色面板共用）已於檔案開頭宣告

-- ==============================================================================
-- SaveManager / InterfaceManager 相容層
-- ==============================================================================
local function SerializeValue(v)
    local t = typeof(v)
    if t == "Color3" then
        return { __color = true, r = v.R, g = v.G, b = v.B }
    elseif t == "table" then
        local out = {}
        for k, val in pairs(v) do
            out[k] = SerializeValue(val)
        end
        return out
    end
    return v
end

local function DeserializeValue(v)
    if type(v) == "table" then
        if v.__color then
            return Color3.new(v.r, v.g, v.b)
        end
        local out = {}
        for k, val in pairs(v) do
            out[k] = DeserializeValue(val)
        end
        return out
    end
    return v
end

local SaveManager = {}
local InterfaceManager = {}
local saveFolder = "Nekohub/Islands"
local autoloadName = nil

local function configPath(name)
    return saveFolder .. "/configs/" .. tostring(name) .. ".json"
end

local function ensureFolder(path)
    -- 手寫逐層建立，避免依賴 Roblox 專有的 string.split
    local cur = ""
    for part in string.gmatch(tostring(path), "[^/]+") do
        cur = (cur == "") and part or (cur .. "/" .. part)
        if not isfolder(cur) then
            pcall(makefolder, cur)
        end
    end
end

local function collectFlags()
    local out = {}
    for _, el in ipairs(registeredElements) do
        if el.Flag and el.Type ~= "Button" then
            out[el.Flag] = SerializeValue(el.Value)
        end
    end
    return out
end

local function applyFlags(data)
    if type(data) ~= "table" then return end
    for _, el in ipairs(registeredElements) do
        if el.Flag and data[el.Flag] ~= nil then
            local v = DeserializeValue(data[el.Flag])
            -- SetValue 會觸發 OnChanged，讓 _G 旗標同步更新
            if el.SetValue then
                pcall(function() el:SetValue(v) end)
            end
        end
    end
end

function SaveManager:SetLibrary() end
function SaveManager:SetFolder(f) saveFolder = tostring(f) end
function SaveManager:IgnoreThemeSettings() end
function SaveManager:SetIgnoreIndexes() end
function SaveManager:LoadAutoloadConfig()
    if autoloadName then
        SaveManager:LoadConfiguration(autoloadName)
    end
end
function SaveManager:LoadConfiguration(name)
    local path = configPath(name)
    local ok, data = pcall(function()
        if not isfile(path) then return nil end
        return game:GetService("HttpService"):JSONDecode(readfile(path))
    end)
    if ok and data then
        applyFlags(data)
        Notify({ Title = "Config", Content = "Loaded: " .. tostring(name), Duration = 4 })
        return true
    end
    return false
end
function SaveManager:SaveConfiguration(name)
    ensureFolder(saveFolder .. "/configs")
    local ok = pcall(function()
        writefile(configPath(name),
            game:GetService("HttpService"):JSONEncode(collectFlags()))
    end)
    Notify({
        Title = "Config",
        Content = ok and ("Saved: " .. tostring(name)) or "Save failed",
        Duration = 4
    })
    return ok
end

local function BuildConfigSection(section)
    if not section then return end
    local configName = "default"

    section:AddInput("ConfigName", {
        Title = "Config Name",
        Description = "Name used when saving / loading",
        Placeholder = "default",
        Default = "default",
        Callback = function(v)
            configName = (v ~= "" and v) or "default"
        end
    })

    section:AddButton({
        Title = "Save Config",
        Description = "Write current settings to disk",
        Callback = function() SaveManager:SaveConfiguration(configName) end
    })
    section:AddButton({
        Title = "Load Config",
        Description = "Restore settings from disk",
        Callback = function() SaveManager:LoadConfiguration(configName) end
    })
    section:AddInput("AutoloadName", {
        Title = "Autoload Config",
        Description = "Config loaded automatically on start",
        Placeholder = "default",
        Default = "",
        Callback = function(v)
            autoloadName = (v ~= "" and v) or nil
        end
    })
end

function InterfaceManager:SetLibrary() end
function InterfaceManager:SetFolder() end
function InterfaceManager:BuildInterfaceSection(section)
    if not section then return end
    section:AddParagraph({
        Title = "Interface",
        Content = "Identical UI engine. Drag the title bar to move, double-click it to minimize."
    })
    section:AddButton({
        Title = "Unload Interface",
        Description = "Remove the interface from screen",
        Callback = function()
            screenGui:Destroy()
        end
    })
end

-- ==============================================================================
-- 對外
-- ==============================================================================
local Library = {
    Options = Options,
    Flags = Flags,
    ScreenGui = screenGui,
    SaveManager = SaveManager,
    InterfaceManager = InterfaceManager,
    Themes = { Dark = Theme },
    Notify = Notify
}

function Library:CreateWindow(config)
    screenGui.Enabled = true
    local window = CreateWindow(self, config)
    Library.Window = window
    Library.Dialog = function(_, cfg) return window.Dialog(cfg) end
    return window
end

function Library:SetTheme() end
function Library:ToggleTransparency() end

-- ==============================================================================
-- Demo 自我測試層
-- ==============================================================================
-- 用途：單獨執行本檔時，畫出一個完整介面，把所有控件跑一遍，
--       讓你不需要 IslandsScript.lua 就能當場驗證引擎是否正常。
--
-- 為什麼要用 __index 延遲建構：
--       正常使用時本檔是被 loadstring(...)() 載入的，那條路徑「只取 Library」，
--       不應該順手多開一個測試視窗。所以 demo 只有在你真的存取
--       Library.Demo 時才會建立。
local demoWindow = nil

local function BuildDemoWindow()
    if demoWindow then return demoWindow end

    local w = Library:CreateWindow({
        Title = "Identical UI — 自我測試",
        SubTitle = "FluentCompat v1.0",
        TabWidth = 180,
        MinimizeKey = "LeftControl"
    })
    demoWindow = w

    -- ---------------- 總覽 ----------------
    local home = w:AddTab({ Title = "總覽", Icon = "◈" })
    home:AddParagraph({
        Title = "引擎自我測試",
        Content = "若你看到這個視窗與底下的控件，代表引擎載入、版面與互動都正常。"
    })
    local clickCount = 0
    home:AddButton({
        Title = "測試按鈕",
        Description = "點我應該會跳通知並更新下方數字",
        Callback = function()
            clickCount = clickCount + 1
            Notify({
                Title = "按鈕正常",
                Content = "這是第 " .. tostring(clickCount) .. " 次點擊",
                Duration = 3
            })
        end
    })
    home:AddButton({
        Title = "測試對話框",
        Description = "應該會彈出確認視窗",
        Callback = function()
            w:Dialog({
                Title = "確認視窗測試",
                Content = "看到這個就代表 Dialog 正常。",
                Buttons = {
                    {
                        Title = "確定",
                        Callback = function() Notify({ Title = "已確認", Duration = 3 }) end
                    },
                    { Title = "取消", Callback = function() end }
                }
            })
        end
    })

    -- ---------------- 控件 ----------------
    local controls = w:AddTab({ Title = "控件", Icon = "✦" })
    local toggleSec = controls:AddSection("開關與滑桿")

    toggleSec:AddToggle("DemoToggle", {
        Title = "測試開關",
        Description = "預設為開啟",
        Default = true,
        Callback = function(v)
            print("[Demo] Toggle =", v)
        end
    })

    local sliderValue = 50
    toggleSec:AddSlider("DemoSlider", {
        Title = "測試滑桿",
        Description = "應該可以拖曳，數字會跟著跑",
        Default = 50,
        Min = 0,
        Max = 100,
        Rounding = 0,
        Callback = function(v)
            sliderValue = v
        end
    })

    controls:AddSection("輸入與選擇"):AddDropdown("DemoDropdown", {
        Title = "測試下拉（單選）",
        Description = "選一個選項",
        Values = { "Alpha", "Beta", "Gamma", "Delta" },
        Default = "Alpha",
        Callback = function(v)
            print("[Demo] Dropdown =", v)
        end
    })

    controls:AddSection("多選與文字"):AddDropdown("DemoMulti", {
        Title = "測試下拉（多選）",
        Description = "可同時勾選多項，選單會保持開啟",
        Values = { "小麥", "紅蘿蔔", "南瓜", "番茄", "洋蔥" },
        Multi = true,
        Default = { "小麥" },
        Callback = function(t)
            print("[Demo] Multi =", type(t) == "table" and table.concat(t, ", ") or tostring(t))
        end
    })

    local inputSec = controls:AddSection("文字與按鍵")
    inputSec:AddInput("DemoInput", {
        Title = "測試輸入框",
        Description = "按 Enter 後才會觸發回呼",
        Placeholder = "在這裡打字...",
        Default = "",
        Finished = true,
        Callback = function(v)
            Notify({ Title = "輸入內容", Content = tostring(v), Duration = 3 })
        end
    })
    inputSec:AddInput("DemoNumeric", {
        Title = "測試數字框",
        Description = "只接受數字",
        Placeholder = "0",
        Default = "0",
        Numeric = true,
        Finished = true,
        Callback = function(v)
            print("[Demo] Numeric =", v)
        end
    })
    inputSec:AddKeybind("DemoKeybind", {
        Title = "測試按鍵綁定",
        Description = "點一下再按任意鍵即可改綁",
        Mode = "Toggle",
        Default = "G",
        Callback = function(state)
            print("[Demo] Keybind =", state)
        end,
        ChangedCallback = function(newKey)
            print("[Demo] Keybind changed ->", tostring(newKey))
        end
    })

    controls:AddSection("顏色"):AddColorpicker("DemoColor", {
        Title = "測試顏色選擇",
        Description = "點右邊色塊開啟 H/S/V 調整",
        Default = Color3.fromRGB(168, 85, 247),
        Transparency = 0
    })

    -- ---------------- 設定與介面 ----------------
    local settings = w:AddTab({ Title = "設定", Icon = "≡" })
    BuildConfigSection(settings:AddSection("設定存檔"))
    InterfaceManager:BuildInterfaceSection(settings:AddSection("介面"))

    w:SelectTab(1)
    Notify({ Title = "自我測試已啟動", Content = "引擎載入正常", Duration = 4 })

    print("[FluentCompat] Demo 視窗已建立。切換分頁與操作控件即可驗證引擎。")
    return w
end

setmetatable(Library, {
    __index = function(_, key)
        if key == "Demo" then
            return BuildDemoWindow()
        end
        return nil
    end
})

-- ==============================================================================
-- 自我測試入口
-- ==============================================================================
-- 註冊到全域有兩個作用：
--   1. 之後的載入（IslandsScript）可直接取用，完全不需要檔案讀寫；
--   2. 讓你能驗證引擎是否就緒：getgenv().FluentCompat
--
-- 本檔不會自動開視窗 —— 因為它也會被 IslandsScript 用 loadstring 載入，
-- 那條路徑不該順手多開一個測試視窗。想看介面請執行：
--
--     getgenv().FluentCompat.Demo
--
-- 或在執行器直接跑 install-compat.lua，它會自動開起來。
pcall(function()
    if getgenv then
        local g = getgenv()
        g.FluentCompat = Library
        g.IdenticalUI = Library
        g.IdenticalUIDemo = BuildDemoWindow
    end
end)

return Library

]=]

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
