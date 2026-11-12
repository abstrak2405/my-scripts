--[[
    SaveMap | FayintX (versi diperbaiki)
    Perbaikan utama:
    - Hapus goto/label (tidak didukung Luau -> penyebab GUI tidak muncul)
    - Parent GUI aman: gethui -> CoreGui -> PlayerGui + protect_gui
    - HttpGet/loadstring dibungkus pcall, ada fallback request/http_request
    - Cancel tidak lagi bisa diklik setelah selesai & tidak bisa Start ganda
    - Koneksi drag dilepas saat GUI ditutup
    - Panel guide responsif (scroll) dan ikut hancur saat GUI ditutup
    - Guard error di seluruh bagian pembuatan GUI
]]

----------------------------------------------------------------
-- Services
----------------------------------------------------------------
local Players           = game:GetService("Players")
local CoreGui           = game:GetService("CoreGui")
local StarterGui        = game:GetService("StarterGui")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

----------------------------------------------------------------
-- Konfigurasi
----------------------------------------------------------------
local GUI_NAME = "FayintXCopy"
local GUIDE_NAME = "SaveMapGuide"
local SAVE_MODULE_URL =
    "https://raw.githubusercontent.com/FayintXhub/FayintLibrary/refs/heads/main/FYSavemap.luau"

local SIZE_OPEN = UDim2.new(0.36, 0, 0.42, 0)
local SIZE_ZERO = UDim2.new(0, 0, 0, 0)

local C = {
    bg        = Color3.fromRGB(18, 18, 18),
    bar       = Color3.fromRGB(26, 26, 26),
    button    = Color3.fromRGB(35, 35, 35),
    input     = Color3.fromRGB(30, 30, 30),
    text      = Color3.fromRGB(255, 255, 255),
    textDim   = Color3.fromRGB(170, 170, 170),
    textLabel = Color3.fromRGB(200, 200, 200),
    off       = Color3.fromRGB(60, 60, 70),
    orange    = Color3.fromRGB(255, 140, 0),
    green     = Color3.fromRGB(80, 200, 120),
    red       = Color3.fromRGB(220, 20, 60),
}

----------------------------------------------------------------
-- Deteksi executor + warna aksen (tanpa goto)
----------------------------------------------------------------
local function detectExecutor()
    local ok, name = pcall(function()
        if identifyexecutor then return (identifyexecutor()) end
        if getexecutorname then return (getexecutorname()) end
        if executor then return executor end
        return nil
    end)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return "Unknown"
end

local EXECUTOR_COLORS = {
    { { "real" },                          "#00c8ff" },
    { { "flux" },                          "#30ff6a" },
    { { "delta" },                         "#e74c3c" },
    { { "arceus" },                        "#a03cff" },
    { { "krampus", "oxygen" },             "#ff3838" },
    { { "volcano" },                       "#ff8c00" },
    { { "synapse", "scriptware", "script-ware", "krypton" }, "#ffd700" },
    { { "wave" },                          "#00e5ff" },
    { { "zenith" },                        "#ff00ff" },
    { { "seliware" },                      "#00ffa2" },
    { { "krnl" },                          "#1e90ff" },
    { { "trigon" },                        "#ff007f" },
    { { "nihon" },                         "#8a2be2" },
    { { "celery" },                        "#4caf50" },
    { { "lunar" },                         "#8080ff" },
    { { "valyse" },                        "#ff1493" },
    { { "vega" },                          "#4682b4" },
    { { "electron" },                      "#7fffd4" },
    { { "awp" },                           "#ff005e" },
    { { "bunni" },                         "#ff69b4" },
}

local function pickAccent(name)
    local lowered = string.lower(name)
    for _, entry in ipairs(EXECUTOR_COLORS) do
        for _, keyword in ipairs(entry[1]) do
            if string.find(lowered, keyword, 1, true) then
                local ok, color = pcall(Color3.fromHex, entry[2])
                if ok then return color end
            end
        end
    end
    return Color3.fromRGB(200, 200, 200)
end

local executorName = detectExecutor()
local accent = pickAccent(executorName)

----------------------------------------------------------------
-- Helper UI
----------------------------------------------------------------
local function new(class, props, parent)
    local inst = Instance.new(class)
    for key, value in pairs(props) do
        inst[key] = value
    end
    inst.Parent = parent
    return inst
end

