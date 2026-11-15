--[[
    Dealer -> Deliver -> Buyer loop  |  Solara
    RightShift = open/close menu.
    Dealer: "Mystery Dealer" / DealerPrompt.  Buyer: "Delivery Recipient".
    Sequence: E -> adjustable delay -> 1  |  delivery: E
    After each delivery: confirm slot 1 is equipped, hold LMB, release, press 1.
    Cycle repeats every 45.5s (measured from cycle start).
]]

if getgenv().DQL_Unload then pcall(getgenv().DQL_Unload) end

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local VIM        = game:GetService("VirtualInputManager")
local HS         = game:GetService("HttpService")
local LP = Players.LocalPlayer

local CONFIG = {
    DealerPos  = nil,
    BuyerPos   = nil,
    Cycle      = 45.5,
    MenuDelay  = 1.00,
    AcceptWait = 2.0,
    DeliverWait= 1.5,
    Taps       = 3,
    Hold       = 0.12,
    LmbHold    = 5.3,
    Radius     = 14,
    AutoLoad   = false,
    DealerName      = "Mystery Dealer",
    BuyerName       = "Delivery Recipient",
    DealerPrompt    = "DealerPrompt",
    NpcPatterns     = { "mystery dealer", "dealer", "package", "delivery", "courier" },
    BuyerPatterns   = { "delivery recipient", "recipient", "customer", "buyer", "client", "drop" },
    PackagePatterns = { "package", "parcel", "delivery", "box", "mail", "crate" },
}

local FILE = "DQL_config.json"
local running, menuOpen = false, false
local camConn

------------------------------------------------------------------ storage
local function encodeCfg()
    local d = {}
    for k, v in pairs(CONFIG) do
        if type(v) ~= "table" then
            d[k] = typeof(v) == "Vector3" and { v.X, v.Y, v.Z } or v
        end
    end
    return HS:JSONEncode(d)
end

local function applyCfg(data)
    for k, v in pairs(data) do
        if CONFIG[k] ~= nil and k ~= "AutoLoad" then
            if type(v) == "table" and #v == 3 then
                CONFIG[k] = Vector3.new(v[1], v[2], v[3])
            elseif type(v) ~= "table" then
                CONFIG[k] = v
            end
        end
    end
end

local function saveCfg()
    local ok, json = pcall(encodeCfg)
    if not ok then return nil end
    if writefile then pcall(writefile, FILE, json) end
    return json
end

local function readCfgFile()
    if not (isfile and readfile and isfile(FILE)) then return nil end
    local ok, data = pcall(function() return HS:JSONDecode(readfile(FILE)) end)
    if ok and type(data) == "table" then return data end
    return nil
end

do
    local startup = readCfgFile()
    if startup then
        CONFIG.AutoLoad = startup.AutoLoad == true
        if CONFIG.AutoLoad then applyCfg(startup) end
    end
end

------------------------------------------------------------------ helpers
local function getRoot()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function matchAny(str, pats)
    str = string.lower(tostring(str or ""))
    for _, p in ipairs(pats) do
        if string.find(str, string.lower(p), 1, true) then return true end
    end
    return false
end

local function sameName(a, b)
    return string.lower(tostring(a or "")) == string.lower(tostring(b or ""))
end

local function teleportTo(pos)
    local hrp = getRoot()
    if not hrp then return false end
    hrp.Anchored = true
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0))
    task.wait(0.12)
    hrp.Anchored = false
    hrp.AssemblyLinearVelocity = Vector3.zero
    return true
end

-- includes disabled prompts, since the dealer prompt may be gated by range
local function promptsNear(pos, radius)
    local out = {}
    for _, o in ipairs(Workspace:GetDescendants()) do
        local isP = o:IsA("ProximityPrompt") or o:IsA("ClickDetector")
        if isP and o.Parent then
            local d = (o.Parent:GetPivot().Position - pos).Magnitude
            if d <= radius then table.insert(out, { obj = o, d = d }) end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

local function nativeFire(p)
    if p:IsA("ProximityPrompt") and fireproximityprompt then
        pcall(fireproximityprompt, p)
    elseif p:IsA("ClickDetector") and fireclickdetector then
        pcall(fireclickdetector, p)
    end
