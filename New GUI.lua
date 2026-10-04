--[[
================================================================================
  IDENTICAL UI LIBRARY  v1.1
================================================================================
  紫色主題的暗色系 GUI 框架。

  v1.1 更新重點
    [修正] 最小化還原時視窗尺寸被寫死，改為記住實際尺寸後還原
    [修正] 拖曳視窗時下拉選單會脫離原位，現在即時跟隨
    [修正] 重新拖曳時每次都在舊的 InputChanged 上疊加新連線（連線洩漏）
    [修正] 搜尋只掃描分頁直屬子項，現在遞迴掃描所有列
    [修正] 下拉選單開啟後點擊空白處無法關閉，且切換分頁後仍浮在畫面上
    [修正] 下拉選單 MouseLeave 會蓋掉已選項目的高亮
    [修正] table.clear 在部分環境不存在，導致卸載失敗
    [修正] 提示氣泡改用絕對座標，不再因視窗拖曳而錯位，並自動避免超出畫面
    [修正] 取消按鈕未做防抖，連點會產生重複 tween 與殘留連線
    [新增] 視窗投影、進場動畫、統一 hover 動效
    [新增] 輕量通知（Toast）系統
    [新增] 最小化改用「雙擊標題列」與視窗按鈕皆可
    [新增] 各控件補上 SetValue / GetValue / SetOption / GetOption / SetState / GetState
================================================================================
]]

-- ==============================================================================
-- 服務與環境
-- ==============================================================================
local cloneref = cloneref or function(o) return o end

local Players          = cloneref(game:GetService("Players"))
local RunService       = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TweenService     = cloneref(game:GetService("TweenService"))
local TextService      = cloneref(game:GetService("TextService"))
local CoreGui          = cloneref(game:GetService("CoreGui"))

local LocalPlayer = Players.LocalPlayer

local TweenInfoFast = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TweenInfoMed  = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ==============================================================================
-- 配色主題
-- ==============================================================================
local Colors = {
    Background     = Color3.fromRGB(15, 12, 22),
    SidebarBg      = Color3.fromRGB(11, 9, 17),
    BorderPurple   = Color3.fromRGB(168, 85, 247),
    BorderSubtle   = Color3.fromRGB(45, 33, 66),
    Divider        = Color3.fromRGB(36, 26, 54),
    PurplePrimary  = Color3.fromRGB(216, 160, 255),
    PurpleAccent   = Color3.fromRGB(168, 85, 247),
    PurpleMuted    = Color3.fromRGB(147, 112, 196),
    PurpleDark     = Color3.fromRGB(72, 45, 107),
    PurpleGlow     = Color3.fromRGB(192, 132, 252),
    TextMain       = Color3.fromRGB(243, 235, 255),
    TextSecondary  = Color3.fromRGB(186, 172, 212),
    TextMuted      = Color3.fromRGB(130, 115, 160),
    TextDark       = Color3.fromRGB(80, 68, 100),
    ToggleTrackOff = Color3.fromRGB(30, 24, 42),
    ToggleKnobOff  = Color3.fromRGB(90, 75, 115),
    ToggleTrackOn  = Color3.fromRGB(168, 85, 247),
    ToggleKnobOn   = Color3.fromRGB(255, 255, 255),
    SliderTrack    = Color3.fromRGB(28, 22, 40),
    SliderFill     = Color3.fromRGB(168, 85, 247),
    SliderKnob     = Color3.fromRGB(243, 230, 255),
    DropdownBg     = Color3.fromRGB(13, 10, 20),
    DropdownBorder = Color3.fromRGB(54, 38, 82),
    StatusActive   = Color3.fromRGB(52, 211, 153),
    StatusWarn     = Color3.fromRGB(251, 191, 36),
    StatusOff      = Color3.fromRGB(120, 105, 145),
    RowBg          = Color3.fromRGB(20, 16, 28),
    RowBgHover     = Color3.fromRGB(26, 20, 37),
    CardBg         = Color3.fromRGB(20, 16, 28),
    CardBgHover    = Color3.fromRGB(26, 20, 36),
    Danger         = Color3.fromRGB(255, 125, 125),
    DangerStroke   = Color3.fromRGB(110, 45, 45),
    CalmText       = Color3.fromRGB(220, 185, 255),
    CalmStroke     = Color3.fromRGB(90, 56, 140),
    ButtonBg       = Color3.fromRGB(24, 18, 38)
}

-- ==============================================================================
-- 工具函數
-- ==============================================================================
local ZWS = utf8.char(0x200B)

-- 零寬字符包裝（沿用原本的防字串混淆用途）
local function S(str)
    if type(str) ~= "string" or str == "" then return str end
    local chars = {}
    local ok = pcall(function()
        for _, code in utf8.codes(str) do
            table.insert(chars, utf8.char(code))
        end
    end)
    if not ok or #chars == 0 then
        for i = 1, #str do
            table.insert(chars, str:sub(i, i))
        end
    end
    return table.concat(chars, ZWS)
end

local function RandName()
    return "UI_" .. tostring(math.random(100000, 999999))
end

-- 只有字串才包零寬字符，其他型別原樣回傳
local function Txt(v)
    if v == nil then return "" end
    if type(v) == "string" then return S(v) end
    return tostring(v)
end

local function Round(n)
    if n >= 0 then return math.floor(n + 0.5) end
    return -math.floor(-n + 0.5)
end

-- 依名稱做防抖，避免高頻事件堆疊 tween
local debounceClock = {}
local function Debounce(key, interval)
    local now = os.clock()
    if debounceClock[key] and (now - debounceClock[key]) < interval then
        return false
    end
    debounceClock[key] = now
    return true
end

local function SafeTween(obj, info, goal)
    if not obj or not obj.Parent then return end
    local ok, tween = pcall(TweenService.Create, TweenService, obj, info, goal)
    if ok and tween then
        tween:Play()
    end
end

-- 安全掛載節點：取得失敗時退回 PlayerGui
local function GetSafeParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    if syn and syn.protect_gui then
        local ok, res = pcall(function() return CoreGui end)
        if ok and res then return res end
    end
    local ok, res = pcall(function() return CoreGui end)
    if ok and res then return res end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- ==============================================================================
-- ScreenGui 初始化
-- ==============================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = RandName()
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
screenGui.Parent = GetSafeParent()

-- 集中管理連線，卸載時一次斷開
local uiConnections = {}
local function Track(conn)
    table.insert(uiConnections, conn)
    return conn
end

-- 集中管理 Tween：播放新動畫前先取消同一物件上的舊動畫
local activeTweens = {}
local function TweenTo(obj, info, goal, tag)
    if not obj then return end
    local key = tag or obj
    local prev = activeTweens[key]
    if prev then
        pcall(function() prev:Cancel() end)
    end
    local ok, tween = pcall(TweenService.Create, TweenService, obj, info, goal)
    if not ok or not tween then return end
    activeTweens[key] = tween
    tween:Play()
end

-- ==============================================================================
-- 視窗主體
-- ==============================================================================
local WINDOW_W, WINDOW_H = 680, 460
local TOPBAR_H = 38
local SIDEBAR_W = 164
local FOOTER_H = 25

local mainFrame = Instance.new("Frame")
mainFrame.Name = RandName()
mainFrame.Size = UDim2.new(0, WINDOW_W, 0, WINDOW_H)
mainFrame.Position = UDim2.new(0.5, -Round(WINDOW_W / 2), 0.5, -Round(WINDOW_H / 2))
mainFrame.BackgroundColor3 = Colors.Background
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.ClipsDescendants = false
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 10)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Colors.BorderPurple
mainStroke.Thickness = 1.2
mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
mainStroke.Parent = mainFrame

-- 邊框漸層：頂部亮、底部收暗（UIGradient 不支援時安全略過）
pcall(function()
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(196, 138, 255)),
        ColorSequenceKeypoint.new(0.45, Color3.fromRGB(138, 74, 214)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(58, 36, 92))
    })
    grad.Parent = mainStroke
end)

-- 視窗投影（兩層：擴散層 + 收斂層）
local shadowFar = Instance.new("Frame")
shadowFar.Name = RandName()
shadowFar.Size = UDim2.new(1, 22, 1, 26)
shadowFar.Position = UDim2.new(0, -11, 0, -5)
shadowFar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadowFar.BackgroundTransparency = 0.62
shadowFar.BorderSizePixel = 0
shadowFar.ZIndex = -2
shadowFar.Parent = mainFrame

local shadowFarCorner = Instance.new("UICorner")
shadowFarCorner.CornerRadius = UDim.new(0, 20)
shadowFarCorner.Parent = shadowFar