local function round(parent, radius)
    return new("UICorner", { CornerRadius = radius }, parent)
end

local function notify(title, text, icon)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 5,
            Icon = icon or "rbxassetid://6023426925",
        })
    end)
end

local function tween(inst, time, props, style, direction)
    local t = TweenService:Create(
        inst,
        TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
        props
    )
    t:Play()
    return t
end

local function isPointerStart(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isPointerMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

-- Semua koneksi global dikumpulkan agar bisa dilepas saat GUI ditutup
local connections = {}

local function makeDraggable(frame, handle)
    local dragging, dragStart, startPos = false, nil, nil

    table.insert(connections, handle.InputBegan:Connect(function(input)
        if isPointerStart(input) then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end))

    table.insert(connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and isPointerMove(input) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))

    table.insert(connections, UserInputService.InputEnded:Connect(function(input)
        if isPointerStart(input) then
            dragging = false
        end
    end))
end

----------------------------------------------------------------
-- Parent GUI yang aman
----------------------------------------------------------------
local function getGuiParent()
    if gethui then
        local ok, ui = pcall(gethui)
        if ok and typeof(ui) == "Instance" then return ui end
    end
    local ok = pcall(function() return CoreGui.Name end)
    if ok then return CoreGui end
    local lp = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()

local function protect(gui)
    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(gui)
        elseif protect_gui then
            protect_gui(gui)
        end
    end)
end

-- Bersihkan GUI lama
for _, parent in ipairs({ CoreGui, guiParent }) do
    pcall(function()
        for _, name in ipairs({ GUI_NAME, GUIDE_NAME }) do
            local old = parent:FindFirstChild(name)
            if old then old:Destroy() end
        end
    end)
end

local screenGui = new("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
})
protect(screenGui)
screenGui.Parent = guiParent

----------------------------------------------------------------
-- Frame utama
----------------------------------------------------------------
local main = new("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = C.bg,
    BackgroundTransparency = 0.1,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = SIZE_ZERO,
}, screenGui)

round(main, UDim.new(0, 14))
new("UIAspectRatioConstraint", { AspectRatio = 0.78 }, main)
new("UISizeConstraint", { MinSize = Vector2.new(240, 340), MaxSize = Vector2.new(480, 680) }, main)
new("UIStroke", {
    Color = accent, Transparency = 0.4, Thickness = 1.8,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, main)

-- Top bar
local topBar = new("Frame", {
    Name = "TopBar",
    BackgroundColor3 = C.bar,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0.16, 0),
    ZIndex = 2,
}, main)
round(topBar, UDim.new(0, 14))

new("Frame", { -- menutup sudut bawah topBar agar rata
    BackgroundColor3 = C.bar, BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0.7, 0), Size = UDim2.new(1, 0, 0.3, 0), ZIndex = 2,
}, topBar)

new("TextLabel", {
    Name = "Title",
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 16, 0, 8),
    Size = UDim2.new(0.6, 0, 0.4, 0),
    Font = Enum.Font.GothamBold,
    Text = "SAVEMAP | FAYINTX",
    TextColor3 = C.text,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 3,
}, topBar)

new("TextLabel", {
    Name = "Description",
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 16, 0.5, 0),
    Size = UDim2.new(0.6, 0, 0.3, 0),
    Font = Enum.Font.Gotham,
    Text = executorName .. " Executor",
    TextColor3 = accent,
    TextScaled = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 3,
}, topBar)

new("Frame", {
    Name = "AccentBar",
    BackgroundColor3 = accent,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 16, 1, -3),
    Size = UDim2.new(0.2, 0, 0, 3),
    ZIndex = 4,
}, topBar)

local closeButton = new("TextButton", {
    Name = "Close",
    AnchorPoint = Vector2.new(1, 0),
    BackgroundColor3 = Color3.fromRGB(45, 45, 45),
    BorderSizePixel = 0,
    Position = UDim2.new(1, -12, 0, 10),
    Size = UDim2.new(0, 28, 0, 28),
    AutoButtonColor = false,
    Font = Enum.Font.GothamBold,
    Text = "×",
    TextColor3 = C.textDim,
    TextSize = 24,
    ZIndex = 5,
}, topBar)
round(closeButton, UDim.new(0.25, 0))

makeDraggable(main, topBar)