end

-- pick the prompt belonging to the target, falling back to the closest
local function promptFor(targetName, pos)
    local hits = promptsNear(pos, CONFIG.Radius)
    for _, h in ipairs(hits) do
        if h.obj.Parent and sameName(h.obj.Parent.Name, targetName) then return h.obj end
    end
    for _, h in ipairs(hits) do
        if sameName(h.obj.Name, CONFIG.DealerPrompt) then return h.obj end
    end
    return hits[1] and hits[1].obj or nil
end

------------------------------------------------------------------ input
local function keyDown(code, str)
    if keypress then pcall(keypress, str) end
    pcall(function() VIM:SendKeyEvent(true, code, false, game) end)
end

local function keyUp(code, str)
    if keyrelease then pcall(keyrelease, str) end
    pcall(function() VIM:SendKeyEvent(false, code, false, game) end)
end

local function pressE(hold)
    keyDown(Enum.KeyCode.E, "e")
    task.wait(hold or CONFIG.Hold)
    keyUp(Enum.KeyCode.E, "e")
end

local function pressOne(hold)
    keyDown(Enum.KeyCode.One, "1")
    task.wait(hold or 0.1)
    keyUp(Enum.KeyCode.One, "1")
end

local function lmbDown()
    if mouse1press then pcall(mouse1press) end
    pcall(function() VIM:SendMouseButtonEvent(0, 0, 1, true, 1, game) end)
end

local function lmbUp()
    if mouse1release then pcall(mouse1release) end
    pcall(function() VIM:SendMouseButtonEvent(0, 0, 1, false, 1, game) end)
end

local function equippedTool()
    local c = LP.Character
    if not c then return nil end
    return c:FindFirstChildOfClass("Tool")
end

local function hasPackage()
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and matchAny(t.Name, CONFIG.PackagePatterns) then return true end
        end
    end
    local char = LP.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and matchAny(t.Name, CONFIG.PackagePatterns) then return true end
        end
    end
    return false
end

local function waitFor(fn, timeout)
    local t = 0
    while t < timeout do
        if fn() then return true end
        task.wait(0.12)
        t = t + 0.12
    end
    return false
end

------------------------------------------------------------------ gui
local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local gui = new("ScreenGui", {
    Name = "DQL_Menu", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = true,
}, LP:WaitForChild("PlayerGui"))

local hint = new("TextLabel", {
    Size = UDim2.fromOffset(148, 22), Position = UDim2.new(0.5, -74, 0, 8),
    BackgroundColor3 = Color3.fromRGB(22, 24, 30), BackgroundTransparency = 0.15,
    Text = "RightShift — Menu", Font = Enum.Font.GothamSemibold, TextSize = 11,
    TextColor3 = Color3.fromRGB(190, 196, 208), BorderSizePixel = 0,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 11) }, hint)

local main = new("Frame", {
    Size = UDim2.fromOffset(300, 478), Position = UDim2.fromOffset(50, 50),
    BackgroundColor3 = Color3.fromRGB(22, 24, 30), BorderSizePixel = 0,
    Active = true, ClipsDescendants = false,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, main)
new("UIStroke", { Color = Color3.fromRGB(58, 62, 74), Thickness = 1 }, main)

local title = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(30, 33, 41),
    Text = "  Dealer / Buyer Loop", TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Color3.fromRGB(235, 238, 245), Font = Enum.Font.GothamBold,
    TextSize = 13, BorderSizePixel = 0,
}, main)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, title)

local dragging, dragStart, startPos
title.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = i.Position; startPos = main.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        main.Position = UDim2.fromOffset(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

local function tab(text, x)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(80, 26), Position = UDim2.fromOffset(x, 36),
        BackgroundColor3 = Color3.fromRGB(38, 42, 51), Text = text,
        TextColor3 = Color3.fromRGB(190, 196, 208), Font = Enum.Font.GothamSemibold,
        TextSize = 11, BorderSizePixel = 0,
    }, main)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    return b
end

local mainTabBtn = tab("Main", 8)
local cfgTabBtn  = tab("Config", 92)