local shadowNear = Instance.new("Frame")
shadowNear.Name = RandName()
shadowNear.Size = UDim2.new(1, 10, 1, 12)
shadowNear.Position = UDim2.new(0, -5, 0, -3)
shadowNear.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadowNear.BackgroundTransparency = 0.48
shadowNear.BorderSizePixel = 0
shadowNear.ZIndex = -1
shadowNear.Parent = mainFrame

local shadowNearCorner = Instance.new("UICorner")
shadowNearCorner.CornerRadius = UDim.new(0, 14)
shadowNearCorner.Parent = shadowNear

-- 內容裁切層：把側邊欄與內容區收在圓角內，投影不受影響
local clipFrame = Instance.new("Frame")
clipFrame.Name = RandName()
clipFrame.Size = UDim2.new(1, 0, 1, 0)
clipFrame.BackgroundTransparency = 1
clipFrame.ClipsDescendants = true
clipFrame.Active = false
clipFrame.Parent = mainFrame

local clipPadding = Instance.new("UIPadding")
clipPadding.PaddingTop = UDim.new(0, 4)
clipPadding.PaddingBottom = UDim.new(0, 4)
clipPadding.PaddingLeft = UDim.new(0, 4)
clipPadding.PaddingRight = UDim.new(0, 4)
clipPadding.Parent = clipFrame

-- ------------------------------------------------------------------
-- 標題列
-- ------------------------------------------------------------------
local topBar = Instance.new("Frame")
topBar.Name = RandName()
topBar.Size = UDim2.new(1, 0, 0, TOPBAR_H)
topBar.BackgroundTransparency = 1
topBar.Parent = mainFrame

local crest = Instance.new("Frame")
crest.Size = UDim2.new(0, 22, 0, 22)
crest.Position = UDim2.new(0, 14, 0.5, -11)
crest.BackgroundColor3 = Colors.CardBg
crest.BorderSizePixel = 0
crest.Parent = topBar

local crestCorner = Instance.new("UICorner")
crestCorner.CornerRadius = UDim.new(1, 0)
crestCorner.Parent = crest

local crestStroke = Instance.new("UIStroke")
crestStroke.Color = Colors.PurpleAccent
crestStroke.Thickness = 1
crestStroke.Parent = crest

local crestLabel = Instance.new("TextLabel")
crestLabel.Size = UDim2.new(1, 0, 1, 0)
crestLabel.BackgroundTransparency = 1
crestLabel.Text = S("I")
crestLabel.TextColor3 = Colors.PurplePrimary
crestLabel.TextSize = 11
crestLabel.Font = Enum.Font.GothamBold
crestLabel.Parent = crest

local brandLabel = Instance.new("TextLabel")
brandLabel.Size = UDim2.new(0, 92, 1, 0)
brandLabel.Position = UDim2.new(0, 44, 0, 0)
brandLabel.BackgroundTransparency = 1
brandLabel.Text = S("IDENTICAL")
brandLabel.TextColor3 = Color3.fromRGB(230, 205, 255)
brandLabel.TextSize = 13
brandLabel.Font = Enum.Font.GothamBold
brandLabel.TextXAlignment = Enum.TextXAlignment.Left
brandLabel.Parent = topBar

-- 原本用文字「|」當分隔線，改為 1px 直線，避免字型基線偏移
local topPipe = Instance.new("Frame")
topPipe.Size = UDim2.new(0, 1, 0, 14)
topPipe.Position = UDim2.new(0, 142, 0.5, -7)
topPipe.BackgroundColor3 = Color3.fromRGB(85, 68, 110)
topPipe.BorderSizePixel = 0
topPipe.Parent = topBar

local gameLabel = Instance.new("TextLabel")
gameLabel.Size = UDim2.new(0, 180, 1, 0)
gameLabel.Position = UDim2.new(0, 154, 0, 0)
gameLabel.BackgroundTransparency = 1
gameLabel.Text = S("Dashboard")
gameLabel.TextColor3 = Colors.TextSecondary
gameLabel.TextSize = 12
gameLabel.Font = Enum.Font.Gotham
gameLabel.TextXAlignment = Enum.TextXAlignment.Left
gameLabel.Parent = topBar

-- 標題列按鈕共用建立器（補上 hover 底與防抖）
local function CreateBarButton(text, order, hoverColor)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 28, 0, 28)
    btn.Position = UDim2.new(1, -(34 + (order - 1) * 30), 0.5, -14)
    btn.BackgroundColor3 = hoverColor
    btn.BackgroundTransparency = 1
    btn.AutoButtonColor = false
    btn.Text = text
    btn.TextColor3 = Colors.TextSecondary
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamMedium
    btn.Parent = topBar

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = btn

    btn.MouseEnter:Connect(function()
        TweenTo(btn, TweenInfoFast, { BackgroundTransparency = 0, TextColor3 = Colors.TextMain }, btn)
    end)
    btn.MouseLeave:Connect(function()
        TweenTo(btn, TweenInfoFast, { BackgroundTransparency = 1, TextColor3 = Colors.TextSecondary }, btn)
    end)
    return btn
end

local closeBtn = CreateBarButton("✕", 1, Color3.fromRGB(70, 26, 36))
local minBtn   = CreateBarButton("—", 2, Color3.fromRGB(38, 28, 56))

-- ------------------------------------------------------------------
-- 拖曳（修正連線洩漏 + 像素對齊）
-- ------------------------------------------------------------------
local function MakeDraggable(guiObject, dragHandle)
    dragHandle = dragHandle or guiObject
    local dragging = false
    local dragStart, handleStartPos
    local dragInput

    local function finishDrag()
        dragging = false
        dragInput = nil
        -- 對齊整數像素，避免停在半像素造成文字模糊
        local p = guiObject.Position
        guiObject.Position = UDim2.new(p.X.Scale, Round(p.X.Offset), p.Y.Scale, Round(p.Y.Offset))
    end

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            handleStartPos = guiObject.Position
            -- 只保留「這一個」拖曳輸入的連線，pointer 放開或換手時自動釋放
            dragInput = input
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    finishDrag()
                end
            end)
        end
    end)

    guiObject.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    Track(UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and dragStart then
            local delta = input.Position - dragStart
            guiObject.Position = UDim2.new(
                handleStartPos.X.Scale,
                handleStartPos.X.Offset + delta.X,
                handleStartPos.Y.Scale,
                handleStartPos.Y.Offset + delta.Y
            )
        end
    end))

    return function() return dragging end
end

local topDivider = Instance.new("Frame")
topDivider.Size = UDim2.new(1, 0, 0, 1)
topDivider.Position = UDim2.new(0, 0, 0, TOPBAR_H)
topDivider.BackgroundColor3 = Colors.Divider
topDivider.BorderSizePixel = 0
topDivider.Parent = mainFrame

-- ------------------------------------------------------------------
-- 主內容區
-- ------------------------------------------------------------------
local bodyFrame = Instance.new("Frame")
bodyFrame.Size = UDim2.new(1, 0, 1, -(TOPBAR_H + 1 + FOOTER_H))
bodyFrame.Position = UDim2.new(0, 0, 0, TOPBAR_H + 1)
bodyFrame.BackgroundTransparency = 1
bodyFrame.Parent = clipFrame

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, 0)
sidebar.BackgroundColor3 = Colors.SidebarBg
sidebar.BorderSizePixel = 0
sidebar.Parent = bodyFrame

local verticalDivider = Instance.new("Frame")
verticalDivider.Size = UDim2.new(0, 1, 1, 0)
verticalDivider.Position = UDim2.new(0, SIDEBAR_W, 0, 0)
verticalDivider.BackgroundColor3 = Colors.Divider
verticalDivider.BorderSizePixel = 0
verticalDivider.Parent = bodyFrame

-- 搜尋框
local searchFrame = Instance.new("Frame")
searchFrame.Size = UDim2.new(1, -22, 0, 26)
searchFrame.Position = UDim2.new(0, 11, 0, 12)
searchFrame.BackgroundColor3 = Color3.fromRGB(18, 14, 28)
searchFrame.BorderSizePixel = 0
searchFrame.Parent = sidebar

local searchCorner = Instance.new("UICorner")
searchCorner.CornerRadius = UDim.new(0, 4)
searchCorner.Parent = searchFrame

local searchStroke = Instance.new("UIStroke")
searchStroke.Color = Colors.BorderSubtle
searchStroke.Thickness = 1
searchStroke.Parent = searchFrame

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -16, 1, 0)
searchBox.Position = UDim2.new(0, 8, 0, 0)
searchBox.BackgroundTransparency = 1
searchBox.PlaceholderText = S("Search...")
searchBox.PlaceholderColor3 = Colors.TextMuted
searchBox.Text = ""
searchBox.TextColor3 = Colors.TextMain
searchBox.TextSize = 11
searchBox.Font = Enum.Font.Gotham
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.Parent = searchFrame