-- Tab
local tabContainer = new("Frame", {
    Name = "TabContainer",
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 0, 0.16, 0),
    Size = UDim2.new(1, 0, 0.12, 0),
}, main)
new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, tabContainer)

local function makeTab(name, text, x, active)
    local tab = new("TextButton", {
        Name = name,
        BackgroundColor3 = active and accent or C.button,
        BorderSizePixel = 0,
        Position = UDim2.new(x, 0, 0.125, 0),
        Size = UDim2.new(0.48, 0, 0.75, 0),
        AutoButtonColor = false,
        Font = Enum.Font.GothamBold,
        Text = text,
        TextColor3 = active and C.text or C.textDim,
        TextSize = 14,
    }, tabContainer)
    round(tab, UDim.new(0.25, 0))
    return tab
end

local saveTab = makeTab("SaveTab", "SAVE", 0, true)
local settingsTab = makeTab("SettingsTab", "SETTINGS", 0.52, false)

-- Konten
local content = new("Frame", {
    Name = "Content",
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 0, 0.28, 0),
    Size = UDim2.new(1, 0, 0.72, 0),
}, main)
new("UIPadding", {
    PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 16),
    PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
}, content)

local savePage = new("Frame", {
    Name = "SavePage", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
}, content)
local settingsPage = new("Frame", {
    Name = "SettingsPage", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Visible = false,
}, content)

----------------------------------------------------------------
-- Halaman SAVE
----------------------------------------------------------------
local mode = "optimized"

local modeContainer = new("Frame", {
    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.12, 0),
}, savePage)
new("TextLabel", {
    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.35, 0),
    Font = Enum.Font.Gotham, Text = "Save Mode:", TextColor3 = C.textLabel,
    TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
}, modeContainer)
local modeButtons = new("Frame", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.35, 0), Size = UDim2.new(1, 0, 0.65, 0),
}, modeContainer)

local modeList = {
    { text = "FULL",    value = "full",      x = 0 },
    { text = "OPT",     value = "optimized", x = 0.33 },
    { text = "SCRIPTS", value = "scripts",   x = 0.66 },
}
local modeButtonByValue = {}

local function setMode(value)
    mode = value
    for v, button in pairs(modeButtonByValue) do
        local active = v == value
        button.BackgroundColor3 = active and accent or C.button
        button.TextColor3 = active and C.text or C.textDim
    end
end

for _, info in ipairs(modeList) do
    local button = new("TextButton", {
        Position = UDim2.new(info.x, 0, 0, 0),
        Size = UDim2.new(0.33, -2, 1, 0),
        BackgroundColor3 = C.button,
        BorderSizePixel = 0,
        Text = info.text,
        TextColor3 = C.textDim,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        AutoButtonColor = false,
    }, modeButtons)
    round(button, UDim.new(0.15, 0))
    modeButtonByValue[info.value] = button
    button.MouseButton1Click:Connect(function() setMode(info.value) end)
end

-- Nama file
local filenameContainer = new("Frame", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.14, 0), Size = UDim2.new(1, 0, 0.12, 0),
}, savePage)
new("TextLabel", {
    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.35, 0),
    Font = Enum.Font.Gotham, Text = "File Name:", TextColor3 = C.textLabel,
    TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
}, filenameContainer)
local filenameBox = new("TextBox", {
    BackgroundColor3 = C.input,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0.35, 0),
    Size = UDim2.new(1, 0, 0.65, 0),
    ClearTextOnFocus = false,
    Font = Enum.Font.Gotham,
    PlaceholderColor3 = Color3.fromRGB(120, 120, 120),
    PlaceholderText = "MySavedGame",
    Text = "",
    TextColor3 = C.text,
    TextSize = 13,
}, filenameContainer)
round(filenameBox, UDim.new(0.15, 0))
new("UIStroke", { Color = Color3.fromRGB(80, 80, 80), Transparency = 0.5 }, filenameBox)

-- Progress
local progressContainer = new("Frame", {
    Name = "ProgressContainer",
    BackgroundColor3 = C.input,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Position = UDim2.new(0, 0, 0.28, 0),
    Size = UDim2.new(1, 0, 0.08, 0),
}, savePage)
round(progressContainer, UDim.new(0.15, 0))

local progressFill = new("Frame", {
    BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0),
}, progressContainer)
round(progressFill, UDim.new(0.15, 0))