local mainTab = new("Frame", {
    Size = UDim2.new(1, -16, 0, 396), Position = UDim2.fromOffset(8, 68),
    BackgroundTransparency = 1,
}, main)

local cfgTab = new("Frame", {
    Size = UDim2.new(1, -16, 0, 396), Position = UDim2.fromOffset(8, 68),
    BackgroundTransparency = 1, Visible = false,
}, main)

local function selectTab(which)
    local onMain = which == "main"
    mainTab.Visible = onMain
    cfgTab.Visible = not onMain
    mainTabBtn.BackgroundColor3 = onMain and Color3.fromRGB(48, 84, 140) or Color3.fromRGB(38, 42, 51)
    cfgTabBtn.BackgroundColor3 = onMain and Color3.fromRGB(38, 42, 51) or Color3.fromRGB(48, 84, 140)
end
mainTabBtn.MouseButton1Click:Connect(function() selectTab("main") end)
cfgTabBtn.MouseButton1Click:Connect(function() selectTab("cfg") end)

local status = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 0),
    BackgroundTransparency = 1, TextWrapped = true, TextSize = 11,
    Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(150, 156, 168),
    Text = "Set both positions, then press START", TextXAlignment = Enum.TextXAlignment.Left,
}, mainTab)

local function setStatus(t, col)
    status.Text = t
    status.TextColor3 = col or Color3.fromRGB(150, 156, 168)
end

local function btn(parent, text, y, color, w, x, size)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(w or 268, 26), Position = UDim2.fromOffset(x or 0, y),
        BackgroundColor3 = color, Text = text, TextColor3 = Color3.fromRGB(240, 242, 248),
        Font = Enum.Font.GothamSemibold, TextSize = size or 11, BorderSizePixel = 0,
    }, parent)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    return b
end

local dealerBtn = btn(mainTab, "Set Dealer", 52, Color3.fromRGB(48, 84, 140))
dealerBtn.Size = UDim2.new(1, 0, 0, 30)
local buyerBtn = btn(mainTab, "Set Buyer", 88, Color3.fromRGB(48, 84, 140))
buyerBtn.Size = UDim2.new(1, 0, 0, 30)

local findDealerBtn = btn(mainTab, "Find Dealer", 124, Color3.fromRGB(52, 58, 70), 138, 0)
local findBuyerBtn  = btn(mainTab, "Find Buyer", 124, Color3.fromRGB(52, 58, 70), 138, 146)
local tapBtn        = btn(mainTab, "Test E+1", 154, Color3.fromRGB(60, 72, 96), 138, 0)
local clearBtn      = btn(mainTab, "Clear", 154, Color3.fromRGB(70, 52, 52), 138, 146)

local coordLabel = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 184),
    BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 10,
    TextColor3 = Color3.fromRGB(120, 128, 142), TextXAlignment = Enum.TextXAlignment.Left,
    Text = "dealer: -, -    buyer: -, -",
}, mainTab)

local function refreshCoords()
    local function f(v) return v and string.format("%d, %d", v.X, v.Z) or "-, -" end
    coordLabel.Text = "dealer: " .. f(CONFIG.DealerPos) .. "    buyer: " .. f(CONFIG.BuyerPos)
end
refreshCoords()

new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 206),
    BackgroundTransparency = 1, Text = "ONLY CHANGE WHEN YOU KNOW WHAT YOU ARE DOING",
    Font = Enum.Font.GothamBold, TextSize = 9, TextWrapped = true,
    TextColor3 = Color3.fromRGB(214, 168, 84), TextXAlignment = Enum.TextXAlignment.Left,
}, mainTab)

