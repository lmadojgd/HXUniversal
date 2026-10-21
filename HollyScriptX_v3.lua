-- HollyScriptX Universal v3.0 - Liquid Glass UI (client-only)
-- LocalScript in StarterPlayer > StarterPlayerScripts
-- Tabs: MOVE / VIEW / ESP / MISC
-- Everything is local: nothing here touches the server or remotes.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ========== State ==========
local state = {
    -- movement
    walk = 16,
    jumpHeight = 7.2,
    flySpeed = 50,
    flying = false,
    noclip = false,
    infJump = false,
    up = false,
    down = false,
    -- view
    fov = 70,
    fovOn = false,
    shader = "Off",
    fullbright = false,
    noFog = false,
    clock = 14,
    clockOn = false,
    -- esp
    esp = false,
    espBox = true,
    espName = true,
    espDist = true,
    espHealth = true,
    espTeam = false, -- true = hide teammates
    espRange = 1000,
    -- misc
    blur = false,
}

-- Humanoid values are written only after the user touches the slider
local custom = { walk = false, jump = false }

local C = {
    white = Color3.new(1, 1, 1),
    tint = Color3.fromRGB(16, 22, 38),
    accent = Color3.fromRGB(120, 190, 255),
    accent2 = Color3.fromRGB(190, 140, 255),
    on = Color3.fromRGB(70, 210, 160),
    text = Color3.fromRGB(245, 248, 255),
    sub = Color3.fromRGB(165, 178, 210),
    danger = Color3.fromRGB(255, 110, 110),
}

-- ========== Connection tracking (clean unload) ==========
local connections = {}
local function bind(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

-- ========== Animation + glass helpers ==========
local function tween(inst, time, props, style, dir)
    local t = TweenService:Create(inst,
        TweenInfo.new(time, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
        props)
    t:Play()
    return t
end

local function loopTween(inst, time, props)
    TweenService:Create(inst,
        TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        props):Play()
end

local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = inst
    return c
end

local function stroke(inst, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.Color = C.white
    s.Transparency = transparency or 0.75
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

-- vertical glass sheen (more opaque on top, clearer at the bottom)
local function sheen(inst, a, b)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, a),
        NumberSequenceKeypoint.new(1, b),
    })
    g.Parent = inst
    return g
end

-- glass layer: frosted translucent fill + hairline border + sheen
local function surface(parent, radius, transparency, color)
    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(1, 1)
    f.BackgroundColor3 = color or C.white
    f.BackgroundTransparency = transparency
    f.BorderSizePixel = 0
    f:SetAttribute("Base", transparency)
    f.Parent = parent
    corner(f, radius)
    stroke(f, 0.78, 1)
    sheen(f, 0, 0.45)
    return f
end

local function makeText(parent, text, size, font, color, align)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = UDim2.fromScale(1, 1)
    l.Font = font or Enum.Font.GothamMedium
    l.TextSize = size or 13
    l.TextColor3 = color or C.text
    l.TextXAlignment = align or Enum.TextXAlignment.Center
    l.Text = text
    l.Parent = parent
    return l
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function isMove(input, active)
    if input.UserInputType == Enum.UserInputType.Touch then
        return input == active
    end
    return input.UserInputType == Enum.UserInputType.MouseMovement
end

-- press squish + hover brighten
local function pressable(btn, bg)
    local scale = Instance.new("UIScale")
    scale.Parent = btn
    btn.MouseEnter:Connect(function()
        tween(bg, 0.2, { BackgroundTransparency = math.max(bg:GetAttribute("Base") - 0.08, 0) })
    end)
    btn.MouseLeave:Connect(function()
        tween(bg, 0.3, { BackgroundTransparency = bg:GetAttribute("Base") })
    end)
    btn.InputBegan:Connect(function(input)
        if isPress(input) then
            tween(scale, 0.12, { Scale = 0.95 })
        end
    end)
    bind(UIS.InputEnded, function(input)
        if isPress(input) then
            tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
        end
    end)
end

-- ========== GUI base ==========
local gui = Instance.new("ScreenGui")
gui.Name = "HollyScriptXv3"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local espFolder = Instance.new("Folder")
espFolder.Name = "ESP"
espFolder.Parent = gui

-- Toast notifications
local toastFrame = Instance.new("CanvasGroup")
toastFrame.Size = UDim2.fromOffset(210, 36)
toastFrame.AnchorPoint = Vector2.new(0.5, 0)
toastFrame.Position = UDim2.new(0.5, 0, 0, 10)
toastFrame.BackgroundTransparency = 1
toastFrame.GroupTransparency = 1
toastFrame.ZIndex = 10
toastFrame.Parent = gui
surface(toastFrame, 18, 0.35, C.tint)
local toastLabel = makeText(toastFrame, "", 13, Enum.Font.GothamSemibold)
local toastToken = 0