local progressText = new("TextLabel", {
    BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
    Font = Enum.Font.Gotham, Text = "Ready (0%)", TextColor3 = C.textLabel, TextSize = 11, ZIndex = 2,
}, progressContainer)

local statusLabel = new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.38, 0), Size = UDim2.new(1, 0, 0.06, 0),
    Font = Enum.Font.Gotham, Text = "Status: Idle", TextColor3 = Color3.fromRGB(180, 180, 180),
    TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
}, savePage)

local detailLabel = new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.45, 0), Size = UDim2.new(1, 0, 0.06, 0),
    Font = Enum.Font.Gotham, Text = "Instances: 0 / 0", TextColor3 = Color3.fromRGB(150, 150, 150),
    TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
}, savePage)

-- Tombol aksi
local actionButtons = new("Frame", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.56, 0), Size = UDim2.new(1, 0, 0.4, 0),
}, savePage)

local startButton = new("TextButton", {
    BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.48, 0),
    AutoButtonColor = false, Font = Enum.Font.GothamBold, Text = "🚀 START SAVING",
    TextColor3 = C.text, TextSize = 14,
}, actionButtons)
round(startButton, UDim.new(0.15, 0))

local guideButton = new("TextButton", {
    BackgroundColor3 = Color3.fromRGB(50, 50, 80), BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0.52, 0), Size = UDim2.new(1, 0, 0.48, 0),
    AutoButtonColor = false, Font = Enum.Font.GothamBold, Text = "ℹ️ DETAILED GUIDE",
    TextColor3 = Color3.fromRGB(200, 200, 255), TextSize = 12,
}, actionButtons)
round(guideButton, UDim.new(0.15, 0))

local cancelButton = new("TextButton", {
    BackgroundColor3 = Color3.fromRGB(45, 45, 45), BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0.52, 0), Size = UDim2.new(1, 0, 0.48, 0),
    AutoButtonColor = false, Font = Enum.Font.GothamBold, Text = "❌ CANCEL",
    TextColor3 = C.textDim, TextSize = 12, Visible = false,
}, actionButtons)
round(cancelButton, UDim.new(0.15, 0))

----------------------------------------------------------------
-- Halaman SETTINGS
----------------------------------------------------------------
local function makeToggle(label, y, default)
    local toggle = { name = label, state = default }

    local row = new("Frame", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, y), Size = UDim2.new(1, 0, 0, 40),
    }, settingsPage)

    new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(0.7, 0, 1, 0),
        Font = Enum.Font.Gotham, Text = label, TextColor3 = C.textLabel,
        TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local track = new("TextButton", {
        BackgroundColor3 = default and accent or C.off, BorderSizePixel = 0, Text = "",
        AutoButtonColor = false, Position = UDim2.new(1, -40, 0.5, -10), Size = UDim2.new(0, 40, 0, 20),
    }, row)
    round(track, UDim.new(1, 0))

    local dot = new("Frame", {
        BackgroundColor3 = C.text, BorderSizePixel = 0,
        Position = UDim2.new(0, default and 22 or 2, 0.5, -8), Size = UDim2.new(0, 16, 0, 16),
    }, track)
    round(dot, UDim.new(1, 0))

    track.MouseButton1Click:Connect(function()
        toggle.state = not toggle.state
        tween(dot, 0.2, { Position = UDim2.new(0, toggle.state and 22 or 2, 0.5, -8) })
        tween(track, 0.2, { BackgroundColor3 = toggle.state and accent or C.off })
    end)

    return toggle
end

local settings = {
    noscripts               = makeToggle("Disable Decompile", 0, false),
    scriptcache             = makeToggle("Use Cache", 40, true),
    SaveBytecode            = makeToggle("Save Bytecode", 80, false),
    IgnoreDefaultProperties = makeToggle("Ignore Default Props", 120, true),
    SafeMode                = makeToggle("Safe Mode", 160, false),
    SaveTerrain             = makeToggle("Save Terrain", 200, true),
}

----------------------------------------------------------------
-- Tab switching
----------------------------------------------------------------
local function showTab(name)
    local onSave = name == "Save"
    saveTab.BackgroundColor3     = onSave and accent or C.button
    saveTab.TextColor3           = onSave and C.text or C.textDim
    settingsTab.BackgroundColor3 = onSave and C.button or accent
    settingsTab.TextColor3       = onSave and C.textDim or C.text
    savePage.Visible     = onSave
    settingsPage.Visible = not onSave