local function field(parent, label, y, get, set, min, max)
    new("TextLabel", {
        Size = UDim2.fromOffset(110, 18), Position = UDim2.fromOffset(0, y),
        BackgroundTransparency = 1, Text = label, Font = Enum.Font.Gotham,
        TextSize = 11, TextColor3 = Color3.fromRGB(160, 166, 178),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
    local box = new("TextBox", {
        Size = UDim2.fromOffset(58, 20), Position = UDim2.fromOffset(226, y - 1),
        BackgroundColor3 = Color3.fromRGB(34, 37, 45), Text = tostring(get()),
        TextColor3 = Color3.fromRGB(230, 234, 240), Font = Enum.Font.Code, TextSize = 12,
        BorderSizePixel = 0, ClearTextOnFocus = false,
    }, parent)
    new("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then set(math.clamp(n, min, max)) end
        box.Text = tostring(get())
        saveCfg()
    end)
    return box
end

local function slider(parent, label, y, get, set, min, max)
    new("TextLabel", {
        Size = UDim2.fromOffset(110, 18), Position = UDim2.fromOffset(0, y),
        BackgroundTransparency = 1, Text = label, Font = Enum.Font.Gotham,
        TextSize = 11, TextColor3 = Color3.fromRGB(160, 166, 178),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)

    local track = new("Frame", {
        Size = UDim2.fromOffset(130, 6), Position = UDim2.fromOffset(88, y + 6),
        BackgroundColor3 = Color3.fromRGB(44, 48, 58), BorderSizePixel = 0,
    }, parent)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(70, 130, 200),
        BorderSizePixel = 0,
    }, track)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(12, 16), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Color3.fromRGB(225, 230, 240),
        BorderSizePixel = 0, ZIndex = 2,
    }, track)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

    local box = new("TextBox", {
        Size = UDim2.fromOffset(58, 20), Position = UDim2.fromOffset(226, y - 1),
        BackgroundColor3 = Color3.fromRGB(34, 37, 45), Text = string.format("%.2f", get()),
        TextColor3 = Color3.fromRGB(230, 234, 240), Font = Enum.Font.Code, TextSize = 11,
        BorderSizePixel = 0, ClearTextOnFocus = false,
    }, parent)
    new("UICorner", { CornerRadius = UDim.new(0, 4) }, box)

    local function refresh()
        local a = math.clamp((get() - min) / (max - min), 0, 1)
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
        box.Text = string.format("%.2f", get())
    end

    local sliding = false
    local function fromX(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        set(min + rel * (max - min))
        refresh()
    end

    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = true; fromX(i.Position.X) end
    end)
    knob.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = true; fromX(i.Position.X) end
    end)
    UIS.InputChanged:Connect(function(i)
        if sliding and i.UserInputType == Enum.UserInputType.MouseMovement then fromX(i.Position.X) end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 and sliding then
            sliding = false
            saveCfg()
        end
    end)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then set(math.clamp(n, min, max)) end
        refresh()
        saveCfg()
    end)

    refresh()
    return refresh
end

local cycleBox = field(mainTab, "Cycle (s)", 224, function() return CONFIG.Cycle end,
    function(v) CONFIG.Cycle = v end, 5, 300)
local menuSlider = slider(mainTab, "E to 1 delay", 248, function() return CONFIG.MenuDelay end,
    function(v) CONFIG.MenuDelay = v end, 0.1, 1.0)
local tapsBox  = field(mainTab, "E taps", 276, function() return CONFIG.Taps end,
    function(v) CONFIG.Taps = math.floor(v) end, 1, 10)
local holdBox  = field(mainTab, "Hold (s)", 300, function() return CONFIG.Hold end,
    function(v) CONFIG.Hold = v end, 0.05, 1)
local lmbBox   = field(mainTab, "LMB hold (s)", 324, function() return CONFIG.LmbHold end,
    function(v) CONFIG.LmbHold = v end, 1, 15)

local toggle = new("TextButton", {
    Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 352),
    BackgroundColor3 = Color3.fromRGB(40, 140, 74), Text = "START",
    TextColor3 = Color3.fromRGB(245, 248, 250), Font = Enum.Font.GothamBold,
    TextSize = 15, BorderSizePixel = 0,
}, mainTab)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, toggle)

------------------------------------------------------------------ config tab
new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, TextWrapped = true,
    Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = Color3.fromRGB(140, 146, 158),
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Config stores both positions and every setting. Save writes a file and puts a code below you can copy. Load reads the file, or paste a code and press Load.",
}, cfgTab)

local saveCfgBtn = btn(cfgTab, "Save Config", 34, Color3.fromRGB(48, 84, 140), 86, 0)
local loadCfgBtn = btn(cfgTab, "Load Config", 34, Color3.fromRGB(48, 84, 140), 86, 91)
local wipeCfgBtn = btn(cfgTab, "Reset All", 34, Color3.fromRGB(70, 52, 52), 86, 182)

