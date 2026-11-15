--[[
    Dealer -> Deliver -> Buyer loop  |  Solara
    RightShift = open/close menu.
    Dealer: E -> adjustable delay -> 1.  Buyer: E.
    After each delivery: hold RMB, release, press 1.
    Cycle repeats every 45.5s (measured from cycle start).
]]

if getgenv().DQL_Unload then pcall(getgenv().DQL_Unload) end

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local VIM        = game:GetService("VirtualInputManager")
local LP = Players.LocalPlayer

local CONFIG = {
    DealerPos  = nil,
    BuyerPos   = nil,
    Cycle      = 45.5,
    MenuDelay  = 0.33,
    AcceptWait = 2.0,
    DeliverWait= 1.5,
    Taps       = 3,
    Hold       = 0.12,
    RmbHold    = 5.3,
    Radius     = 14,
    NpcPatterns     = { "dealer", "package", "delivery", "courier", "mail" },
    PackagePatterns = { "package", "parcel", "delivery", "box", "mail", "crate" },
}

local FILE = "DQL_config.json"
local running, menuOpen = false, false
local camConn

------------------------------------------------------------------ io
local function saveCfg()
    if not writefile then return end
    local d = {}
    for k, v in pairs(CONFIG) do
        if type(v) ~= "table" then
            d[k] = typeof(v) == "Vector3" and { v.X, v.Y, v.Z } or v
        end
    end
    pcall(writefile, FILE, game:GetService("HttpService"):JSONEncode(d))
end

local function loadCfg()
    if not (isfile and readfile and isfile(FILE)) then return end
    local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(FILE)) end)
    if not ok or type(data) ~= "table" then return end
    for k, v in pairs(data) do
        if CONFIG[k] ~= nil then
            if type(v) == "table" and #v == 3 then
                CONFIG[k] = Vector3.new(v[1], v[2], v[3])
            else
                CONFIG[k] = v
            end
        end
    end
end
loadCfg()

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

local function promptsNear(pos, radius)
    local out = {}
    for _, o in ipairs(Workspace:GetDescendants()) do
        local isP = (o:IsA("ProximityPrompt") and o.Enabled) or o:IsA("ClickDetector")
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

local function rmbDown()
    if mouse2press then pcall(mouse2press) end
    pcall(function() VIM:SendMouseButtonEvent(0, 0, 2, true, 1, game) end)
end

local function rmbUp()
    if mouse2release then pcall(mouse2release) end
    pcall(function() VIM:SendMouseButtonEvent(0, 0, 2, false, 1, game) end)
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
    Size = UDim2.fromOffset(262, 388), Position = UDim2.fromOffset(60, 90),
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

local status = new("TextLabel", {
    Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 36),
    BackgroundTransparency = 1, TextWrapped = true, TextSize = 11,
    Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(150, 156, 168),
    Text = "Set both positions, then press START", TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local function setStatus(t, col)
    status.Text = t
    status.TextColor3 = col or Color3.fromRGB(150, 156, 168)
end

local function btn(text, y, color, w, x)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(w or 246, 26), Position = UDim2.fromOffset(x or 8, y),
        BackgroundColor3 = color, Text = text, TextColor3 = Color3.fromRGB(240, 242, 248),
        Font = Enum.Font.GothamSemibold, TextSize = 11, BorderSizePixel = 0,
    }, main)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    return b
end

local dealerBtn = btn("Set Dealer", 76, Color3.fromRGB(48, 84, 140))
dealerBtn.Size = UDim2.new(1, -16, 0, 30)
local buyerBtn = btn("Set Buyer", 112, Color3.fromRGB(48, 84, 140))
buyerBtn.Size = UDim2.new(1, -16, 0, 30)

local autoBtn  = btn("Auto-Find", 148, Color3.fromRGB(52, 58, 70), 78, 8)
local tapBtn   = btn("Test E+1", 148, Color3.fromRGB(60, 72, 96), 78, 92)
local clearBtn = btn("Clear", 148, Color3.fromRGB(70, 52, 52), 78, 176)

local coordLabel = new("TextLabel", {
    Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 180),
    BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 10,
    TextColor3 = Color3.fromRGB(120, 128, 142), TextXAlignment = Enum.TextXAlignment.Left,
    Text = "dealer: -, -    buyer: -, -",
}, main)

local function refreshCoords()
    local function f(v) return v and string.format("%d, %d", v.X, v.Z) or "-, -" end
    coordLabel.Text = "dealer: " .. f(CONFIG.DealerPos) .. "    buyer: " .. f(CONFIG.BuyerPos)
end
refreshCoords()