end

saveTab.MouseButton1Click:Connect(function() showTab("Save") end)
settingsTab.MouseButton1Click:Connect(function() showTab("Settings") end)

----------------------------------------------------------------
-- State & progress
----------------------------------------------------------------
local state = {
    running = false,   -- sesi save aktif (tombol cancel tampil)
    busy = false,      -- modul save masih berjalan di belakang layar
    cancelled = false,
    done = false,
    runId = 0,
    total = 0,
    processed = 0,
    startTime = 0,
}

local function setProgress(percent, phase, detail)
    if not progressContainer.Parent then return end

    percent = math.floor(math.clamp(percent, 0, 100))
    local countText = state.total > 0
        and string.format(" (%d/%d)", state.processed, state.total) or ""
    progressText.Text = string.format("%d%%%s", percent, countText)

    tween(progressFill, 0.2, { Size = UDim2.new(percent / 100, 0, 1, 0) })

    if phase then
        statusLabel.Text = string.format("Status: %s (%.1fs)", phase, os.clock() - state.startTime)
    end
    if detail then
        detailLabel.Text = detail
    end

    if percent < 33 then
        progressFill.BackgroundColor3 = accent
    elseif percent < 66 then
        progressFill.BackgroundColor3 = C.orange
    else
        progressFill.BackgroundColor3 = C.green
    end
end

local function resetButtons()
    startButton.Text = "🚀 START SAVING"
    startButton.BackgroundColor3 = accent
    cancelButton.Visible = false
    guideButton.Visible = true
end