local autoLoadBtn = btn(cfgTab, "Auto-load: OFF", 66, Color3.fromRGB(52, 58, 70))
autoLoadBtn.Size = UDim2.new(1, 0, 0, 26)

new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 96),
    BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 10,
    TextColor3 = Color3.fromRGB(130, 136, 148), TextXAlignment = Enum.TextXAlignment.Left,
    Text = writefile and "File storage available." or "No file storage - use the code box.",
}, cfgTab)

local cfgBox = new("TextBox", {
    Size = UDim2.new(1, 0, 0, 274), Position = UDim2.fromOffset(0, 118),
    BackgroundColor3 = Color3.fromRGB(30, 33, 41), Text = "",
    TextColor3 = Color3.fromRGB(205, 210, 220), Font = Enum.Font.Code, TextSize = 9,
    BorderSizePixel = 0, MultiLine = true, TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    ClearTextOnFocus = false, PlaceholderText = "config code appears here",
}, cfgTab)
new("UICorner", { CornerRadius = UDim.new(0, 5) }, cfgBox)
new("UIStroke", { Color = Color3.fromRGB(50, 54, 64), Thickness = 1 }, cfgBox)

local function refreshAll()
    refreshCoords()
    cycleBox.Text = tostring(CONFIG.Cycle)
    menuSlider()
    tapsBox.Text = tostring(CONFIG.Taps)
    holdBox.Text = tostring(CONFIG.Hold)
    lmbBox.Text = tostring(CONFIG.LmbHold)
end

local function paintAutoLoad()
    autoLoadBtn.Text = "Auto-load: " .. (CONFIG.AutoLoad and "ON" or "OFF")
    autoLoadBtn.BackgroundColor3 = CONFIG.AutoLoad and Color3.fromRGB(40, 130, 72) or Color3.fromRGB(52, 58, 70)
end
paintAutoLoad()

saveCfgBtn.MouseButton1Click:Connect(function()
    local json = saveCfg()
    if not json then setStatus("Could not encode config", Color3.fromRGB(200, 140, 90)) return end
    cfgBox.Text = json
    if setclipboard then pcall(setclipboard, json) end
    setStatus(writefile and "Saved and copied" or "Copied - no file support", Color3.fromRGB(120, 200, 140))
end)

loadCfgBtn.MouseButton1Click:Connect(function()
    local data
    if cfgBox.Text ~= "" then
        local ok, parsed = pcall(function() return HS:JSONDecode(cfgBox.Text) end)
        if ok and type(parsed) == "table" then data = parsed end
    end
    if not data then data = readCfgFile() end
    if not data then
        setStatus("Nothing to load", Color3.fromRGB(200, 140, 90))
        return
    end
    applyCfg(data)
    refreshAll()
    saveCfg()
    setStatus("Config loaded", Color3.fromRGB(120, 200, 140))
end)

wipeCfgBtn.MouseButton1Click:Connect(function()
    CONFIG.DealerPos, CONFIG.BuyerPos = nil, nil
    CONFIG.Cycle, CONFIG.MenuDelay = 45.5, 1.00
    CONFIG.Taps, CONFIG.Hold, CONFIG.LmbHold = 3, 0.12, 5.3
    cfgBox.Text = ""
    refreshAll(); saveCfg(); setStatus("Reset to defaults")
end)

autoLoadBtn.MouseButton1Click:Connect(function()
    CONFIG.AutoLoad = not CONFIG.AutoLoad
    paintAutoLoad(); saveCfg()
    setStatus(CONFIG.AutoLoad and "Config will auto-load" or "Auto-load off")
end)

local cursor = new("Frame", {
    Size = UDim2.fromOffset(6, 6), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 0, ZIndex = 40, Visible = false,
}, gui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, cursor)
new("UIStroke", { Color = Color3.fromRGB(15, 15, 18), Thickness = 1 }, cursor)