-- 聚焦時邊框亮起
searchBox.Focused:Connect(function()
    TweenTo(searchStroke, TweenInfoFast, { Color = Colors.PurpleAccent }, searchStroke)
end)
searchBox.FocusLost:Connect(function()
    TweenTo(searchStroke, TweenInfoFast, { Color = Colors.BorderSubtle }, searchStroke)
end)

-- 導航清單
local navList = Instance.new("Frame")
navList.Size = UDim2.new(1, 0, 1, -56)
navList.Position = UDim2.new(0, 0, 0, 48)
navList.BackgroundTransparency = 1
navList.Parent = sidebar

local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, 2)
navLayout.SortOrder = Enum.SortOrder.LayoutOrder
navLayout.Parent = navList

-- 底部狀態列
local footerBar = Instance.new("Frame")
footerBar.Size = UDim2.new(1, 0, 0, FOOTER_H)
footerBar.Position = UDim2.new(0, 0, 1, -FOOTER_H)
footerBar.BackgroundColor3 = Colors.Background
footerBar.BorderSizePixel = 0
footerBar.Parent = clipFrame

local footerDivider = Instance.new("Frame")
footerDivider.Size = UDim2.new(1, 0, 0, 1)
footerDivider.BackgroundColor3 = Colors.Divider
footerDivider.BorderSizePixel = 0
footerDivider.Parent = footerBar

local footerLeft = Instance.new("TextLabel")
footerLeft.Size = UDim2.new(0, 220, 1, 0)
footerLeft.Position = UDim2.new(0, 14, 0, 0)
footerLeft.BackgroundTransparency = 1
footerLeft.Text = S("Ready")
footerLeft.TextColor3 = Colors.TextDark
footerLeft.TextSize = 10
footerLeft.Font = Enum.Font.GothamMedium
footerLeft.TextXAlignment = Enum.TextXAlignment.Left
footerLeft.Parent = footerBar

local footerCenter = Instance.new("TextLabel")
footerCenter.Size = UDim2.new(0, 220, 1, 0)
footerCenter.Position = UDim2.new(0.5, -110, 0, 0)
footerCenter.BackgroundTransparency = 1
footerCenter.Text = S("Identical UI Library v1.1")
footerCenter.TextColor3 = Colors.TextDark
footerCenter.TextSize = 10
footerCenter.Font = Enum.Font.Gotham
footerCenter.Parent = footerBar

local footerRight = Instance.new("TextLabel")
footerRight.Size = UDim2.new(0, 200, 1, 0)
footerRight.Position = UDim2.new(1, -214, 0, 0)
footerRight.BackgroundTransparency = 1
footerRight.Text = S("L-CTRL TO TOGGLE")
footerRight.TextColor3 = Colors.TextDark
footerRight.TextSize = 10
footerRight.Font = Enum.Font.GothamBold
footerRight.TextXAlignment = Enum.TextXAlignment.Right
footerRight.Parent = footerBar

-- 內容容器
local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -SIDEBAR_W, 1, 0)
contentArea.Position = UDim2.new(0, SIDEBAR_W, 0, 0)
contentArea.BackgroundTransparency = 1
contentArea.Parent = bodyFrame

-- ==============================================================================
-- 浮動小圖示
-- ==============================================================================
local miniCrest = Instance.new("TextButton")
miniCrest.Size = UDim2.new(0, 42, 0, 42)
miniCrest.Position = UDim2.new(0, 20, 0.5, -21)
miniCrest.BackgroundColor3 = Color3.fromRGB(16, 12, 26)
miniCrest.BackgroundTransparency = 0.05
miniCrest.AutoButtonColor = false
miniCrest.Text = ""
miniCrest.Active = true
miniCrest.Visible = false
miniCrest.ZIndex = 100
miniCrest.Parent = screenGui

local miniCrestCorner = Instance.new("UICorner")
miniCrestCorner.CornerRadius = UDim.new(1, 0)
miniCrestCorner.Parent = miniCrest

local miniCrestStroke = Instance.new("UIStroke")
miniCrestStroke.Color = Colors.PurplePrimary
miniCrestStroke.Thickness = 1.5
miniCrestStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
miniCrestStroke.Parent = miniCrest

local miniCrestLabel = Instance.new("TextLabel")
miniCrestLabel.Size = UDim2.new(1, 0, 1, 0)
miniCrestLabel.BackgroundTransparency = 1
miniCrestLabel.Text = S("◆")
miniCrestLabel.TextColor3 = Colors.PurplePrimary
miniCrestLabel.TextSize = 18
miniCrestLabel.Font = Enum.Font.GothamBold
miniCrestLabel.Parent = miniCrest

-- ==============================================================================
-- 通知（Toast）
-- ==============================================================================
local toastHolder = Instance.new("Frame")
toastHolder.Size = UDim2.new(0, 280, 1, -40)
toastHolder.Position = UDim2.new(1, -300, 0, 20)
toastHolder.BackgroundTransparency = 1
toastHolder.ZIndex = 500
toastHolder.Parent = screenGui

local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 8)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Top
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastHolder

local toastOrder = 0
local function Notify(title, message, accent)
    accent = accent or Colors.PurpleAccent
    toastOrder = toastOrder + 1

    local toast = Instance.new("Frame")
    toast.Size = UDim2.new(1, 0, 0, 46)
    toast.BackgroundColor3 = Color3.fromRGB(20, 15, 30)
    toast.BackgroundTransparency = 1
    toast.BorderSizePixel = 0
    toast.LayoutOrder = toastOrder
    toast.ZIndex = 501
    toast.Parent = toastHolder

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = toast

    local stroke = Instance.new("UIStroke")
    stroke.Color = accent
    stroke.Thickness = 1
    stroke.Transparency = 1
    stroke.Parent = toast

    -- 左側色條
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 2, 1, -16)
    bar.Position = UDim2.new(0, 0, 0, 8)
    bar.BackgroundColor3 = accent
    bar.BorderSizePixel = 0
    bar.ZIndex = 502
    bar.Parent = toast

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0, 18)
    titleLabel.Position = UDim2.new(0, 12, 0, 6)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = Txt(title)
    titleLabel.TextColor3 = Colors.TextMain
    titleLabel.TextSize = 11
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTransparency = 1
    titleLabel.ZIndex = 502
    titleLabel.Parent = toast

    local msgLabel = Instance.new("TextLabel")
    msgLabel.Size = UDim2.new(1, -20, 0, 16)
    msgLabel.Position = UDim2.new(0, 12, 0, 24)
    msgLabel.BackgroundTransparency = 1
    msgLabel.Text = Txt(message)
    msgLabel.TextColor3 = Colors.TextSecondary
    msgLabel.TextSize = 10
    msgLabel.Font = Enum.Font.Gotham
    msgLabel.TextXAlignment = Enum.TextXAlignment.Left
    msgLabel.TextTruncate = Enum.TextTruncate.AtEnd
    msgLabel.TextTransparency = 1
    msgLabel.ZIndex = 502
    msgLabel.Parent = toast

    -- 進場
    toast.Position = UDim2.new(1, 30, 0, 0)
    local startOrder = toastOrder
    TweenTo(toast, TweenInfoMed, {
        BackgroundTransparency = 0,
        Position = UDim2.new(0, 0, 0, 0)
    }, toast)
    TweenTo(stroke, TweenInfoMed, { Transparency = 0 }, stroke)
    TweenTo(titleLabel, TweenInfoMed, { TextTransparency = 0 }, titleLabel)
    TweenTo(msgLabel, TweenInfoMed, { TextTransparency = 0 }, msgLabel)

    task.delay(3.2, function()
        if not toast.Parent then return end
        local out = TweenService:Create(toast, TweenInfoMed, {
            BackgroundTransparency = 1,
            Position = UDim2.new(1, 30, 0, 0)
        })
        TweenService:Create(stroke, TweenInfoMed, { Transparency = 1 }):Play()
        TweenService:Create(titleLabel, TweenInfoMed, { TextTransparency = 1 }):Play()
        TweenService:Create(msgLabel, TweenInfoMed, { TextTransparency = 1 }):Play()
        out:Play()
        out.Completed:Connect(function()
            toast:Destroy()
        end)
    end)

    return function()
        if toast.Parent then toast:Destroy() end
    end
end