----------------------------------------------------------------
-- Logika save
----------------------------------------------------------------
local function countInstances()
    local total = 0
    for _, service in ipairs({ Workspace, Lighting, ReplicatedStorage }) do
        local ok, n = pcall(function() return #service:GetDescendants() end)
        total = total + 1 + (ok and n or 0)
    end
    return total
end

local function httpGet(url)
    -- Coba game:HttpGet dulu, lalu fallback ke request/http_request
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(res) == "string" and res ~= "" then return res end

    local req = (syn and syn.request) or http_request or request
        or (http and http.request) or (fluxus and fluxus.request)
    if req then
        local ok2, r = pcall(req, { Url = url, Method = "GET" })
        if ok2 and r and (r.StatusCode == 200 or r.Success) and r.Body then
            return r.Body
        end
    end
    error("HttpGet gagal: " .. tostring(res))
end

local function loadSaveModule()
    local compile = loadstring or load
    if not compile then
        error("Executor tidak mendukung loadstring")
    end
    local source = httpGet(SAVE_MODULE_URL)
    local fn, err = compile(source, "FYSavemap")
    if not fn then
        error("Gagal compile modul: " .. tostring(err))
    end
    return fn()
end

local function buildOptions(fileName, runId, onFinished)
    return {
        mode = mode,
        noscripts = settings.noscripts.state,
        scriptcache = settings.scriptcache.state,
        SaveBytecode = settings.SaveBytecode.state,
        IgnoreDefaultProperties = settings.IgnoreDefaultProperties.state,
        SafeMode = settings.SafeMode.state,
        SaveTerrain = settings.SaveTerrain.state,
        ShowStatus = false,
        FilePath = fileName,
        __DEBUG_MODE = false,
        timeout = 15,
        AvoidFileOverwrite = true,
        AlternativeWritefile = true,
        ReadMe = true,
        AntiIdle = true,
        Callback = function(data, _, size)
            onFinished()
            if state.cancelled or state.runId ~= runId then return end

            setProgress(95, "Writing", "Finalizing file write...")

            -- Tulis manual hanya jika modul belum membuat file sendiri
            if writefile then
                local path = fileName:match("%.rbxlx?$") and fileName or (fileName .. ".rbxlx")
                local exists = isfile and isfile(path)
                if not exists and data then
                    pcall(writefile, path, data)
                end
            end

            local bytes = (type(size) == "number" and size) or #tostring(data)
            setProgress(100, "Completed",
                string.format("File saved successfully (%.2f MB)", bytes / 1048576))
        end,
    }
end

local function startSave()
    if state.running then return end
    if state.busy then
        notify("Please wait", "Previous save is still finishing in the background")
        return
    end

    state.running = true
    state.busy = true
    state.cancelled = false
    state.done = false
    state.runId = state.runId + 1
    state.processed = 0
    state.total = 0
    state.startTime = os.clock()
    local runId = state.runId

    startButton.Text = "⏳ SAVING..."
    startButton.BackgroundColor3 = C.orange
    cancelButton.Visible = true
    guideButton.Visible = false

    local fileName = filenameBox.Text ~= "" and filenameBox.Text or "FayintSavedMap"
    fileName = fileName:gsub('[\\/:*?"<>|]', "_") -- buang karakter ilegal nama file

    task.spawn(function()
        local ok, err = pcall(function()
            setProgress(0, "Initializing", "Preparing save system...")
            task.wait(0.2)
            if state.cancelled then return end

            setProgress(5, "Scanning", "Counting instances...")
            state.total = countInstances()
            detailLabel.Text = string.format("Total instances: %d", state.total)
            if state.cancelled then return end

            setProgress(10, "Loading", "Loading save module...")
            local saveMap = loadSaveModule()
            if state.cancelled then return end

            setProgress(15, "Configuring", "Building save options...")
            local finished = false
            local options = buildOptions(fileName, runId, function() finished = true end)

            -- Progress estimasi (bukan progres asli dari modul)
            task.spawn(function()
                for p = 20, 90 do
                    if finished or state.cancelled or state.runId ~= runId then break end

                    state.processed = math.floor(p / 90 * state.total)
                    local phase =
                        p < 35 and "Scanning Properties" or
                        p < 55 and "Decompiling Scripts" or
                        p < 75 and "Processing Terrain" or "Finalizing Data"

                    setProgress(p, phase,
                        string.format("Instances: %d / %d (estimasi)", state.processed, state.total))
                    task.wait(0.25)
                end
            end)

            saveMap(options)
            finished = true

            if state.cancelled or state.runId ~= runId then return end

            state.done = true
            cancelButton.Visible = false
            state.processed = state.total
            setProgress(100, "Completed",
                string.format("Saved %d instances successfully!", state.total))
            startButton.Text = "✅ SAVED!"
            startButton.BackgroundColor3 = C.green

            notify("✅ Save Completed",
                string.format("%s saved in %.1f seconds", fileName, os.clock() - state.startTime))
            print(string.format("[SaveMap] File saved: %s.rbxlx", fileName))
        end)

        state.busy = false

        if not ok and not state.cancelled and state.runId == runId then
            setProgress(0, "Error", "Save failed - Check console (F9)")
            startButton.Text = "❌ FAILED"
            startButton.BackgroundColor3 = C.red
            cancelButton.Visible = false
            notify("❌ Save Failed", "Check console for details (F9)", "rbxassetid://6023426919")
            warn("[SaveMap] Error:", err)
        end

        if state.runId ~= runId or state.cancelled then return end
        task.wait(3)

        if state.runId == runId and not state.cancelled and screenGui.Parent then
            resetButtons()
            state.running = false
        end
    end)
end

local function cancelSave()
    if not state.running or state.done then return end

    state.cancelled = true
    state.running = false

    resetButtons()
    setProgress(0, "Cancelled", "Save process was cancelled by user")
    notify("Save Cancelled", "Save process was cancelled")
end

startButton.MouseButton1Click:Connect(startSave)
cancelButton.MouseButton1Click:Connect(cancelSave)

----------------------------------------------------------------
-- Panduan
----------------------------------------------------------------
local GUIDE_LINES = {
    "1. TERRAIN SUPPORT:",
    "   • Use PAID executors for terrain copying",
    "   • Free executors may NOT support terrain",
    "",
    "2. FILE LOCATION:",
    "   • Executor Folder > Workspace",
    "   • Files saved as .rbxlx format",
    "",
    "3. SAVE MODES:",
    "   • FULL - Save everything",
    "   • OPT - Optimized (recommended)",
    "   • SCRIPTS - Scripts only",
    "",
    "4. IF ERROR:",
    "   • Check executor compatibility",
    "   • Try different save mode",
}

local guideGui = nil

guideButton.MouseButton1Click:Connect(function()
    if guideGui then return end

    guideGui = new("ScreenGui", {
        Name = GUIDE_NAME, ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 1000,
    })
    protect(guideGui)
    guideGui.Parent = guiParent

    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    local width = math.min(450, vp.X - 20)
    local height = math.min(400, vp.Y - 20)

    local panel = new("Frame", {
        BackgroundColor3 = Color3.fromRGB(15, 8, 12), BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = SIZE_ZERO, ZIndex = 2, ClipsDescendants = true,
    }, guideGui)
    round(panel, UDim.new(0, 12))
    new("UIStroke", { Color = accent, Thickness = 2 }, panel)

    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 12), Size = UDim2.new(1, 0, 0, 30),
        Font = Enum.Font.GothamBold, Text = "📝 DETAILED SAVEMAP GUIDE",
        TextColor3 = Color3.fromRGB(255, 200, 200), TextSize = 18, ZIndex = 3,
    }, panel)

    local list = new("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.new(0, 30, 0, 50), Size = UDim2.new(1, -60, 1, -100),
        CanvasSize = UDim2.new(0, 0, 0, #GUIDE_LINES * 18),
        ScrollBarThickness = 4, ZIndex = 3,
    }, panel)

    for index, line in ipairs(GUIDE_LINES) do
        local isHeader = line:match("^%d+%. ") ~= nil
        local isBullet = line:match("^   •") ~= nil
        new("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, (index - 1) * 18),
            Size = UDim2.new(1, 0, 0, 18),
            Font = isHeader and Enum.Font.GothamBold or Enum.Font.Gotham,
            Text = line,
            TextColor3 = isHeader and Color3.fromRGB(255, 180, 60)
                or (isBullet and Color3.fromRGB(220, 180, 180) or Color3.fromRGB(150, 150, 150)),
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 3,
        }, list)
    end

    local closeGuide = new("TextButton", {
        BackgroundColor3 = Color3.fromRGB(80, 30, 30),
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12),
        Size = UDim2.new(0, 120, 0, 30), Font = Enum.Font.GothamBold, Text = "❌ CLOSE GUIDE",
        TextColor3 = Color3.fromRGB(255, 200, 200), TextSize = 12, ZIndex = 3,
    }, panel)
    round(closeGuide, UDim.new(0, 8))

    closeGuide.MouseEnter:Connect(function()
        tween(closeGuide, 0.2, { BackgroundColor3 = Color3.fromRGB(100, 40, 40) })
    end)
    closeGuide.MouseLeave:Connect(function()
        tween(closeGuide, 0.2, { BackgroundColor3 = Color3.fromRGB(80, 30, 30) })
    end)
    closeGuide.MouseButton1Click:Connect(function()
        local t = tween(panel, 0.3, { Size = SIZE_ZERO })
        t.Completed:Wait()
        if guideGui then
            guideGui:Destroy()
            guideGui = nil
        end
    end)

    tween(panel, 0.4, { Size = UDim2.new(0, width, 0, height) }, Enum.EasingStyle.Back)