local function field(label, y, get, set, min, max)
    new("TextLabel", {
        Size = UDim2.new(0, 96, 0, 18), Position = UDim2.fromOffset(8, y),
        BackgroundTransparency = 1, Text = label, Font = Enum.Font.Gotham,
        TextSize = 11, TextColor3 = Color3.fromRGB(160, 166, 178),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)
    local box = new("TextBox", {
        Size = UDim2.fromOffset(54, 20), Position = UDim2.fromOffset(190, y - 1),
        BackgroundColor3 = Color3.fromRGB(34, 37, 45), Text = tostring(get()),
        TextColor3 = Color3.fromRGB(230, 234, 240), Font = Enum.Font.Code, TextSize = 12,
        BorderSizePixel = 0, ClearTextOnFocus = false,
    }, main)
    new("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then set(math.clamp(n, min, max)) end
        box.Text = tostring(get())
        saveCfg()
    end)
    return box
end

local function slider(label, y, get, set, min, max)
    new("TextLabel", {
        Size = UDim2.new(0, 96, 0, 18), Position = UDim2.fromOffset(8, y),
        BackgroundTransparency = 1, Text = label, Font = Enum.Font.Gotham,
        TextSize = 11, TextColor3 = Color3.fromRGB(160, 166, 178),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    local track = new("Frame", {
        Size = UDim2.fromOffset(120, 6), Position = UDim2.fromOffset(96, y + 6),
        BackgroundColor3 = Color3.fromRGB(44, 48, 58), BorderSizePixel = 0,
    }, main)
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
        Size = UDim2.fromOffset(52, 20), Position = UDim2.fromOffset(228, y - 1),
        BackgroundColor3 = Color3.fromRGB(34, 37, 45), Text = string.format("%.2f", get()),
        TextColor3 = Color3.fromRGB(230, 234, 240), Font = Enum.Font.Code, TextSize = 11,
        BorderSizePixel = 0, ClearTextOnFocus = false,
    }, main)
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

local cycleBox = field("Cycle (s)", 206, function() return CONFIG.Cycle end,
    function(v) CONFIG.Cycle = v end, 5, 300)
local menuSlider = slider("E to 1 delay", 230, function() return CONFIG.MenuDelay end,
    function(v) CONFIG.MenuDelay = v end, 0.1, 1.0)
local tapsBox  = field("E taps", 258, function() return CONFIG.Taps end,
    function(v) CONFIG.Taps = math.floor(v) end, 1, 10)
local holdBox  = field("Hold (s)", 282, function() return CONFIG.Hold end,
    function(v) CONFIG.Hold = v end, 0.05, 1)
local rmbBox   = field("RMB hold (s)", 306, function() return CONFIG.RmbHold end,
    function(v) CONFIG.RmbHold = v end, 1, 15)

local toggle = new("TextButton", {
    Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 338),
    BackgroundColor3 = Color3.fromRGB(40, 140, 74), Text = "START",
    TextColor3 = Color3.fromRGB(245, 248, 250), Font = Enum.Font.GothamBold,
    TextSize = 15, BorderSizePixel = 0,
}, main)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, toggle)

-- custom cursor (small, matches the in-game dot)
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

autoBtn.MouseButton1Click:Connect(function()
    local hrp = getRoot()
    if not hrp then return end
    local best, bestD = nil, math.huge
    for _, o in ipairs(Workspace:GetDescendants()) do
        if o:IsA("ProximityPrompt") and o.Enabled and o.Parent then
            local label = (o.ActionText or "") .. " " .. (o.ObjectText or "") .. " " .. o.Parent.Name
            if matchAny(label, CONFIG.NpcPatterns) then
                local d = (o.Parent:GetPivot().Position - hrp.Position).Magnitude
                if d < bestD then best, bestD = o.Parent:GetPivot().Position, d end
            end
        end
    end
    if best then
        CONFIG.DealerPos = best; refreshCoords(); saveCfg(); setStatus("Dealer auto-found")
    else
        setStatus("No dealer prompt found - set manually", Color3.fromRGB(200, 140, 90))
    end
end)

------------------------------------------------------------------ loop
local function doDealer()
    teleportTo(CONFIG.DealerPos)
    task.wait(0.3)
    local hits = promptsNear(CONFIG.DealerPos, CONFIG.Radius)
    if hits[1] then nativeFire(hits[1].obj) end

    for _ = 1, CONFIG.Taps do
        if not running then return false end
        local had = hasPackage()
        pressE()
        task.wait(CONFIG.MenuDelay)   -- menu needs to open first
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
    local hits = promptsNear(CONFIG.BuyerPos, CONFIG.Radius)
    if hits[1] then nativeFire(hits[1].obj) end

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

local function afterDelivery()
    setStatus(string.format("Holding RMB %.1fs", CONFIG.RmbHold))
    rmbDown()
    local t = 0
    while running and t < CONFIG.RmbHold do
        task.wait(0.1)
        t = t + 0.1
    end
    rmbUp()
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

            -- hold the 45.5s cadence from the start of this cycle
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

setMenu(false)

getgenv().DQL_Unload = function()
    running = false
    rmbUp()
    if camConn then camConn:Disconnect() end
    UIS.MouseBehavior = Enum.MouseBehavior.Default
    UIS.MouseIconEnabled = true
    if gui then gui:Destroy() end
end