local function toast(msg)
    toastToken += 1
    local mine = toastToken
    toastLabel.Text = msg
    tween(toastFrame, 0.4, { Position = UDim2.new(0.5, 0, 0, 40), GroupTransparency = 0 },
        Enum.EasingStyle.Back)
    task.delay(1.6, function()
        if mine == toastToken and toastFrame.Parent then
            tween(toastFrame, 0.3, { Position = UDim2.new(0.5, 0, 0, 10), GroupTransparency = 1 })
        end
    end)
end

-- Panel (CanvasGroup lets the whole thing fade as one piece)
local PANEL_W, PANEL_H = 300, 396

local panel = Instance.new("CanvasGroup")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.Position = UDim2.new(0, 10 + PANEL_W / 2, 0, 50 + PANEL_H / 2)
panel.BackgroundColor3 = C.tint
panel.BackgroundTransparency = 0.38
panel.BorderSizePixel = 0
panel.GroupTransparency = 1
panel.Parent = gui
corner(panel, 24)

local panelScale = Instance.new("UIScale")
panelScale.Scale = 0.88
panelScale.Parent = panel

-- Slow drifting color blobs behind the content = "liquid" feel
local function blob(size, color, transparency, from, to, time)
    local b = Instance.new("Frame")
    b.Size = UDim2.fromOffset(size, size)
    b.Position = from
    b.BackgroundColor3 = color
    b.BackgroundTransparency = transparency
    b.BorderSizePixel = 0
    b.Parent = panel
    corner(b, size)
    loopTween(b, time, { Position = to })
end
blob(230, Color3.fromRGB(80, 150, 255), 0.80, UDim2.fromOffset(-70, -50), UDim2.fromOffset(60, 110), 9)
blob(210, Color3.fromRGB(170, 100, 255), 0.84, UDim2.fromOffset(150, 250), UDim2.fromOffset(40, 150), 11)
blob(170, Color3.fromRGB(60, 220, 200), 0.88, UDim2.fromOffset(160, 40), UDim2.fromOffset(70, 290), 13)

-- Top specular highlight
do
    local hl = Instance.new("Frame")
    hl.Size = UDim2.new(1, 0, 0, 120)
    hl.BackgroundColor3 = C.white
    hl.BackgroundTransparency = 0.9
    hl.BorderSizePixel = 0
    hl.Parent = panel
    sheen(hl, 0.55, 1)
end