-- ==============================================================================
-- 提示氣泡
-- ==============================================================================
-- 直接掛在 screenGui 並使用「絕對座標」，因此視窗怎麼拖都不會錯位
local tooltipFrame = Instance.new("Frame")
tooltipFrame.Size = UDim2.new(0, 180, 0, 28)
tooltipFrame.BackgroundColor3 = Color3.fromRGB(22, 17, 34)
tooltipFrame.BackgroundTransparency = 0.05
tooltipFrame.BorderSizePixel = 0
tooltipFrame.Visible = false
tooltipFrame.ZIndex = 600
tooltipFrame.Parent = screenGui

local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, 5)
tooltipCorner.Parent = tooltipFrame

local tooltipStroke = Instance.new("UIStroke")
tooltipStroke.Color = Colors.PurpleAccent
tooltipStroke.Thickness = 1
tooltipStroke.Parent = tooltipFrame

local tooltipLabel = Instance.new("TextLabel")
tooltipLabel.Size = UDim2.new(1, -14, 1, -8)
tooltipLabel.Position = UDim2.new(0, 7, 0, 4)
tooltipLabel.BackgroundTransparency = 1
tooltipLabel.Text = ""
tooltipLabel.TextColor3 = Colors.TextMain
tooltipLabel.TextSize = 10
tooltipLabel.Font = Enum.Font.Gotham
tooltipLabel.TextWrapped = true
tooltipLabel.TextXAlignment = Enum.TextXAlignment.Left
tooltipLabel.TextYAlignment = Enum.TextYAlignment.Top
tooltipLabel.ZIndex = 601
tooltipLabel.Parent = tooltipFrame

-- 用固定的大寬度量測，取得真正的單行寬度（width 參數會換行，不適合量測）
local function MeasureOneLine(text, size, font)
    local ok, res = pcall(function()
        return TextService:GetTextSize(text, size, font, Vector2.new(100000, 1000))
    end)
    if ok and res then return res end
    return Vector2.new(#text * size * 0.6, size)
end

local function ShowTooltip(text, sourceGui)
    if not sourceGui or not sourceGui.Parent then return end
    tooltipLabel.Text = Txt(text)

    local measured = MeasureOneLine(text, 10, Enum.Font.Gotham)
    local w = math.clamp(measured.X + 18, 120, 250)
    local h = math.clamp(measured.Y + 12, 26, 90)
    tooltipFrame.Size = UDim2.new(0, w, 0, h)

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

    local abs = sourceGui.AbsolutePosition
    local absSize = sourceGui.AbsoluteSize
    local x = abs.X + absSize.X + 8
    local y = abs.Y + (absSize.Y - h) / 2

    -- 右側放不下就翻到左側
    if x + w > viewport.X - 8 then
        x = abs.X - w - 8
    end
    -- 仍放不下就對齊游標元素
    if x < 8 then
        x = math.clamp(abs.X, 8, math.max(8, viewport.X - w - 8))
    end
    y = math.clamp(y, 8, math.max(8, viewport.Y - h - 8))

    tooltipFrame.Position = UDim2.new(0, Round(x), 0, Round(y))
    tooltipFrame.Visible = true
end

local function HideTooltip()
    tooltipFrame.Visible = false
end

-- ==============================================================================
-- 分頁系統
-- ==============================================================================
local tabs = {}
local tabButtons = {}
local pageRows = {}          -- [page] = { row, row, ... } 供搜尋快速走訪
local currentTabName = nil
local openDropdowns = {}     -- 目前展開的下拉選單，切分頁或點空白處時關閉

local function CloseAllDropdowns()
    for dd, closeFn in pairs(openDropdowns) do
        if closeFn then closeFn() end
        openDropdowns[dd] = nil
    end
end

local function CreateTabContent(name)
    local tabScroll = Instance.new("ScrollingFrame")
    tabScroll.Name = RandName()
    tabScroll.Size = UDim2.new(1, -28, 1, -20)
    tabScroll.Position = UDim2.new(0, 14, 0, 10)
    tabScroll.BackgroundTransparency = 1
    tabScroll.BorderSizePixel = 0
    tabScroll.ScrollBarThickness = 3
    tabScroll.ScrollBarImageColor3 = Colors.PurpleAccent
    tabScroll.ScrollBarImageTransparency = 0.35
    tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    tabScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    tabScroll.ClipsDescendants = true
    tabScroll.Visible = false
    tabScroll.Parent = contentArea

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = tabScroll

    local pad = Instance.new("UIPadding")
    pad.PaddingBottom = UDim.new(0, 14)
    pad.Parent = tabScroll

    tabs[name] = tabScroll
    pageRows[name] = {}
    return tabScroll
end

local function SwitchTab(tabName)
    CloseAllDropdowns()
    HideTooltip()
    currentTabName = tabName
    for name, page in pairs(tabs) do
        page.Visible = (name == tabName)
    end
    for name, btnData in pairs(tabButtons) do
        local isActive = (name == tabName)
        btnData.Indicator.Visible = isActive
        btnData.Button.BackgroundTransparency = isActive and 0.65 or 1
        btnData.Label.TextColor3 = isActive and Colors.PurplePrimary or Colors.TextSecondary
        btnData.Icon.TextColor3 = isActive and Colors.PurplePrimary or Colors.TextMuted
    end
end

local function CreateNavButton(name, icon, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = Colors.RowBgHover
    btn.BackgroundTransparency = 1
    btn.AutoButtonColor = false
    btn.Text = ""
    btn.LayoutOrder = order
    btn.Parent = navList

    local indicator = Instance.new("Frame")
    indicator.Size = UDim2.new(0, 2.5, 0, 18)
    indicator.Position = UDim2.new(0, 0, 0.5, -9)
    indicator.BackgroundColor3 = Colors.PurpleAccent
    indicator.BorderSizePixel = 0
    indicator.Visible = false
    indicator.Parent = btn

    local iconLabel = Instance.new("TextLabel")
    iconLabel.Size = UDim2.new(0, 24, 1, 0)
    iconLabel.Position = UDim2.new(0, 12, 0, 0)
    iconLabel.BackgroundTransparency = 1
    iconLabel.Text = icon or "●"
    iconLabel.TextColor3 = Colors.TextMuted
    iconLabel.TextSize = 12
    iconLabel.Parent = btn

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, -50, 1, 0)
    textLabel.Position = UDim2.new(0, 38, 0, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = Txt(name)
    textLabel.TextColor3 = Colors.TextSecondary
    textLabel.TextSize = 12
    textLabel.Font = Enum.Font.GothamMedium
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.Parent = btn

    btn.MouseEnter:Connect(function()
        if currentTabName ~= name then
            if Debounce(btn, 0.05) then
                TweenTo(btn, TweenInfoFast, { BackgroundTransparency = 0.75 }, btn)
            end
            TweenTo(textLabel, TweenInfoFast, { TextColor3 = Colors.TextMain }, textLabel)
            TweenTo(iconLabel, TweenInfoFast, { TextColor3 = Colors.PurpleAccent }, iconLabel)
        end
    end)
    btn.MouseLeave:Connect(function()
        if currentTabName ~= name then
            TweenTo(btn, TweenInfoFast, { BackgroundTransparency = 1 }, btn)
            TweenTo(textLabel, TweenInfoFast, { TextColor3 = Colors.TextSecondary }, textLabel)
            TweenTo(iconLabel, TweenInfoFast, { TextColor3 = Colors.TextMuted }, iconLabel)
        end
    end)
    btn.MouseButton1Click:Connect(function()
        SwitchTab(name)
    end)

    tabButtons[name] = {
        Button = btn,
        Indicator = indicator,
        Label = textLabel,
        Icon = iconLabel
    }
    return btn
end

-- ==============================================================================
-- 控件構建
-- ==============================================================================
local function IsInstance(v)
    return typeof(v) == "Instance"
end

-- 參數正規化：相容舊式 (parent, label, ...) 與新式 (configTable) 兩種寫法，
-- 並額外支援 config.Description 作為提示文字。
local function NormalizeConfig(parentOrConfig, label, description)
    local cfg
    if IsInstance(parentOrConfig) then
        cfg = { Parent = parentOrConfig, Label = label, Description = description }
    else
        cfg = parentOrConfig or {}
        cfg.Parent = cfg.Parent or cfg.parent
        cfg.Label = cfg.Label or cfg.label or label
        cfg.Description = cfg.Description or cfg.description or cfg.info or description
    end
    cfg.Parent = cfg.Parent or contentArea
    cfg.Label = cfg.Label or "Option"
    cfg.Description = cfg.Description or ""
    return cfg
end

-- 註冊列以供搜尋使用
local function RegisterRow(page, row, labelText)
    if not page or not row then return end
    if not pageRows[page] then pageRows[page] = {} end
    table.insert(pageRows[page], row)
    row:SetAttribute("SearchKey", string.lower(tostring(labelText or "")):gsub("%s+", ""))
end

-- 建立「標題 + 提示徽章」的自動寬度容器，避免用像素硬算造成重疊
local function CreateHeaderInside(row, cfg, maxWidth, headerHeight, yOffset)
    local holder = Instance.new("Frame")
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.new(0, 0, 0, headerHeight)
    holder.Position = UDim2.new(0, 0, 0, yOffset or 0)
    holder.AutomaticSize = Enum.AutomaticSize.X
    holder.Parent = row

    local hLayout = Instance.new("UIListLayout")
    hLayout.FillDirection = Enum.FillDirection.Horizontal
    hLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    hLayout.SortOrder = Enum.SortOrder.LayoutOrder
    hLayout.Padding = UDim.new(0, 6)
    hLayout.Parent = holder

    local constraint = Instance.new("UISizeConstraint")
    constraint.MaxSize = Vector2.new(maxWidth, headerHeight)
    constraint.Parent = holder

    local cursorX = 0
    if cfg.Diamond then
        local diamond = Instance.new("TextLabel")
        diamond.Size = UDim2.new(0, 10, 1, 0)
        diamond.BackgroundTransparency = 1
        diamond.Text = "◆"
        diamond.TextColor3 = Colors.PurplePrimary
        diamond.TextSize = 9
        diamond.LayoutOrder = 1
        diamond.Parent = holder
        cursorX = 10
    end

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.AutomaticSize = Enum.AutomaticSize.X
    label.Text = Txt(cfg.Label)
    label.TextColor3 = Colors.TextMain
    label.TextSize = 12
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.LayoutOrder = 2
    label.Parent = holder

    if cfg.Description ~= "" then
        local badge = Instance.new("TextButton")
        badge.Size = UDim2.new(0, 15, 0, 15)
        badge.BackgroundColor3 = Color3.fromRGB(25, 18, 40)
        badge.AutoButtonColor = false
        badge.Text = "?"
        badge.TextColor3 = Colors.PurpleMuted
        badge.TextSize = 10
        badge.Font = Enum.Font.GothamBold
        badge.LayoutOrder = 3
        badge.Parent = holder

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = badge

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(75, 48, 115)
        stroke.Thickness = 1
        stroke.Parent = badge

        badge.MouseEnter:Connect(function()
            TweenTo(badge, TweenInfoFast, { TextColor3 = Colors.PurplePrimary }, badge)
            TweenTo(stroke, TweenInfoFast, { Color = Colors.PurpleAccent }, stroke)
            ShowTooltip(cfg.Description, badge)
        end)
        badge.MouseLeave:Connect(function()
            TweenTo(badge, TweenInfoFast, { TextColor3 = Colors.PurpleMuted }, badge)
            TweenTo(stroke, TweenInfoFast, { Color = Color3.fromRGB(75, 48, 115) }, stroke)
            HideTooltip()
        end)
    end

    return holder, cursorX + label.TextBounds.X
end

-- 建立列的外框（共用）
local function CreateRowBase(page, cfg, height)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, height)
    row.BackgroundTransparency = 1
    row.Parent = cfg.Parent
    RegisterRow(page, row, cfg.Label)
    return row
end

local function ResolvePage(cfg)
    -- 沿用呼叫端目前選取的分頁；若 config 有指定就用指定的
    return cfg.Page or tabs[currentTabName] or contentArea
end

function CreateCategoryHeader(parent, titleText)
    local headerFrame = Instance.new("Frame")
    headerFrame.Size = UDim2.new(1, 0, 0, 26)
    headerFrame.BackgroundTransparency = 1
    headerFrame:SetAttribute("IsCategoryHeader", true) -- 供搜尋時辨識，避免用字體猜測
    headerFrame.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -20, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = Txt(tostring(titleText):upper())
    lbl.TextColor3 = Colors.PurpleAccent
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = headerFrame

    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, 0, 0, 1)
    div.Position = UDim2.new(0, 0, 1, -1)
    div.BackgroundColor3 = Color3.fromRGB(34, 25, 52)
    div.BorderSizePixel = 0
    div.Parent = headerFrame

    return headerFrame