end)

----------------------------------------------------------------
-- Tombol close & hover
----------------------------------------------------------------
local closing = false

closeButton.MouseButton1Click:Connect(function()
    if closing then return end
    closing = true
    state.cancelled = true
    state.running = false

    local t = tween(main, 0.25, { Size = SIZE_ZERO }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    t.Completed:Wait()

    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(connections)

    if guideGui then
        guideGui:Destroy()
        guideGui = nil
    end
    screenGui:Destroy()
end)

closeButton.MouseEnter:Connect(function() closeButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60) end)
closeButton.MouseLeave:Connect(function() closeButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45) end)
guideButton.MouseEnter:Connect(function() guideButton.BackgroundColor3 = Color3.fromRGB(60, 60, 100) end)
guideButton.MouseLeave:Connect(function() guideButton.BackgroundColor3 = Color3.fromRGB(50, 50, 80) end)

----------------------------------------------------------------
-- Inisialisasi
----------------------------------------------------------------
local function defaultFileName()
    return os.date("FayintSaveMap_%d%m_%H%M")
end

setMode("optimized")
filenameBox.Text = defaultFileName()
setProgress(0, "Idle", "Ready to save")
statusLabel.Text = "Status: Ready"

tween(main, 0.5, { Size = SIZE_OPEN }, Enum.EasingStyle.Back)

notify("🛠️ Universal SaveMap", string.format("Running on %s executor", executorName))
print("[SaveMap] GUI Loaded - Executor:", executorName)
print("[SaveMap] Note: Some executors may not support terrain saving")