-- Border with a slowly rotating shimmer
do
    local border = Instance.new("Frame")
    border.Size = UDim2.fromScale(1, 1)
    border.BackgroundTransparency = 1
    border.Parent = panel
    corner(border, 24)
    local s = stroke(border, 0, 1.5)
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(0.3, 0.85),
        NumberSequenceKeypoint.new(0.7, 0.85),
        NumberSequenceKeypoint.new(1, 0.15),
    })
    g.Parent = s
    TweenService:Create(g,
        TweenInfo.new(7, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
        { Rotation = 360 }):Play()
end

-- Reopen pill (shown when the panel is collapsed)
local reopen = Instance.new("TextButton")
reopen.AnchorPoint = Vector2.new(0.5, 0.5)
reopen.Size = UDim2.fromOffset(120, 40)
reopen.BackgroundTransparency = 1
reopen.Text = ""
reopen.AutoButtonColor = false
reopen.Visible = false
reopen.Parent = gui
local reopenScale = Instance.new("UIScale")
reopenScale.Scale = 0
reopenScale.Parent = reopen
surface(reopen, 20, 0.5, C.tint)
makeText(reopen, "HOLLYSCRIPTX", 12, Enum.Font.GothamBold)

local panelOpen = true
local function setPanelOpen(open)
    panelOpen = open
    if open then
        panel.Visible = true
        tween(panelScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
        tween(panel, 0.35, { GroupTransparency = 0 })
        tween(reopenScale, 0.2, { Scale = 0 })
        task.delay(0.22, function()
            if panelOpen then reopen.Visible = false end
        end)
    else
        local p = panel.Position
        reopen.Position = UDim2.new(p.X.Scale, p.X.Offset - PANEL_W / 2 + 60,
            p.Y.Scale, p.Y.Offset - PANEL_H / 2 + 20)
        reopen.Visible = true
        tween(reopenScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
        tween(panelScale, 0.28, { Scale = 0.88 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        tween(panel, 0.28, { GroupTransparency = 1 })
        task.delay(0.3, function()
            if not panelOpen then panel.Visible = false end
        end)
    end
end
reopen.Activated:Connect(function() setPanelOpen(true) end)

-- Header: draggable area, pulsing dot, title, collapse button
local header = Instance.new("TextButton")
header.Size = UDim2.new(1, -56, 0, 44)
header.BackgroundTransparency = 1
header.Text = ""
header.AutoButtonColor = false
header.Parent = panel

do
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(8, 8)
    dot.Position = UDim2.fromOffset(18, 18)
    dot.BackgroundColor3 = C.accent
    dot.BackgroundTransparency = 0.1
    dot.BorderSizePixel = 0
    dot.Parent = header
    corner(dot, 4)
    loopTween(dot, 1.2, { BackgroundTransparency = 0.75 })

    local title = makeText(header, 'HollyScriptX  <font size="11" color="rgb(150,170,210)">liquid glass</font>',
        15, Enum.Font.GothamBold, C.text, Enum.TextXAlignment.Left)
    title.RichText = true
    title.Position = UDim2.fromOffset(34, 0)
    title.Size = UDim2.new(1, -34, 1, 0)

    local active, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if isPress(input) then
            active = input
            dragStart = input.Position
            startPos = panel.Position
        end
    end)
    bind(UIS.InputChanged, function(input)
        if active and isMove(input, active) then
            local d = input.Position - dragStart
            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    bind(UIS.InputEnded, function(input)
        if input == active then
            active = nil
        end
    end)
end

do
    local mini = Instance.new("TextButton")
    mini.Size = UDim2.fromOffset(28, 28)
    mini.AnchorPoint = Vector2.new(0.5, 0.5)
    mini.Position = UDim2.new(1, -28, 0, 22)
    mini.BackgroundTransparency = 1
    mini.Text = ""
    mini.AutoButtonColor = false
    mini.Parent = panel
    local bg = surface(mini, 14, 0.85)
    makeText(mini, "-", 18, Enum.Font.GothamBold)
    pressable(mini, bg)
    mini.Activated:Connect(function() setPanelOpen(false) end)
end

-- ========== Tabs + pages ==========
local TAB_ORDER = { "MOVE", "VIEW", "ESP", "MISC" }
local TAB_W = (PANEL_W - 20 - 8) / #TAB_ORDER
local HOLDER_POS = UDim2.fromOffset(10, 90)
local holders, pages, tabButtons = {}, {}, {}

local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.fromOffset(10, 48)
tabBar.Size = UDim2.new(1, -20, 0, 34)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel
surface(tabBar, 17, 0.9)

local pill = Instance.new("Frame")
pill.Size = UDim2.fromOffset(TAB_W, 26)
pill.Position = UDim2.fromOffset(4, 4)
pill.BackgroundColor3 = C.white
pill.BackgroundTransparency = 0.72
pill.BorderSizePixel = 0
pill.Parent = tabBar
corner(pill, 13)
stroke(pill, 0.6, 1)
sheen(pill, 0, 0.4)

for i, name in ipairs(TAB_ORDER) do
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(4 + (i - 1) * TAB_W, 4)
    b.Size = UDim2.fromOffset(TAB_W, 26)
    b.BackgroundTransparency = 1
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.TextColor3 = C.sub
    b.Text = name
    b.AutoButtonColor = false
    b.Parent = tabBar
    tabButtons[name] = b

    local holder = Instance.new("CanvasGroup")
    holder.Position = HOLDER_POS
    holder.Size = UDim2.new(1, -20, 1, -100)
    holder.BackgroundTransparency = 1
    holder.Visible = false
    holder.Parent = panel
    holders[name] = holder

    local sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.fromScale(1, 1)
    sf.BackgroundTransparency = 1
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 3
    sf.ScrollBarImageColor3 = C.accent
    sf.CanvasSize = UDim2.new()
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.Parent = holder
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 7)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = sf
    pages[name] = sf
end

local function showPage(name, instant)
    local index = 1
    for i, n in ipairs(TAB_ORDER) do
        local active = (n == name)
        if active then index = i end
        tween(tabButtons[n], 0.25, { TextColor3 = active and C.text or C.sub })
        local holder = holders[n]
        if active then
            holder.Visible = true
            if instant then
                holder.GroupTransparency = 0
                holder.Position = HOLDER_POS
            else
                holder.GroupTransparency = 1
                holder.Position = HOLDER_POS + UDim2.fromOffset(18, 0)
                tween(holder, 0.35, { GroupTransparency = 0, Position = HOLDER_POS })
            end
        else
            holder.Visible = false
        end
    end
    tween(pill, 0.45, { Position = UDim2.fromOffset(4 + (index - 1) * TAB_W, 4) },
        Enum.EasingStyle.Back)
end

for _, name in ipairs(TAB_ORDER) do
    tabButtons[name].Activated:Connect(function() showPage(name) end)
end

-- ========== Widgets ==========
local toggleRefs = {}

local function glassButton(parent, text, height, tintColor)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -6, 0, height)
    holder.BackgroundTransparency = 1
    holder.Parent = parent
    local btn = Instance.new("TextButton")
    btn.AnchorPoint = Vector2.new(0.5, 0.5)
    btn.Position = UDim2.fromScale(0.5, 0.5)
    btn.Size = UDim2.fromScale(1, 1)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = holder
    local bg = surface(btn, 14, 0.88, tintColor)
    local lbl = makeText(btn, text)
    pressable(btn, bg)
    return btn, lbl, bg
end

local function createToggle(page, labelText, key, onChange)
    local btn, lbl, bg = glassButton(page, labelText, 40)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Position = UDim2.fromOffset(16, 0)
    lbl.Size = UDim2.new(1, -80, 1, 0)

    local pillSwitch = Instance.new("Frame")
    pillSwitch.AnchorPoint = Vector2.new(1, 0.5)
    pillSwitch.Position = UDim2.new(1, -12, 0.5, 0)
    pillSwitch.Size = UDim2.fromOffset(42, 22)
    pillSwitch.BorderSizePixel = 0
    pillSwitch.Parent = btn
    corner(pillSwitch, 11)
    stroke(pillSwitch, 0.7, 1)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.fromOffset(18, 18)
    knob.BackgroundColor3 = C.white
    knob.BorderSizePixel = 0
    knob.Parent = pillSwitch
    corner(knob, 9)

    local function paint(animate)
        local on = state[key]
        local t = animate and 0.3 or 0
        tween(pillSwitch, t, {
            BackgroundColor3 = on and C.on or C.white,
            BackgroundTransparency = on and 0.15 or 0.8,
        })
        tween(knob, t, { Position = on and UDim2.new(1, -11, 0.5, 0) or UDim2.new(0, 11, 0.5, 0) },
            Enum.EasingStyle.Back)
        local base = on and 0.78 or 0.88
        bg:SetAttribute("Base", base)
        tween(bg, t, {
            BackgroundColor3 = on and C.on or C.white,
            BackgroundTransparency = base,
        })
        tween(lbl, t, { TextColor3 = on and C.text or C.sub })
    end

    toggleRefs[key] = function() paint(true) end
    btn.Activated:Connect(function()
        state[key] = not state[key]
        paint(true)
        toast(labelText .. (state[key] and "  ON" or "  OFF"))
        if onChange then onChange(state[key]) end
    end)
    paint(false)
    return btn
end

local function createSlider(page, title, min, max, default, step, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -6, 0, 58)
    row.BackgroundTransparency = 1
    row.Parent = page
    surface(row, 14, 0.88)

    local titleLabel = makeText(row, title, 13, Enum.Font.GothamMedium, C.sub, Enum.TextXAlignment.Left)
    titleLabel.Position = UDim2.fromOffset(16, 6)
    titleLabel.Size = UDim2.new(0.6, 0, 0, 20)

    local valueLabel = makeText(row, "", 13, Enum.Font.GothamBold, C.accent, Enum.TextXAlignment.Right)
    valueLabel.Position = UDim2.new(0.6, 0, 0, 6)
    valueLabel.Size = UDim2.new(0.4, -16, 0, 20)

    local hit = Instance.new("TextButton")
    hit.Position = UDim2.fromOffset(0, 26)
    hit.Size = UDim2.new(1, 0, 1, -26)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.AutoButtonColor = false
    hit.Parent = row

    local track = Instance.new("Frame")
    track.Position = UDim2.new(0, 26, 0.5, -3)
    track.Size = UDim2.new(1, -52, 0, 6)
    track.BackgroundColor3 = C.white
    track.BackgroundTransparency = 0.8
    track.BorderSizePixel = 0
    track.Parent = hit
    corner(track, 3)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = C.white
    fill.BorderSizePixel = 0
    fill.Parent = track
    corner(fill, 3)
    local fg = Instance.new("UIGradient")
    fg.Color = ColorSequence.new(C.accent, C.accent2)
    fg.Parent = fill

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(20, 20)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.BackgroundColor3 = C.white
    knob.BorderSizePixel = 0
    knob.Parent = track
    corner(knob, 10)
    stroke(knob, 0.5, 1.5).Color = C.accent

    local function set(value, byUser)
        value = math.clamp(math.floor(value / step + 0.5) * step, min, max)
        value = tonumber(string.format("%.2f", value))
        local alpha = (value - min) / (max - min)
        valueLabel.Text = tostring(value)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        onChange(value, byUser)
    end

    local function fromX(x)
        local alpha = math.clamp(
            (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        set(min + alpha * (max - min), true)
    end

    local active
    hit.InputBegan:Connect(function(input)
        if isPress(input) then
            active = input
            page.ScrollingEnabled = false -- don't scroll the page while dragging
            tween(knob, 0.2, { Size = UDim2.fromOffset(27, 27) }, Enum.EasingStyle.Back)
            fromX(input.Position.X)
        end
    end)
    bind(UIS.InputChanged, function(input)
        if active and isMove(input, active) then
            fromX(input.Position.X)
        end
    end)
    bind(UIS.InputEnded, function(input)
        if input == active then
            active = nil
            page.ScrollingEnabled = true
            tween(knob, 0.3, { Size = UDim2.fromOffset(20, 20) }, Enum.EasingStyle.Back)
        end
    end)

    set(default, false)
    return set
end

local function createHeader(page, text)
    local l = makeText(page, text, 11, Enum.Font.GothamBold, C.accent, Enum.TextXAlignment.Left)
    l.Size = UDim2.new(1, -6, 0, 18)
    l.Position = UDim2.fromOffset(6, 0)
end

-- ========== Character helpers ==========
local function getHumanoid()
    local c = player.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local humDefaults = nil

local function applyHumanoid()
    local hum = getHumanoid()
    if not hum then return end
    if custom.walk then
        hum.WalkSpeed = state.walk
    end
    if custom.jump then
        hum.UseJumpPower = false -- otherwise JumpHeight is ignored
        hum.JumpHeight = state.jumpHeight
    end
end

-- ========== Fly buttons (glass circles with pop animation) ==========
local flyShown = false

local function makeFlyButton(text, pos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(64, 64)
    btn.AnchorPoint = Vector2.new(1, 0)
    btn.Position = pos
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Visible = false
    btn.Parent = gui
    local sc = Instance.new("UIScale")
    sc.Scale = 0
    sc.Parent = btn
    surface(btn, 32, 0.55, C.tint)
    makeText(btn, text, 13, Enum.Font.GothamBold)
    return btn, sc
end

local upButton, upScale = makeFlyButton("UP", UDim2.new(1, -20, 0.5, -76))
local downButton, downScale = makeFlyButton("DOWN", UDim2.new(1, -20, 0.5, 4))

local function holdButton(button, scale, key)
    local active
    button.InputBegan:Connect(function(input)
        if isPress(input) then
            active = input
            state[key] = true
            tween(scale, 0.12, { Scale = 0.9 })
        end
    end)
    -- global release: finger sliding off the button still releases it
    bind(UIS.InputEnded, function(input)
        if input == active then
            active = nil
            state[key] = false
            if flyShown then
                tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
            end
        end
    end)
end
holdButton(upButton, upScale, "up")
holdButton(downButton, downScale, "down")

local function showFlyButtons(show)
    flyShown = show
    for _, pair in ipairs({ { upButton, upScale }, { downButton, downScale } }) do
        local btn, sc = pair[1], pair[2]
        if show then
            btn.Visible = true
            tween(sc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
        else
            tween(sc, 0.25, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            task.delay(0.27, function()
                if not flyShown then btn.Visible = false end
            end)
        end
    end
end

local function setFly(enabled)
    state.flying = enabled
    local hum, root = getHumanoid(), getRoot()
    if hum then
        hum.PlatformStand = enabled
        if not enabled and hum.Health > 0 then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end
    if not enabled then
        state.up = false
        state.down = false
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
        end
    end
    showFlyButtons(enabled)
    if toggleRefs.flying then toggleRefs.flying() end
end

-- ========== Noclip ==========
local partList = {}
local noclipTouched = setmetatable({}, { __mode = "k" })
local charConns = {}

local function trackCharacter(character)
    for _, c in ipairs(charConns) do c:Disconnect() end
    table.clear(charConns)
    partList = {}
    table.clear(noclipTouched)
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(partList, d) end
    end
    table.insert(charConns, character.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then table.insert(partList, d) end
    end))
end

local function restoreNoclip()
    for part in pairs(noclipTouched) do
        if part.Parent then part.CanCollide = true end
    end
    table.clear(noclipTouched)
end

bind(RunService.Stepped, function()
    if state.noclip then
        for _, part in ipairs(partList) do
            if part.Parent and part.CanCollide then
                noclipTouched[part] = true
                part.CanCollide = false
            end
        end
    elseif next(noclipTouched) ~= nil then
        restoreNoclip()
    end
end)

-- Infinite jump
bind(UIS.JumpRequest, function()
    if not state.infJump then return end
    local hum = getHumanoid()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

-- ========== Lighting overrides (fullbright / no fog / time lock) ==========
local overrides = {}     -- feature -> { Property = value }
local origLighting = {}  -- Property -> original value

local function setOverride(feature, props)
    if props then
        for prop in pairs(props) do
            if origLighting[prop] == nil then
                origLighting[prop] = Lighting[prop]
            end
        end
        overrides[feature] = props
    else
        overrides[feature] = nil
        for prop, orig in pairs(origLighting) do
            local still = false
            for _, p in pairs(overrides) do
                if p[prop] ~= nil then still = true break end
            end
            if not still then
                Lighting[prop] = orig
                origLighting[prop] = nil
            end
        end
    end
end

local function enforceLighting()
    for _, props in pairs(overrides) do
        for prop, value in pairs(props) do
            if Lighting[prop] ~= value then
                Lighting[prop] = value
            end
        end
    end
end

local function updateFullbright()
    if state.fullbright then
        setOverride("fullbright", {
            Brightness = 2,
            GlobalShadows = false,
            Ambient = Color3.fromRGB(178, 178, 178),
            OutdoorAmbient = Color3.fromRGB(178, 178, 178),
        })
    else
        setOverride("fullbright", nil)
    end
end

local function updateNoFog()
    if state.noFog then
        setOverride("nofog", { FogEnd = 1e6, FogStart = 1e6 - 1 })
    else
        setOverride("nofog", nil)
    end
end

local function updateClock()
    if state.clockOn then
        setOverride("clock", { ClockTime = state.clock })
    else
        setOverride("clock", nil)
    end
end

-- ========== Shaders (post-processing presets) ==========
local PRESETS = {
    Vivid = {
        { "ColorCorrectionEffect", { Saturation = 0.35, Contrast = 0.15, Brightness = 0.02,
            TintColor = Color3.fromRGB(255, 248, 240) } },
        { "BloomEffect", { Intensity = 0.5, Size = 30, Threshold = 1 } },
        { "SunRaysEffect", { Intensity = 0.15, Spread = 0.8 } },
    },
    Cinematic = {
        { "ColorCorrectionEffect", { Saturation = -0.1, Contrast = 0.25, Brightness = -0.03,
            TintColor = Color3.fromRGB(255, 235, 215) } },
        { "BloomEffect", { Intensity = 0.35, Size = 40, Threshold = 0.9 } },
        { "DepthOfFieldEffect", { FarIntensity = 0.2, FocusDistance = 70,
            InFocusRadius = 50, NearIntensity = 0 } },
    },
    Sunset = {
        { "ColorCorrectionEffect", { Saturation = 0.25, Contrast = 0.1, Brightness = 0,
            TintColor = Color3.fromRGB(255, 200, 160) } },
        { "BloomEffect", { Intensity = 0.6, Size = 36, Threshold = 0.8 } },
        { "SunRaysEffect", { Intensity = 0.25, Spread = 0.9 } },
    },
    Night = {
        { "ColorCorrectionEffect", { Saturation = -0.15, Contrast = 0.1, Brightness = -0.08,
            TintColor = Color3.fromRGB(150, 175, 255) } },
        { "BloomEffect", { Intensity = 0.4, Size = 30, Threshold = 1 } },
    },
    Retro = {
        { "ColorCorrectionEffect", { Saturation = -0.55, Contrast = 0.3, Brightness = 0,
            TintColor = Color3.fromRGB(235, 225, 185) } },
        { "BloomEffect", { Intensity = 0.2, Size = 20, Threshold = 1 } },
    },
}
local SHADER_ORDER = { "Off", "Vivid", "Cinematic", "Sunset", "Night", "Retro" }

local function clearShaders()
    for _, child in ipairs(Lighting:GetChildren()) do
        if child.Name:sub(1, 4) == "HSX_" then child:Destroy() end
    end
end

local function applyShader(name)
    clearShaders()
    local preset = PRESETS[name]
    if not preset then return end
    for _, def in ipairs(preset) do
        local inst = Instance.new(def[1])
        inst.Name = "HSX_" .. def[1]
        for prop, value in pairs(def[2]) do
            pcall(function() inst[prop] = value end)
        end
        inst.Parent = Lighting
    end
end

-- World blur (optional; the 3D scene only, UI stays sharp)
local blurEffect = nil
local function updateBlur()
    if state.blur then
        if not blurEffect then
            blurEffect = Instance.new("BlurEffect")
            blurEffect.Name = "HSXGlassBlur"
            blurEffect.Size = 0
            blurEffect.Parent = Lighting
        end
        tween(blurEffect, 0.6, { Size = 14 })
    elseif blurEffect then
        local b = blurEffect
        blurEffect = nil
        tween(b, 0.4, { Size = 0 }).Completed:Connect(function() b:Destroy() end)
    end
end

-- ========== FOV ==========
local originalFov = nil

RunService:BindToRenderStep("HSX_FOV", Enum.RenderPriority.Camera.Value + 1, function()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    if state.fovOn then
        if originalFov == nil then originalFov = camera.FieldOfView end
        if camera.FieldOfView ~= state.fov then
            camera.FieldOfView = state.fov
        end
    elseif originalFov ~= nil then
        camera.FieldOfView = originalFov
        originalFov = nil
    end
end)

-- ========== ESP ==========
local espObjects = {}

local function removeEsp(plr)
    local o = espObjects[plr]
    if o then
        o.highlight:Destroy()
        o.billboard:Destroy()
        espObjects[plr] = nil
    end
end

local function createEsp(plr, character)
    local highlight = Instance.new("Highlight")
    highlight.Name = "HSX_" .. plr.Name
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.75
    highlight.OutlineTransparency = 0
    highlight.Adornee = character
    highlight.Parent = espFolder

    local bb = Instance.new("BillboardGui")
    bb.Name = "HSX_" .. plr.Name .. "_Info"
    bb.Size = UDim2.fromOffset(170, 40)
    bb.StudsOffset = Vector3.new(0, 3.2, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Adornee = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    bb.Parent = espFolder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 13
    label.TextColor3 = C.text
    label.TextStrokeTransparency = 0.4
    label.Parent = bb

    espObjects[plr] = { character = character, highlight = highlight,
        billboard = bb, label = label }
end

local function updateEsp()
    if not state.esp then
        for plr in pairs(espObjects) do removeEsp(plr) end
        return
    end
    local camera = Workspace.CurrentCamera
    if not camera then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then
            local character = plr.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local hum = character and character:FindFirstChildOfClass("Humanoid")
            local skip = not (root and hum) or hum.Health <= 0

            if not skip and state.espTeam and plr.Team ~= nil and plr.Team == player.Team then
                skip = true
            end

            local dist = 0
            if not skip then
                dist = (root.Position - camera.CFrame.Position).Magnitude
                if dist > state.espRange then skip = true end
            end

            if skip then
                removeEsp(plr)
            else
                local o = espObjects[plr]
                if o and o.character ~= character then
                    removeEsp(plr)
                    o = nil
                end
                if not o then
                    createEsp(plr, character)
                    o = espObjects[plr]
                end

                local color = plr.Team and plr.TeamColor.Color or Color3.fromRGB(255, 80, 80)
                o.highlight.Enabled = state.espBox
                o.highlight.FillColor = color
                o.highlight.OutlineColor = color

                local lines = {}
                if state.espName then
                    table.insert(lines, plr.DisplayName)
                end
                local info = {}
                if state.espDist then
                    table.insert(info, math.floor(dist) .. " studs")
                end
                if state.espHealth then
                    table.insert(info, "HP " .. math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth))
                end
                if #info > 0 then
                    table.insert(lines, table.concat(info, "  |  "))
                end
                o.label.Text = table.concat(lines, "\n")
                o.billboard.Enabled = #lines > 0
            end
        end
    end
end

bind(Players.PlayerRemoving, removeEsp)

-- ========== Main loop ==========
local espTimer = 0

bind(RunService.Heartbeat, function(dt)
    dt = math.min(dt, 0.1)

    if next(overrides) ~= nil then
        enforceLighting()
    end

    espTimer += dt
    if espTimer >= 0.15 then
        espTimer = 0
        updateEsp()
    end

    if not state.flying then return end
    local character = player.Character
    local hum = getHumanoid()
    local root = getRoot()
    if not character or not hum or not root or hum.Health <= 0 then return end

    if not hum.PlatformStand then hum.PlatformStand = true end

    local camera = Workspace.CurrentCamera
    local dir = hum.MoveDirection
    local vertical = 0
    if dir.Magnitude > 0 and camera then
        vertical = camera.CFrame.LookVector.Y
    end
    if state.up then
        vertical = 1
    elseif state.down then
        vertical = -1
    end

    if dir.Magnitude == 0 and not state.up and not state.down then
        root.AssemblyLinearVelocity = Vector3.zero -- hover
        return
    end

    root.AssemblyLinearVelocity = Vector3.new(
        dir.X * state.flySpeed,
        vertical * state.flySpeed,
        dir.Z * state.flySpeed)
end)

-- ========== Unload ==========
local function unload()
    for _, c in ipairs(connections) do c:Disconnect() end
    table.clear(connections)
    for _, c in ipairs(charConns) do c:Disconnect() end
    table.clear(charConns)
    pcall(function() RunService:UnbindFromRenderStep("HSX_FOV") end)

    -- restore everything we touched
    state.noclip = false
    restoreNoclip()
    if state.flying then setFly(false) end
    for plr in pairs(espObjects) do removeEsp(plr) end
    for feature in pairs(overrides) do setOverride(feature, nil) end
    clearShaders()
    if blurEffect then blurEffect:Destroy() blurEffect = nil end

    local camera = Workspace.CurrentCamera
    if camera and originalFov ~= nil then
        camera.FieldOfView = originalFov
    end

    local hum = getHumanoid()
    if hum and humDefaults then
        hum.WalkSpeed = humDefaults.walk
        hum.UseJumpPower = humDefaults.useJump
        hum.JumpHeight = humDefaults.jump
    end

    gui:Destroy()
end

-- ========== Page: MOVE ==========
do
    local page = pages.MOVE
    createHeader(page, "CHARACTER")
    createSlider(page, "Walk speed", 1, 300, state.walk, 1, function(v, byUser)
        state.walk = v
        if byUser then custom.walk = true applyHumanoid() end
    end)
    createSlider(page, "Jump height", 1, 50, state.jumpHeight, 0.1, function(v, byUser)
        state.jumpHeight = v
        if byUser then custom.jump = true applyHumanoid() end
    end)
    createHeader(page, "FLIGHT")
    createSlider(page, "Fly speed", 1, 500, state.flySpeed, 1, function(v)
        state.flySpeed = v
    end)
    createToggle(page, "FLY", "flying", function(v) setFly(v) end)
    createToggle(page, "NOCLIP", "noclip")
    createToggle(page, "INFINITE JUMP", "infJump")
end

-- ========== Page: VIEW ==========
do
    local page = pages.VIEW
    createHeader(page, "CAMERA")
    createSlider(page, "FOV", 30, 120, state.fov, 1, function(v) state.fov = v end)
    createToggle(page, "FOV OVERRIDE", "fovOn")

    createHeader(page, "SHADERS")
    local shaderIndex = 1
    local shaderButton, shaderLabel, shaderBg = glassButton(page, "SHADER: Off", 40)
    shaderButton.Activated:Connect(function()
        shaderIndex = shaderIndex % #SHADER_ORDER + 1
        state.shader = SHADER_ORDER[shaderIndex]
        applyShader(state.shader)
        shaderLabel.Text = "SHADER: " .. state.shader
        local on = state.shader ~= "Off"
        local base = on and 0.75 or 0.88
        shaderBg:SetAttribute("Base", base)
        tween(shaderBg, 0.35, {
            BackgroundColor3 = on and C.accent or C.white,
            BackgroundTransparency = base,
        })
        toast("Shader: " .. state.shader)
    end)

    createToggle(page, "FULLBRIGHT", "fullbright", updateFullbright)
    createToggle(page, "NO FOG", "noFog", updateNoFog)

    createHeader(page, "TIME")
    createSlider(page, "Time of day", 0, 24, state.clock, 0.5, function(v)
        state.clock = v
        if state.clockOn then updateClock() end
    end)
    createToggle(page, "TIME LOCK", "clockOn", updateClock)
end

-- ========== Page: ESP ==========
do
    local page = pages.ESP
    createToggle(page, "ESP", "esp", function(v)
        if not v then updateEsp() end
    end)
    createHeader(page, "OPTIONS")
    createToggle(page, "HIGHLIGHT", "espBox")
    createToggle(page, "NAMES", "espName")
    createToggle(page, "DISTANCE", "espDist")
    createToggle(page, "HEALTH", "espHealth")
    createToggle(page, "HIDE TEAMMATES", "espTeam")
    createSlider(page, "Max distance", 50, 3000, state.espRange, 50, function(v)
        state.espRange = v
    end)
end

-- ========== Page: MISC ==========
do
    local page = pages.MISC
    createHeader(page, "INTERFACE")
    createSlider(page, "Glass opacity", 0.15, 0.8, 0.38, 0.01, function(v)
        panel.BackgroundTransparency = v
    end)
    createToggle(page, "WORLD BLUR", "blur", updateBlur)

    createHeader(page, "PANEL")
    local collapse = glassButton(page, "Collapse panel", 40)
    collapse.Activated:Connect(function() setPanelOpen(false) end)

    local unloadButton, _, unloadBg = glassButton(page, "UNLOAD (restore everything)", 40, C.danger)
    unloadBg:SetAttribute("Base", 0.8)
    unloadBg.BackgroundTransparency = 0.8
    unloadButton.Activated:Connect(unload)
end

-- ========== Character lifecycle ==========
local function onCharacter(character)
    trackCharacter(character)
    state.up = false
    state.down = false
    if state.flying then
        state.flying = false
        if toggleRefs.flying then toggleRefs.flying() end
    end
    showFlyButtons(false)

    task.spawn(function()
        local hum = character:WaitForChild("Humanoid", 10)
        if not hum or player.Character ~= character then return end
        humDefaults = {
            walk = hum.WalkSpeed,
            useJump = hum.UseJumpPower,
            jump = hum.JumpHeight,
        }
        applyHumanoid()
    end)
end

bind(player.CharacterAdded, onCharacter)
if player.Character then
    onCharacter(player.Character)
end

showPage("MOVE", true)
setPanelOpen(true)