end

function CreateInfoRow(parent, labelText, valueText, hasDiamondBullet)
    local cfg = NormalizeConfig(parent, labelText)
    cfg.Diamond = hasDiamondBullet
    local row = CreateRowBase(ResolvePage(cfg), cfg, 36)

    local holder, usedWidth = CreateHeaderInside(row, cfg, 380, 36, 0)

    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(1, -(usedWidth + 30), 1, 0)
    valLabel.Position = UDim2.new(0, usedWidth + 20, 0, 0)
    valLabel.BackgroundTransparency = 1
    valLabel.Text = Txt(valueText)
    valLabel.TextColor3 = Colors.TextSecondary
    valLabel.TextSize = 11
    valLabel.Font = Enum.Font.Gotham
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.TextTruncate = Enum.TextTruncate.AtEnd
    valLabel.Parent = row

    return {
        Row = row,
        Label = holder,
        SetValue = function(v) valLabel.Text = Txt(v) end,
        GetValue = function() return valLabel.Text end
    }
end

function CreateToggleRow(parent, labelText, description, defaultState, callback, hasDiamondBullet)
    local cfg = NormalizeConfig(parent, labelText, description)

    -- 相容舊簽名：第 4 個參數是布林（狀態）、第 5 個是回呼
    local state = defaultState
    local cb = callback
    if type(description) == "boolean" then
        state = description
        cb = defaultState
    elseif type(description) == "table" then
        local t = description
        state = t.Default ~= nil and t.Default or t.default or state
        cb = t.Callback or t.callback or cb
        cfg.Description = t.Description or t.description or cfg.Description
        cfg.Diamond = t.Diamond ~= nil and t.Diamond or hasDiamondBullet
    end
    cfg.Diamond = cfg.Diamond or hasDiamondBullet

    local page = ResolvePage(cfg)
    local row = CreateRowBase(page, cfg, 36)
    CreateHeaderInside(row, cfg, 300, 36, 0)

    local switchTrack = Instance.new("TextButton")
    switchTrack.Size = UDim2.new(0, 36, 0, 18)
    switchTrack.Position = UDim2.new(1, -44, 0.5, -9)
    switchTrack.BackgroundColor3 = state and Colors.ToggleTrackOn or Colors.ToggleTrackOff
    switchTrack.AutoButtonColor = false
    switchTrack.Text = ""
    switchTrack.Parent = row

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 9)
    trackCorner.Parent = switchTrack

    local trackStroke = Instance.new("UIStroke")
    trackStroke.Color = state and Color3.fromRGB(120, 68, 185) or Color3.fromRGB(50, 38, 72)
    trackStroke.Thickness = 1
    trackStroke.Parent = switchTrack

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    knob.BackgroundColor3 = state and Colors.ToggleKnobOn or Colors.ToggleKnobOff
    knob.BorderSizePixel = 0
    knob.Parent = switchTrack

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(0, 3)
    knobCorner.Parent = knob

    local current = state
    local function updateState(newState, callCb)
        current = newState and true or false
        TweenTo(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = current and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7),
            BackgroundColor3 = current and Colors.ToggleKnobOn or Colors.ToggleKnobOff
        }, knob)
        TweenTo(switchTrack, TweenInfo.new(0.18), {
            BackgroundColor3 = current and Colors.ToggleTrackOn or Colors.ToggleTrackOff
        }, switchTrack)
        TweenTo(trackStroke, TweenInfo.new(0.18), {
            Color = current and Color3.fromRGB(120, 68, 185) or Color3.fromRGB(50, 38, 72)
        }, trackStroke)
        if callCb and cb then cb(current) end
    end

    switchTrack.MouseButton1Click:Connect(function()
        updateState(not current, true)
    end)

    return {
        Row = row,
        SetState = function(v) updateState(v, false) end,
        SetValue = function(v) updateState(v, false) end,
        GetState = function() return current end,
        GetValue = function() return current end
    }
end