------------------------------------------------------------------ menu state
local function setMenu(open)
    menuOpen = open
    main.Visible = open
    hint.Visible = not open
    cursor.Visible = open
    if camConn then camConn:Disconnect(); camConn = nil end

    if open then
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        camConn = RunService.RenderStepped:Connect(function()
            if UIS.MouseBehavior ~= Enum.MouseBehavior.Default then
                UIS.MouseBehavior = Enum.MouseBehavior.Default
            end
            if UIS.MouseIconEnabled then UIS.MouseIconEnabled = false end
            local m = UIS:GetMouseLocation()
            cursor.Position = UDim2.fromOffset(m.X - 3, m.Y - 3)
        end)
    else
        UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
        UIS.MouseIconEnabled = true
    end
end

UIS.InputBegan:Connect(function(i)
    if i.KeyCode ~= Enum.KeyCode.RightShift then return end
    if UIS:GetFocusedTextBox() then return end
    setMenu(not menuOpen)
end)

------------------------------------------------------------------ actions
dealerBtn.MouseButton1Click:Connect(function()
    local hrp = getRoot()
    if hrp then CONFIG.DealerPos = hrp.Position; refreshCoords(); saveCfg(); setStatus("Dealer set") end
end)

buyerBtn.MouseButton1Click:Connect(function()
    local hrp = getRoot()
    if hrp then CONFIG.BuyerPos = hrp.Position; refreshCoords(); saveCfg(); setStatus("Buyer set") end
end)

clearBtn.MouseButton1Click:Connect(function()
    CONFIG.DealerPos, CONFIG.BuyerPos = nil, nil
    refreshCoords(); saveCfg(); setStatus("Positions cleared")
end)

tapBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        setStatus("Test: E -> " .. string.format("%.2f", CONFIG.MenuDelay) .. "s -> 1")
        pressE()
        task.wait(CONFIG.MenuDelay)
        pressOne()
        task.wait(0.6)
        if hasPackage() then
            setStatus("Package detected", Color3.fromRGB(120, 200, 140))
        else
            setStatus("No package detected - adjust delay", Color3.fromRGB(200, 140, 90))
        end
    end)
end)

------------------------------------------------------------------ finders
local function findByExactName(name)
    for _, o in ipairs(Workspace:GetDescendants()) do
        if (o:IsA("Model") or o:IsA("BasePart")) and sameName(o.Name, name) then
            local ok, pos = pcall(function() return o:GetPivot().Position end)
            if ok and pos then return pos, o.Name end
        end
    end
    return nil
end

local function nearestByPattern(pats)
    local hrp = getRoot()
    if not hrp then return nil, nil end
    local best, bestD, bestName = nil, math.huge, nil
    for _, o in ipairs(Workspace:GetDescendants()) do
        if (o:IsA("Model") or o:IsA("BasePart")) and o.Parent ~= LP.Character and matchAny(o.Name, pats) then
            local ok, pos = pcall(function() return o:GetPivot().Position end)
            if ok and pos then
                local d = (pos - hrp.Position).Magnitude
                if d < bestD then best, bestD, bestName = pos, d, o.Name end
            end
        end
    end
    return best, bestName
end

findDealerBtn.MouseButton1Click:Connect(function()
    setStatus("Scanning for dealer...")
    task.spawn(function()
        local pos, nm = findByExactName(CONFIG.DealerName)
        local how = "exact name"
        if not pos then pos, nm = nearestByPattern(CONFIG.NpcPatterns); how = "pattern" end
        if pos then
            CONFIG.DealerPos = pos
            refreshCoords(); saveCfg()
            setStatus("Dealer set (" .. how .. ": " .. tostring(nm) .. ")", Color3.fromRGB(120, 200, 140))
        else
            setStatus("Dealer not loaded - get closer", Color3.fromRGB(200, 140, 90))
        end
    end)
end)

findBuyerBtn.MouseButton1Click:Connect(function()
    setStatus("Scanning for buyer...")
    task.spawn(function()
        local pos, nm = findByExactName(CONFIG.BuyerName)
        local how = "exact name"
        if not pos then pos, nm = nearestByPattern(CONFIG.BuyerPatterns); how = "pattern" end
        if pos then
            CONFIG.BuyerPos = pos
            refreshCoords(); saveCfg()
            setStatus("Buyer set (" .. how .. ": " .. tostring(nm) .. ")", Color3.fromRGB(120, 200, 140))
        else
            setStatus("Buyer not loaded - get closer", Color3.fromRGB(200, 140, 90))
        end
    end)
end)