function CreateSliderRow(parent, labelText, description, minVal, maxVal, defaultVal, isFloat, suffix, callback, hasDiamondBullet)
    local cfg = NormalizeConfig(parent, labelText, description)

    local minV, maxV, defV = minVal, maxVal, defaultVal
    local floatMode, sfx, cb = isFloat, suffix, callback
    local diamond = hasDiamondBullet

    -- 相容舊簽名：(..., min, max, default, isFloat, suffix, callback, diamond)
    if type(description) == "table" then
        local t = description
        minV = t.Min or t.min or minV
        maxV = t.Max or t.max or maxV
        defV = t.Default or t.default or t.Value or defV
        floatMode = t.Float ~= nil and t.Float or t.IsFloat or floatMode
        sfx = t.Suffix or t.suffix or sfx
        cb = t.Callback or t.callback or cb
        cfg.Description = t.Description or t.description or cfg.Description
        diamond = t.Diamond ~= nil and t.Diamond or diamond
    end

    minV = tonumber(minV) or 0
    maxV = tonumber(maxV) or 100
    if maxV <= minV then maxV = minV + 1 end
    defV = math.clamp(tonumber(defV) or minV, minV, maxV)
    sfx = sfx or ""
    cfg.Diamond = cfg.Diamond or diamond

    local page = ResolvePage(cfg)
    local row = CreateRowBase(page, cfg, 44)
    CreateHeaderInside(row, cfg, 300, 20, 0)

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(0, 80, 0, 16)
    valueLabel.Position = UDim2.new(1, -88, 0, 2)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = floatMode and string.format("%.3f%s", defV, sfx) or string.format("%d%s", math.floor(defV + 0.5), sfx)
    valueLabel.TextColor3 = Colors.TextMain
    valueLabel.TextSize = 11
    valueLabel.Font = Enum.Font.GothamMedium
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = row

    -- 滑軌由實際像素寬度驅動，數值換算就不會因為版面改動而失準
    local SLIDER_W = 300
    local trackHolder = Instance.new("Frame")
    trackHolder.Size = UDim2.new(1, -20, 0, 16)
    trackHolder.Position = UDim2.new(0, 10, 0, 25)
    trackHolder.BackgroundTransparency = 1
    trackHolder.Parent = row

    local sliderTrack = Instance.new("Frame")
    sliderTrack.Size = UDim2.new(0, SLIDER_W, 0, 2)
    sliderTrack.Position = UDim2.new(0, 0, 0.5, -1)
    sliderTrack.BackgroundColor3 = Colors.SliderTrack
    sliderTrack.BorderSizePixel = 0
    sliderTrack.Parent = trackHolder

    local sliderFill = Instance.new("Frame")
    sliderFill.Size = UDim2.new(0, 0, 1, 0)
    sliderFill.BackgroundColor3 = Colors.SliderFill
    sliderFill.BorderSizePixel = 0
    sliderFill.Parent = sliderTrack

    local diamondKnob = Instance.new("Frame")
    diamondKnob.Size = UDim2.new(0, 9, 0, 9)
    diamondKnob.Position = UDim2.new(1, -4.5, 0.5, -4.5)
    diamondKnob.Rotation = 45
    diamondKnob.BackgroundColor3 = Colors.SliderKnob
    diamondKnob.BorderSizePixel = 0
    diamondKnob.Parent = sliderFill

    local dragging = false
    local currentValue = defV

    local function formatValue(v)
        if floatMode then
            return string.format("%.3f%s", v, sfx)
        end
        -- 原本用 floor(v + 0.5)，負數會錯誤進位，改用四捨五入
        return string.format("%d%s", Round(v), sfx)
    end

    local function setValue(val, callCb)
        if val ~= val then return end -- NaN 防護
        currentValue = math.clamp(val, minV, maxV)
        local pct = (currentValue - minV) / (maxV - minV)
        sliderFill.Size = UDim2.new(pct, 0, 1, 0)
        valueLabel.Text = formatValue(currentValue)
        if callCb and cb then cb(currentValue) end
    end

    local hitZone = Instance.new("TextButton")
    hitZone.Size = UDim2.new(1, 16, 1, 12)
    hitZone.Position = UDim2.new(0, -8, 0.5, -6)
    hitZone.BackgroundTransparency = 1
    hitZone.Text = ""
    hitZone.Parent = trackHolder

    local function valueFromInput(input)
        local absTrack = sliderTrack.AbsolutePosition
        local absSize = sliderTrack.AbsoluteSize
        local width = absSize.X > 1 and absSize.X or SLIDER_W
        local relX = math.clamp(input.Position.X - absTrack.X, 0, width)
        setValue(minV + ((relX / width) * (maxV - minV)), true)
    end

    hitZone.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            valueFromInput(input)
        end
    end)

    Track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            valueFromInput(input)
        end
    end))

    Track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    hitZone.MouseEnter:Connect(function()
        TweenTo(diamondKnob, TweenInfoFast, { BackgroundColor3 = Colors.ToggleKnobOn }, diamondKnob)
    end)
    hitZone.MouseLeave:Connect(function()
        if not dragging then
            TweenTo(diamondKnob, TweenInfoFast, { BackgroundColor3 = Colors.SliderKnob }, diamondKnob)
        end
    end)

    setValue(defV, false)

    return {
        Row = row,
        SetValue = function(v) setValue(v, false) end,
        GetValue = function() return currentValue end
    }
end

function CreateDropdownRow(parent, labelText, description, options, defaultOption, callback, hasDiamondBullet, subText)
    local cfg = NormalizeConfig(parent, labelText, description)

    local opts, defOpt, cb, diamond, sub = options, defaultOption, callback, hasDiamondBullet, subText

    -- 相容舊簽名：(..., options, default, callback, diamond, subText)
    if type(description) == "table" then
        local t = description
        opts = t.Options or t.options or opts
        defOpt = t.Default or t.default or t.Value or defOpt
        cb = t.Callback or t.callback or cb
        diamond = t.Diamond ~= nil and t.Diamond or diamond
        sub = t.Sub or t.subText or t.Description2 or sub
        cfg.Description = t.Description or t.description or cfg.Description
    end

    opts = opts or {}
    if #opts == 0 then opts = { "None" } end
    defOpt = defOpt or opts[1]
    cfg.Diamond = cfg.Diamond or diamond
    if sub and sub ~= "" and cfg.Description == "" then
        cfg.Description = sub
    end

    local page = ResolvePage(cfg)
    local totalHeight = (sub and sub ~= "") and 52 or 36
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, totalHeight)
    row.BackgroundTransparency = 1
    row.ZIndex = 5
    row.Parent = cfg.Parent
    RegisterRow(page, row, cfg.Label)

    CreateHeaderInside(row, cfg, 300, 36, 0)

    if sub and sub ~= "" then
        local subLabel = Instance.new("TextLabel")
        subLabel.Size = UDim2.new(1, -4, 0, 16)
        subLabel.Position = UDim2.new(0, cfg.Diamond and 14 or 0, 0, 32)
        subLabel.BackgroundTransparency = 1
        subLabel.Text = Txt(sub)
        subLabel.TextColor3 = Colors.PurpleMuted
        subLabel.TextSize = 10
        subLabel.Font = Enum.Font.Gotham
        subLabel.TextXAlignment = Enum.TextXAlignment.Left
        subLabel.ZIndex = 6
        subLabel.Parent = row
    end

    local ddBox = Instance.new("TextButton")
    ddBox.Size = UDim2.new(0, 168, 0, 26)
    ddBox.Position = UDim2.new(1, -176, 0, 5)
    ddBox.BackgroundColor3 = Colors.DropdownBg
    ddBox.AutoButtonColor = false
    ddBox.Text = ""
    ddBox.ZIndex = 6
    ddBox.Parent = row

    local ddCorner = Instance.new("UICorner")
    ddCorner.CornerRadius = UDim.new(0, 4)
    ddCorner.Parent = ddBox

    local ddStroke = Instance.new("UIStroke")
    ddStroke.Color = Colors.DropdownBorder
    ddStroke.Thickness = 1
    ddStroke.Parent = ddBox

    local selectedText = Instance.new("TextLabel")
    selectedText.Size = UDim2.new(1, -30, 1, 0)
    selectedText.Position = UDim2.new(0, 10, 0, 0)
    selectedText.BackgroundTransparency = 1
    selectedText.Text = Txt(defOpt)
    selectedText.TextColor3 = Colors.TextMain
    selectedText.TextSize = 11
    selectedText.Font = Enum.Font.Gotham
    selectedText.TextXAlignment = Enum.TextXAlignment.Left
    selectedText.TextTruncate = Enum.TextTruncate.AtEnd
    selectedText.ZIndex = 7
    selectedText.Parent = ddBox

    local chevron = Instance.new("TextLabel")
    chevron.Size = UDim2.new(0, 20, 1, 0)
    chevron.Position = UDim2.new(1, -24, 0, 0)
    chevron.BackgroundTransparency = 1
    chevron.Text = "▾"
    chevron.TextColor3 = Colors.PurpleMuted
    chevron.TextSize = 12
    chevron.Font = Enum.Font.GothamBold
    chevron.ZIndex = 7
    chevron.Parent = ddBox

    local LIST_ITEM_H = 24
    local listFrame = Instance.new("Frame")
    listFrame.Size = UDim2.new(0, 168, 0, #opts * LIST_ITEM_H + 6)
    listFrame.BackgroundColor3 = Colors.DropdownBg
    listFrame.BorderSizePixel = 0
    listFrame.Visible = false
    listFrame.ZIndex = 150
    listFrame.Parent = mainFrame

    local listCorner = Instance.new("UICorner")
    listCorner.CornerRadius = UDim.new(0, 4)
    listCorner.Parent = listFrame

    local listStroke = Instance.new("UIStroke")
    listStroke.Color = Colors.PurpleAccent
    listStroke.Thickness = 1
    listStroke.Parent = listFrame

    local menuScroll = Instance.new("ScrollingFrame")
    menuScroll.Size = UDim2.new(1, -4, 1, -4)
    menuScroll.Position = UDim2.new(0, 2, 0, 2)
    menuScroll.BackgroundTransparency = 1
    menuScroll.BorderSizePixel = 0
    menuScroll.ScrollBarThickness = 3
    menuScroll.ScrollBarImageColor3 = Colors.PurpleAccent
    menuScroll.CanvasSize = UDim2.new(0, 0, 0, #opts * LIST_ITEM_H)
    menuScroll.ZIndex = 151
    menuScroll.Parent = listFrame

    local menuLayout = Instance.new("UIListLayout")
    menuLayout.Padding = UDim.new(0, 1)
    menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
    menuLayout.Parent = menuScroll

    local currentSelected = defOpt
    local optionButtons = {}

    -- 重貼齊：同時處理視窗拖曳、分頁捲動與視窗尺寸變化
    local function Reposition()
        if not listFrame.Visible then return end
        local absBox = ddBox.AbsolutePosition
        local absMain = mainFrame.AbsolutePosition
        local x = absBox.X - absMain.X
        local y = absBox.Y - absMain.Y + ddBox.AbsoluteSize.Y + 3
        local listH = listFrame.AbsoluteSize.Y
        -- 往下超過視窗就翻到上方
        if y + listH > mainFrame.AbsoluteSize.Y - 4 then
            local above = (absBox.Y - absMain.Y) - listH - 3
            if above >= 4 then
                y = above
            else
                y = math.max(4, mainFrame.AbsoluteSize.Y - 4 - listH)
            end
        end
        listFrame.Position = UDim2.new(0, Round(x), 0, Round(y))
    end

    local function setOpen(open)
        listFrame.Visible = open
        chevron.Text = open and "▴" or "▾"
        TweenTo(ddStroke, TweenInfoFast, {
            Color = open and Colors.PurpleAccent or Colors.DropdownBorder
        }, ddStroke)
        if open then
            openDropdowns[listFrame] = function() setOpen(false) end
            Reposition()
        else
            openDropdowns[listFrame] = nil
        end
    end

    local function selectOption(opt, callCb)
        currentSelected = opt
        selectedText.Text = Txt(opt)
        for name, btn in pairs(optionButtons) do
            btn.TextColor3 = (name == currentSelected) and Colors.PurplePrimary or Colors.TextSecondary
        end
        setOpen(false)
        if callCb ~= false and cb then cb(opt) end
    end

    for index, optName in ipairs(opts) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, 0, 0, LIST_ITEM_H)
        optBtn.BackgroundColor3 = Color3.fromRGB(36, 24, 56)
        optBtn.BackgroundTransparency = 1
        optBtn.AutoButtonColor = false
        optBtn.Text = "   " .. Txt(optName)
        optBtn.TextColor3 = (optName == currentSelected) and Colors.PurplePrimary or Colors.TextSecondary
        optBtn.TextSize = 11
        optBtn.Font = Enum.Font.Gotham
        optBtn.TextXAlignment = Enum.TextXAlignment.Left
        optBtn.TextTruncate = Enum.TextTruncate.AtEnd
        optBtn.LayoutOrder = index
        optBtn.ZIndex = 152
        optBtn.Parent = menuScroll
        optionButtons[optName] = optBtn

        optBtn.MouseEnter:Connect(function()
            optBtn.BackgroundTransparency = 0
            optBtn.TextColor3 = Colors.PurplePrimary
        end)
        optBtn.MouseLeave:Connect(function()
            optBtn.BackgroundTransparency = 1
            -- 已選項目保持高亮，原本會被這裡蓋掉
            optBtn.TextColor3 = (optName == currentSelected) and Colors.PurplePrimary or Colors.TextSecondary
        end)
        optBtn.MouseButton1Click:Connect(function()
            selectOption(optName, true)
        end)
    end

    ddBox.MouseButton1Click:Connect(function()
        setOpen(not listFrame.Visible)
    end)

    -- 捲動內容區時，展開的選單要跟著跑
    if page:IsA("ScrollingFrame") then
        page:GetPropertyChangedSignal("CanvasPosition"):Connect(Reposition)
        page:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(Reposition)
    end
    contentArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(Reposition)

    return {
        Row = row,
        SetOption = function(v) selectOption(v, false) end,
        GetOption = function() return currentSelected end,
        Open = function() setOpen(true) end,
        Close = function() setOpen(false) end,
        IsOpen = function() return listFrame.Visible end
    }
end

function CreateButtonRow(parent, labelText, buttonText, iconText, isRed, callback)
    local cfg = NormalizeConfig(parent, labelText)
    local page = ResolvePage(cfg)

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundTransparency = 1
    row.Parent = cfg.Parent
    RegisterRow(page, row, cfg.Label)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 200, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = Txt(cfg.Label)
    label.TextColor3 = Colors.TextMain
    label.TextSize = 12
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 120, 0, 26)
    btn.Position = UDim2.new(1, -128, 0.5, -13)
    btn.BackgroundColor3 = Colors.ButtonBg
    btn.AutoButtonColor = false
    btn.Text = (iconText and iconText .. "  " or "") .. Txt(tostring(buttonText or "OK"):upper())
    btn.TextColor3 = isRed and Colors.Danger or Colors.CalmText
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.Parent = row

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = btn

    local stroke = Instance.new("UIStroke")
    stroke.Color = isRed and Colors.DangerStroke or Colors.CalmStroke
    stroke.Thickness = 1
    stroke.Parent = btn

    local baseStroke = stroke.Color
    local baseText = btn.TextColor3

    btn.MouseEnter:Connect(function()
        TweenTo(stroke, TweenInfoMed, {
            Color = isRed and Color3.fromRGB(255, 75, 75) or Colors.PurplePrimary
        }, stroke)
        TweenTo(btn, TweenInfoMed, {
            BackgroundColor3 = isRed and Color3.fromRGB(45, 20, 20) or Color3.fromRGB(38, 26, 60)
        }, btn)
    end)
    btn.MouseLeave:Connect(function()
        TweenTo(stroke, TweenInfoMed, { Color = baseStroke }, stroke)
        TweenTo(btn, TweenInfoMed, { BackgroundColor3 = Colors.ButtonBg }, btn)
    end)

    -- 按下回饋
    btn.MouseButton1Down:Connect(function()
        TweenTo(btn, TweenInfoFast, { BackgroundColor3 = isRed and Color3.fromRGB(58, 24, 24) or Color3.fromRGB(48, 33, 74) }, btn)
    end)
    btn.MouseButton1Up:Connect(function()
        TweenTo(btn, TweenInfoMed, {
            BackgroundColor3 = isRed and Color3.fromRGB(45, 20, 20) or Color3.fromRGB(38, 26, 60)
        }, btn)
    end)

    btn.MouseButton1Click:Connect(function()
        if not Debounce(btn, 0.25) then return end
        if callback then
            local ok, err = pcall(callback)
            if not ok then
                Notify("Action Error", tostring(err), Color3.fromRGB(255, 100, 100))
            end
        end
    end)

    return {
        Row = row,
        Button = btn,
        SetText = function(v) btn.Text = (iconText and iconText .. "  " or "") .. Txt(tostring(v):upper()) end,
        SetEnabled = function(v)
            btn.Active = v and true or false
            btn.AutoButtonColor = false
            btn.TextColor3 = v and baseText or Colors.TextDark
            btn.BackgroundTransparency = v and 0 or 0.4
        end
    }
end

-- ==============================================================================
-- 視窗控制（開關 / 最小化 / 卸載 / 搜尋）
-- ==============================================================================
local isUiVisible = true
local isWindowMinimized = false
local normalSize = mainFrame.Size -- 記住實際尺寸，不要寫死