------------------------------------------------------------------ loop
local function doDealer()
    teleportTo(CONFIG.DealerPos)
    task.wait(0.3)
    local p = promptFor(CONFIG.DealerName, CONFIG.DealerPos)
    if p then nativeFire(p) end

    for _ = 1, CONFIG.Taps do
        if not running then return false end
        local had = hasPackage()
        pressE()
        task.wait(CONFIG.MenuDelay)
        pressOne()
        if waitFor(function() return not had and hasPackage() end, CONFIG.AcceptWait) then
            setStatus("Package taken", Color3.fromRGB(120, 200, 140))
            return true
        end
        if hasPackage() then
            setStatus("Already holding a package", Color3.fromRGB(120, 200, 140))
            return true
        end
        task.wait(0.3)
    end
    setStatus("Dealer: package not taken", Color3.fromRGB(200, 140, 90))
    return false
end

local function doBuyer()
    teleportTo(CONFIG.BuyerPos)
    task.wait(0.3)
    local p = promptFor(CONFIG.BuyerName, CONFIG.BuyerPos)
    if p then nativeFire(p) end

    for _ = 1, CONFIG.Taps do
        if not running then return false end
        pressE()
        if waitFor(function() return not hasPackage() end, CONFIG.DeliverWait) then
            setStatus("Delivered", Color3.fromRGB(120, 200, 140))
            return true
        end
        task.wait(0.25)
    end
    setStatus("Buyer: still holding package", Color3.fromRGB(200, 140, 90))
    return false
end

local function ensureEquipped()
    if equippedTool() then return true end
    for _ = 1, 3 do
        if not running then return false end
        pressOne()
        if waitFor(function() return equippedTool() ~= nil end, 0.5) then return true end
    end
    return false
end

local function afterDelivery()
    if not ensureEquipped() then
        setStatus("Nothing in slot 1 - LMB skipped", Color3.fromRGB(200, 140, 90))
        return
    end

    setStatus(string.format("Holding LMB %.1fs", CONFIG.LmbHold))
    lmbDown()
    local t = 0
    while running and t < CONFIG.LmbHold do
        task.wait(0.1)
        t = t + 0.1
    end
    lmbUp()
    task.wait(0.15)
    if not running then return end
    pressOne()
    setStatus("Post-delivery 1 sent", Color3.fromRGB(120, 200, 140))
end

local function loop()
    while running do
        if not (CONFIG.DealerPos and CONFIG.BuyerPos) then
            setStatus("Set dealer + buyer first", Color3.fromRGB(200, 140, 90))
            task.wait(0.6)
        else
            local t0 = os.clock()
            local got = doDealer()
            if not running then break end
            if got then
                local sent = doBuyer()
                if not running then break end
                if sent then afterDelivery() end
            end
            if not running then break end

            local left = CONFIG.Cycle - (os.clock() - t0)
            while running and left > 0 do
                setStatus(string.format("Next quest in %.1fs", left))
                task.wait(math.min(0.25, left))
                left = CONFIG.Cycle - (os.clock() - t0)
            end
        end
    end
end

toggle.MouseButton1Click:Connect(function()
    if running then
        running = false
        toggle.Text = "START"
        toggle.BackgroundColor3 = Color3.fromRGB(40, 140, 74)
        setStatus("Stopped")
    else
        if not (CONFIG.DealerPos and CONFIG.BuyerPos) then
            setStatus("Set dealer + buyer first", Color3.fromRGB(200, 140, 90))
            return
        end
        running = true
        toggle.Text = "STOP"
        toggle.BackgroundColor3 = Color3.fromRGB(170, 58, 58)
        setStatus("Running", Color3.fromRGB(120, 200, 140))
        task.spawn(loop)
    end
end)

selectTab("main")
refreshAll()
setMenu(false)

getgenv().DQL_Unload = function()
    running = false
    lmbUp()
    if camConn then camConn:Disconnect() end
    UIS.MouseBehavior = Enum.MouseBehavior.Default
    UIS.MouseIconEnabled = true
    if gui then gui:Destroy() end
end