local function ToggleUiVisibility(force)
    if force ~= nil then
        isUiVisible = force and true or false
    else
        isUiVisible = not isUiVisible
    end
    mainFrame.Visible = isUiVisible
    miniCrest.Visible = not isUiVisible
    HideTooltip()
    if not isUiVisible then
        CloseAllDropdowns()
    end
    return isUiVisible
end

local function SetMinimized(minimized)
    if minimized == isWindowMinimized then return end
    isWindowMinimized = minimized

    CloseAllDropdowns()
    HideTooltip()

    if isWindowMinimized then
        normalSize = mainFrame.Size -- 還原時用這個，不再寫死 680x460
        bodyFrame.Visible = false
        footerBar.Visible = false
        topDivider.Visible = false
        TweenTo(mainFrame, TweenInfoMed, {
            Size = UDim2.new(normalSize.X.Scale, normalSize.X.Offset, 0, TOPBAR_H)
        }, "windowSize")
        gameLabel.Text = Txt("Minimized")
    else
        bodyFrame.Visible = true
        footerBar.Visible = true
        topDivider.Visible = true
        TweenTo(mainFrame, TweenInfoMed, { Size = normalSize }, "windowSize")
        gameLabel.Text = Txt("Dashboard")
    end
end

local function UnloadUI()
    HideTooltip()
    CloseAllDropdowns()
    for key, tween in pairs(activeTweens) do
        pcall(function() tween:Cancel() end)
        activeTweens[key] = nil
    end
    for i = #uiConnections, 1, -1 do
        local conn = uiConnections[i]
        if conn then
            pcall(function()
                if conn.Connected then conn:Disconnect() end
            end)
        end
        uiConnections[i] = nil
    end
    if screenGui then screenGui:Destroy() end
end

-- 最小化：按鈕或雙擊標題列
minBtn.MouseButton1Click:Connect(function()
    SetMinimized(not isWindowMinimized)
end)

local lastTopBarClick = 0
topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local now = os.clock()
        if now - lastTopBarClick < 0.32 then
            SetMinimized(not isWindowMinimized)
            lastTopBarClick = 0
        else
            lastTopBarClick = now
        end
    end
end)

closeBtn.MouseButton1Click:Connect(UnloadUI)

-- 標題列與浮動圖示都可拖曳
MakeDraggable(mainFrame, topBar)
MakeDraggable(miniCrest)

miniCrest.MouseButton1Click:Connect(function()
    ToggleUiVisibility()
end)

-- 點擊畫面空白處關閉所有下拉選單
Track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        CloseAllDropdowns()
    end
end))

-- 鍵盤熱鍵開關
local toggleKey = Enum.KeyCode.LeftControl
Track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == toggleKey then
        ToggleUiVisibility()
    end
end))

-- 即時搜尋：改用每列的 SearchKey 屬性比對，並連動分類標題
local lastQuery = ""
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    local q = searchBox.Text:lower():gsub("%s+", "")
    if q == lastQuery then return end
    lastQuery = q

    for _, page in pairs(tabs) do
        local rows = pageRows[page] or {}
        for _, row in ipairs(rows) do
            if not row.Parent then
                -- 已被回收，跳過
            elseif q == "" then
                row.Visible = true
            else
                local key = row:GetAttribute("SearchKey") or ""
                row.Visible = (key:find(q, 1, true) ~= nil)
            end
        end
        -- 分類標題：該標題之後若沒有任何可見列就一起藏起來
        local children = page:GetChildren()
        table.sort(children, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
        local lastHeader = nil
        local headerHasVisibleRow = false
        for _, child in ipairs(children) do
            if child:IsA("Frame") then
                if child:GetAttribute("IsCategoryHeader") then
                    if lastHeader then lastHeader.Visible = headerHasVisibleRow end
                    lastHeader = child
                    headerHasVisibleRow = false
                elseif child:GetAttribute("SearchKey") then
                    if child.Visible then headerHasVisibleRow = true end
                end
            end
        end
        if lastHeader then lastHeader.Visible = headerHasVisibleRow end
    end
end)

-- 按 Esc 或 Enter 失焦時清空搜尋
searchBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        searchBox.Text = ""
    end
end)

-- ==============================================================================
-- 視窗進場動畫
-- ==============================================================================
mainFrame.BackgroundTransparency = 1
mainStroke.Transparency = 1
TweenTo(mainFrame, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
    BackgroundTransparency = 0
}, "fadeIn")
TweenTo(mainStroke, TweenInfo.new(0.28), { Transparency = 0 }, "fadeInStroke")

-- ==============================================================================
-- 分頁與範例內容
-- ==============================================================================
local tabNames = {
    { Name = "Home",     Icon = "◈" },
    { Name = "Settings", Icon = "≡" },
    { Name = "Visuals",  Icon = "✦" }
}

for i, tabInfo in ipairs(tabNames) do
    CreateNavButton(tabInfo.Name, tabInfo.Icon, i)
    CreateTabContent(tabInfo.Name)
end

SwitchTab("Home")

local homePage = tabs["Home"]
CreateCategoryHeader(homePage, "SYSTEM STATUS")
CreateInfoRow(homePage, "Current User", (LocalPlayer and LocalPlayer.Name) or "Player", false)
CreateInfoRow(homePage, "Interface Engine", "Identical UI v1.1", true)
CreateInfoRow(homePage, "Execution State", "READY", true)

CreateCategoryHeader(homePage, "CONTROL OPTIONS")
CreateToggleRow(homePage, "Example Toggle", "This is a tooltip describing the toggle feature.", true, function(state)
    footerLeft.Text = Txt("Toggle: " .. (state and "ENABLED" or "DISABLED"))
end)

CreateSliderRow(homePage, "Accuracy Slider", "Adjust intensity scale.", 0, 100, 75, false, "%", function(val)
    footerLeft.Text = Txt(string.format("Accuracy: %d%%", Round(val)))
end)

CreateDropdownRow(homePage, "Target Mode", "Select an operational mode.", { "Camera", "Predictive", "Closest" }, "Camera", function(opt)
    Notify("Target Mode", "Switched to " .. tostring(opt))
end)

CreateButtonRow(homePage, "Action Test", "EXECUTE", "▶", false, function()
    Notify("Action", "Example button executed.", Colors.StatusActive)
end)

local settingsPage = tabs["Settings"]
CreateCategoryHeader(settingsPage, "KEYBINDS & MANAGEMENT")
CreateDropdownRow(settingsPage, "Toggle Keybind", "Key to show/hide the main window.",
    { "LeftControl", "RightShift", "Insert", "F4", "V" }, "LeftControl", function(opt)
        if Enum.KeyCode[opt] then
            toggleKey = Enum.KeyCode[opt]
            footerRight.Text = Txt(opt:upper() .. " TO TOGGLE")
        end
    end)

CreateButtonRow(settingsPage, "Unload UI", "UNLOAD", "✕", true, function()
    Notify("Unloading", "Interface closing...", Color3.fromRGB(255, 120, 120))
    task.delay(0.35, UnloadUI)
end)

local visualsPage = tabs["Visuals"]
CreateCategoryHeader(visualsPage, "APPEARANCE")
CreateInfoRow(visualsPage, "Theme", "Identical Purple", true)
CreateButtonRow(visualsPage, "Show Notification", "TEST", "◆", false, function()
    Notify("Notification", "Toast system is working.")
end)

-- ==============================================================================
-- 對外 API
-- ==============================================================================
local API = {
    ScreenGui = screenGui,
    Window = mainFrame,
    MiniCrest = miniCrest,
    Tabs = tabs,

    Notify = Notify,
    Show = function() return ToggleUiVisibility(true) end,
    Hide = function() return ToggleUiVisibility(false) end,
    Toggle = function() return ToggleUiVisibility() end,
    Minimize = function(v) SetMinimized(v ~= false) end,
    IsMinimized = function() return isWindowMinimized end,
    Unload = UnloadUI,
    SetStatus = function(text) footerLeft.Text = Txt(text) end,

    CreateTab = function(name, icon, order)
        CreateNavButton(name, icon, order or (#tabNames + 1))
        CreateTabContent(name)
        return tabs[name]
    end,
    CreateCategory = CreateCategoryHeader,
    CreateInfoRow = CreateInfoRow,
    CreateToggleRow = CreateToggleRow,
    CreateSliderRow = CreateSliderRow,
    CreateDropdownRow = CreateDropdownRow,
    CreateButtonRow = CreateButtonRow
}

_G.IdenticalUI = API
return API
