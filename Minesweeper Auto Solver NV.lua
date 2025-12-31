local player = game.Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local success, Controls = pcall(function() 
    return require(player.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
end)

local settings = {
    currentTab = "rage",
    isAutoSolving = false,
    isLegitActive = false,
    isWaitingForRound = false,
    freezeEnabled = true,
    autoGuess = true,
    actionDelay = 0.1,
    startDelayTime = 10,
    calculateDelay = 0.3,
    calculationMode = "euler",
    accentColor = Color3.fromRGB(130, 90, 255),
    bgColor = Color3.fromRGB(20, 20, 25),
    secColor = Color3.fromRGB(30, 30, 35)
}

local calcOnceTriggered = false 
local waitTimeLeft = 0
local neighborCache = {}
local highlightCache = {}
local lastActionTime, lastCalcTime, lastNotifyTime = tick(), 0, 0
local isGuessing, stopCurrentExecution = false, false
local riskyCells = {}

local function getSafeParent()
    if gethui then return gethui() end
    if player:FindFirstChild("PlayerGui") then return player.PlayerGui end
    return game:GetService("CoreGui")
end

for _, name in pairs({"autosolver_euler", "autosolver_final", "autosolver", "AutosolverUI"}) do
    local p = getSafeParent()
    if p and p:FindFirstChild(name) then p[name]:Destroy() end
    if player.PlayerGui:FindFirstChild(name) then player.PlayerGui[name]:Destroy() end
end

local function safeTween(obj, props, time)
    if not obj or not obj.Parent then return end
    task.spawn(function()
        local successTween = pcall(function()
            local info = TweenInfo.new(time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local t = TweenService:Create(obj, info, props)
            t:Play()
        end)
        if not successTween then
            for p, v in pairs(props) do
                pcall(function() obj[p] = v end)
            end
        end
    end)
end

local function chatNotify(msg)
    if tick() - lastNotifyTime < 0.5 then return end 
    lastNotifyTime = tick()
    pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local channel = TextChatService:FindFirstChild("TextChannels") and TextChatService.TextChannels:FindFirstChild("RBXSystem")
            if channel then 
                channel:DisplaySystemMessage("<b><font color='#825AFF'>[autosolver]</font>: " .. msg .. "</b>") 
                return 
            end
        end
        StarterGui:SetCore("ChatMakeSystemMessage", {
            Text = "[autosolver]: " .. msg,
            Color = Color3.fromRGB(200, 200, 200),
            Font = Enum.Font.GothamBold,
            FontSize = Enum.FontSize.Size18
        })
    end)
end

local function isCellOpen(part)
    if not part or not part.Parent then return true end
    if part.Transparency > 0.5 then return true end
    if part:FindFirstChild("NumberGui") then return true end
    return (part.Color.R > 0.7 and part.Color.G > 0.7 and part.Color.B < 0.6)
end

local function clearCaches()
    neighborCache = {}
    highlightCache = {}
    isGuessing = false
end

local function handleDeath()
    if not settings.isAutoSolving and not settings.isLegitActive then return end
    local deathMsg = isGuessing and "didn't guess right." or "accidentally stepped on a mine/reset."
    chatNotify(deathMsg)
    stopCurrentExecution = true
    clearCaches()
end

local function setupChar(char)
    if not char then return end
    stopCurrentExecution = false
    local hum = char:WaitForChild("Humanoid", 10)
    if hum then hum.Died:Connect(handleDeath) end
end
if player.Character then setupChar(player.Character) end
player.CharacterAdded:Connect(setupChar)

local function updatePhysics()
    local char = player.Character
    if not char then return end
    local active = (settings.isAutoSolving and not settings.isWaitingForRound and settings.freezeEnabled and settings.currentTab == "rage")
    for _, p in ipairs(char:GetDescendants()) do 
        if p:IsA("BasePart") then 
            p.Anchored = active 
            if active then p.Velocity = Vector3.zero end
        end 
    end
    if Controls then
        if active then Controls:Disable() else Controls:Enable() end
    end
end

local function teleportTo(target)
    if stopCurrentExecution or not target or not target.Parent or isCellOpen(target) then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    if not stopCurrentExecution and settings.freezeEnabled and settings.currentTab == "rage" then
        for _, p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = false end end
        root.CFrame = target.CFrame * CFrame.new(0, 5, 0) 
        root.Velocity = Vector3.new(0, 0, 0)
        task.wait(0.01)
        updatePhysics()
    elseif not stopCurrentExecution then
        root.CFrame = target.CFrame * CFrame.new(0, 5, 0)
    end
end

local function getSolverData()
    local folder = workspace:FindFirstChild("Flag") and workspace.Flag:FindFirstChild("Parts")
    if not folder then return {} end
    local numberData = {}
    local allParts = folder:GetChildren()
    
    for _, cell in ipairs(allParts) do
        if not isCellOpen(cell) then continue end
        
        local label = cell:FindFirstChild("NumberGui") and cell.NumberGui:FindFirstChildOfClass("TextLabel")
        local val = (label and tonumber(label.Text)) or 0 
        
        if val == 0 then continue end
        
        if not neighborCache[cell] then
            local nbs = {}
            local pos = cell.Position
            local distCheck = (cell.Size.X * 1.8)
            for _, n in ipairs(allParts) do 
                if n ~= cell and (n.Position - pos).Magnitude < distCheck then 
                    table.insert(nbs, n) 
                end 
            end
            neighborCache[cell] = nbs
        end
        
        local hidden, mines = {}, 0
        for _, n in ipairs(neighborCache[cell]) do
            if not isCellOpen(n) then
                if n.Color == Color3.new(0,0,0) then 
                    mines = mines + 1 
                else 
                    table.insert(hidden, n) 
                end
            end
        end
        
        if #hidden > 0 then 
            table.insert(numberData, {obj = cell, eVal = val - mines, hidden = hidden}) 
        end
    end
    return numberData
end

function mainLoop()
    if stopCurrentExecution then return end
    
    if settings.currentTab == "legit" and settings.isLegitActive and not calcOnceTriggered then
        if tick() - lastCalcTime < settings.calculateDelay then return end
    end
    
    if (not settings.isAutoSolving and not settings.isLegitActive and not calcOnceTriggered) or settings.isWaitingForRound then return end
    
    lastCalcTime = tick()
    local data = getSolverData()
    local safeQueue, mineQueue = {}, {}
    riskyCells = {}
    local foundAnything = false

    for i = 1, #data do
        for j = 1, #data do
            if i ~= j then
                local d1, d2 = data[i], data[j]
                if (d1.obj.Position - d2.obj.Position).Magnitude < 12 then
                    local s1, s2 = d1.hidden, d2.hidden
                    if #s2 > #s1 then
                        local isSubset = true
                        for _, x in ipairs(s1) do
                            local found = false
                            for _, y in ipairs(s2) do if x == y then found = true; break end end
                            if not found then isSubset = false; break end
                        end
                        
                        if isSubset then
                            local diffMines = d2.eVal - d1.eVal
                            local diffCells = {}
                            for _, x in ipairs(s2) do
                                local inS1 = false
                                for _, y in ipairs(s1) do if x == y then inS1 = true; break end end
                                if not inS1 then table.insert(diffCells, x) end
                            end
                            if diffMines == 0 then
                                for _, n in ipairs(diffCells) do table.insert(safeQueue, n); foundAnything = true end
                            elseif diffMines == #diffCells then
                                for _, n in ipairs(diffCells) do table.insert(mineQueue, n); foundAnything = true end
                            end
                        end
                    end
                end
            end
        end
    end

    local basicSafe, basicMines = {}, {}
    for _, d in ipairs(data) do
        if #d.hidden > 0 then
            if #d.hidden == d.eVal then
                for _, n in ipairs(d.hidden) do table.insert(basicMines, n); foundAnything = true end
            elseif d.eVal <= 0 then
                for _, n in ipairs(d.hidden) do table.insert(basicSafe, n); foundAnything = true end
            end
        end
    end

    if settings.currentTab == "rage" and settings.isAutoSolving then
        for _, m in ipairs(mineQueue) do m.Color = Color3.new(0,0,0) end
        for _, m in ipairs(basicMines) do m.Color = Color3.new(0,0,0) end
        
        local targetQueue = #safeQueue > 0 and safeQueue or basicSafe
        if #targetQueue > 0 then
            isGuessing = false
            for _, s in ipairs(targetQueue) do 
                if stopCurrentExecution or not settings.isAutoSolving then break end 
                if not isCellOpen(s) then teleportTo(s); task.wait(settings.actionDelay) end
            end
        elseif settings.autoGuess and not foundAnything and tick() - lastActionTime > 0.8 then
            for _, d in ipairs(data) do 
                for _, n in ipairs(d.hidden) do 
                    if n.Color ~= Color3.new(0,0,0) then 
                        riskyCells[n] = (riskyCells[n] or 0) + 1 
                    end 
                end 
            end
            local best, maxW = nil, -1
            for c, w in pairs(riskyCells) do if w > maxW then maxW = w; best = c end end
            if best then isGuessing = true; teleportTo(best); lastActionTime = tick() end
        end
        
    elseif (settings.currentTab == "legit" and settings.isLegitActive) or calcOnceTriggered then
        local finalMines = (settings.calculationMode == "euler" and #mineQueue > 0) and mineQueue or basicMines
        local finalSafe = (settings.calculationMode == "euler" and #safeQueue > 0) and safeQueue or basicSafe
        
        local Black = Color3.new(0, 0, 0)
        local White = Color3.new(1, 1, 1)

        for _, m in ipairs(finalMines) do 
            if highlightCache[m] ~= "mine" then
                m.Color = Black
                highlightCache[m] = "mine"
            end
        end
        for _, s in ipairs(finalSafe) do 
            if highlightCache[s] ~= "safe" then
                s.Color = White
                highlightCache[s] = "safe"
            end
        end
        calcOnceTriggered = false
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutosolverUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = getSafeParent()

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 480, 0, 320)
mainFrame.Position = UDim2.new(0.5, -240, 0.4, -160)
mainFrame.BackgroundColor3 = settings.bgColor
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui

local openFrame = Instance.new("TextButton")
openFrame.Name = "OpenButton"
openFrame.Size = UDim2.new(0, 100, 0, 30)
openFrame.Position = UDim2.new(0.5, -50, 0, 10)
openFrame.BackgroundColor3 = settings.secColor
openFrame.Text = "OPEN"
openFrame.Font = Enum.Font.GothamBold
openFrame.TextColor3 = settings.accentColor
openFrame.Visible = false
openFrame.Parent = screenGui
local opCorner = Instance.new("UICorner", openFrame); opCorner.CornerRadius = UDim.new(0, 8)

local function toggleUI(state)
    mainFrame.Visible = state
    openFrame.Visible = not state
end

openFrame.MouseButton1Click:Connect(function() toggleUI(true) end)

UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.LeftControl then
        toggleUI(not mainFrame.Visible)
    end
end)

local uiCorner = Instance.new("UICorner", mainFrame)
uiCorner.CornerRadius = UDim.new(0, 10)

local uiStroke = Instance.new("UIStroke", mainFrame)
uiStroke.Color = Color3.fromRGB(60, 60, 70)
uiStroke.Thickness = 1

local sidebar = Instance.new("Frame", mainFrame)
sidebar.Size = UDim2.new(0, 130, 1, 0)
sidebar.BackgroundColor3 = settings.secColor
sidebar.BorderSizePixel = 0
local sideCorner = Instance.new("UICorner", sidebar)
sideCorner.CornerRadius = UDim.new(0, 10)
local sideFix = Instance.new("Frame", sidebar) 
sideFix.Size = UDim2.new(0, 15, 1, 0)
sideFix.Position = UDim2.new(1, -10, 0, 0)
sideFix.BackgroundColor3 = settings.secColor
sideFix.BorderSizePixel = 0

local closeRow = Instance.new("Frame", sidebar)
closeRow.Size = UDim2.new(1, 0, 0, 35)
closeRow.BackgroundTransparency = 1

local closeBtn = Instance.new("TextButton", closeRow)
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(0.5, -16, 0.5, -16) 
closeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
closeBtn.Text = "❌"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.TextSize = 22
closeBtn.Font = Enum.Font.GothamBold
local cBtnCorner = Instance.new("UICorner", closeBtn); cBtnCorner.CornerRadius = UDim.new(0, 6)

closeBtn.MouseButton1Click:Connect(function() toggleUI(false) end)

local titleLbl = Instance.new("TextLabel", sidebar)
titleLbl.Size = UDim2.new(1, -20, 0, 30)
titleLbl.Position = UDim2.new(0, 10, 0, 40) 
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "AUTOSOLVER"
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextColor3 = settings.accentColor
titleLbl.TextSize = 16

local creditLbl = Instance.new("TextLabel", sidebar)
creditLbl.Size = UDim2.new(1, 0, 0, 15)
creditLbl.Position = UDim2.new(0, 0, 1, -25)
creditLbl.BackgroundTransparency = 1
creditLbl.Text = "@andrew12e"
creditLbl.Font = Enum.Font.Code
creditLbl.TextColor3 = Color3.fromRGB(100, 100, 100)
creditLbl.TextSize = 10

local tabContainer = Instance.new("Frame", sidebar)
tabContainer.Size = UDim2.new(1, 0, 1, -90)
tabContainer.Position = UDim2.new(0, 0, 0, 80) 
tabContainer.BackgroundTransparency = 1

local layout = Instance.new("UIListLayout", tabContainer)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local content = Instance.new("Frame", mainFrame)
content.Size = UDim2.new(1, -130, 1, 0)
content.Position = UDim2.new(0, 130, 0, 0)
content.BackgroundTransparency = 1

local ragePage = Instance.new("Frame", content)
ragePage.Size = UDim2.new(1, -20, 1, -20)
ragePage.Position = UDim2.new(0, 10, 0, 10)
ragePage.BackgroundTransparency = 1

local legitPage = Instance.new("Frame", content)
legitPage.Size = UDim2.new(1, -20, 1, -20)
legitPage.Position = UDim2.new(0, 10, 0, 10)
legitPage.BackgroundTransparency = 1
legitPage.Visible = false

local statusBtn = Instance.new("TextButton", content)
statusBtn.Size = UDim2.new(1, -30, 0, 40)
statusBtn.Position = UDim2.new(0, 15, 0, 15)
statusBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
statusBtn.Text = ""
statusBtn.AutoButtonColor = false
local sbCorner = Instance.new("UICorner", statusBtn); sbCorner.CornerRadius = UDim.new(0, 6)
local sbStroke = Instance.new("UIStroke", statusBtn); sbStroke.Color = Color3.fromRGB(60,60,70); sbStroke.Thickness = 1
local sbText = Instance.new("TextLabel", statusBtn)
sbText.Size = UDim2.new(1, 0, 1, 0)
sbText.BackgroundTransparency = 1
sbText.Text = "STATUS: OFF"
sbText.Font = Enum.Font.GothamBold
sbText.TextColor3 = Color3.fromRGB(200, 80, 80)
sbText.TextSize = 14

local function updateStatusVisual()
    task.spawn(function()
        if not statusBtn or not statusBtn.Parent or not sbText then return end
        
        local active = (settings.currentTab == "rage" and settings.isAutoSolving) or (settings.currentTab == "legit" and settings.isLegitActive)
        local txt, txtCol, bgCol
        
        if settings.isWaitingForRound then
            txt = "WAITING (" .. string.format("%.1f", waitTimeLeft) .. "s)"
            txtCol = Color3.fromRGB(255, 180, 50)
            bgCol = Color3.fromRGB(50, 40, 30)
        elseif active then
            txt = "ACTIVE - " .. string.upper(settings.currentTab)
            txtCol = Color3.fromRGB(100, 255, 100)
            bgCol = Color3.fromRGB(30, 50, 30)
        else
            txt = "STATUS: OFF"
            txtCol = Color3.fromRGB(255, 80, 80)
            bgCol = Color3.fromRGB(35, 35, 45)
        end
        
        pcall(function() sbText.Text = txt end)
        safeTween(sbText, {TextColor3 = txtCol})
        safeTween(statusBtn, {BackgroundColor3 = bgCol})
    end)
end

statusBtn.MouseButton1Click:Connect(function()
    if settings.currentTab == "rage" then
        settings.isAutoSolving = not settings.isAutoSolving
        settings.isWaitingForRound = false
    else
        settings.isLegitActive = not settings.isLegitActive
    end
    updatePhysics()
    updateStatusVisual()
end)

local function createTabBtn(name, parent, active)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1, -20, 0, 35)
    btn.BackgroundColor3 = active and settings.bgColor or settings.secColor
    btn.Text = name
    btn.Font = Enum.Font.GothamBold
    btn.TextColor3 = active and settings.accentColor or Color3.fromRGB(150, 150, 150)
    btn.TextSize = 12
    btn.AutoButtonColor = false
    
    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0, 6)
    
    return btn
end

local function createToggle(parent, text, yPos, value, callback)
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(1, 0, 0, 35)
    frame.Position = UDim2.new(0, 0, 0, yPos)
    frame.BackgroundTransparency = 1
    
    local lbl = Instance.new("TextLabel", frame)
    lbl.Text = text
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Size = UDim2.new(0.6, 0, 1, 0)
    lbl.Position = UDim2.new(0, 5, 0, 0)
    lbl.BackgroundTransparency = 1
    
    local switchBg = Instance.new("Frame", frame)
    switchBg.Size = UDim2.new(0, 44, 0, 22)
    switchBg.Position = UDim2.new(1, -50, 0.5, -11)
    switchBg.BackgroundColor3 = value and settings.accentColor or Color3.fromRGB(45, 45, 50)
    local sCorner = Instance.new("UICorner", switchBg); sCorner.CornerRadius = UDim.new(1, 0)
    
    local circle = Instance.new("Frame", switchBg)
    circle.Size = UDim2.new(0, 18, 0, 18)
    circle.Position = value and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    local cCorner = Instance.new("UICorner", circle); cCorner.CornerRadius = UDim.new(1, 0)
    
    local btn = Instance.new("TextButton", frame)
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    
    btn.MouseButton1Click:Connect(function()
        value = not value
        safeTween(switchBg, {BackgroundColor3 = value and settings.accentColor or Color3.fromRGB(45, 45, 50)})
        safeTween(circle, {Position = value and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)})
        callback(value)
    end)
end

local function createSlider(parent, text, yPos, min, max, default, callback)
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(1, 0, 0, 50)
    frame.Position = UDim2.new(0, 0, 0, yPos)
    frame.BackgroundTransparency = 1
    
    local lbl = Instance.new("TextLabel", frame)
    lbl.Text = text
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Size = UDim2.new(1, 0, 0, 20)
    lbl.Position = UDim2.new(0, 5, 0, 0)
    lbl.BackgroundTransparency = 1
    
    local valLbl = Instance.new("TextLabel", frame)
    valLbl.Text = tostring(default)
    valLbl.Font = Enum.Font.Code
    valLbl.TextColor3 = Color3.fromRGB(150, 150, 150)
    valLbl.TextSize = 11
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Size = UDim2.new(1, -10, 0, 20)
    valLbl.BackgroundTransparency = 1
    
    local barBg = Instance.new("Frame", frame)
    barBg.Size = UDim2.new(1, -10, 0, 4)
    barBg.Position = UDim2.new(0, 5, 0, 30)
    barBg.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    barBg.BorderSizePixel = 0
    local bCorner = Instance.new("UICorner", barBg); bCorner.CornerRadius = UDim.new(1, 0)
    
    local fill = Instance.new("Frame", barBg)
    fill.Size = UDim2.new((default - min)/(max - min), 0, 1, 0)
    fill.BackgroundColor3 = settings.accentColor
    fill.BorderSizePixel = 0
    local fCorner = Instance.new("UICorner", fill); fCorner.CornerRadius = UDim.new(1, 0)
    
    local btn = Instance.new("TextButton", frame)
    btn.Size = UDim2.new(1, 0, 0, 20)
    btn.Position = UDim2.new(0, 0, 0, 25)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    
    local dragging = false
    btn.MouseButton1Down:Connect(function() dragging = true end)
    UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local relative = math.clamp((input.Position.X - barBg.AbsolutePosition.X) / barBg.AbsoluteSize.X, 0, 1)
            local newVal = math.floor((min + (max - min) * relative) * 100) / 100
            safeTween(fill, {Size = UDim2.new(relative, 0, 1, 0)}, 0.05)
            valLbl.Text = tostring(newVal)
            callback(newVal)
        end
    end)
end

local btnRage = createTabBtn("RAGE", tabContainer, true)
local btnLegit = createTabBtn("LEGIT", tabContainer, false)

btnRage.MouseButton1Click:Connect(function()
    settings.currentTab = "rage"
    ragePage.Visible, legitPage.Visible = true, false
    safeTween(btnRage, {BackgroundColor3 = settings.bgColor, TextColor3 = settings.accentColor})
    safeTween(btnLegit, {BackgroundColor3 = settings.secColor, TextColor3 = Color3.fromRGB(150, 150, 150)})
    updatePhysics()
    updateStatusVisual()
end)

btnLegit.MouseButton1Click:Connect(function()
    settings.currentTab = "legit"
    ragePage.Visible, legitPage.Visible = false, true
    safeTween(btnLegit, {BackgroundColor3 = settings.bgColor, TextColor3 = settings.accentColor})
    safeTween(btnRage, {BackgroundColor3 = settings.secColor, TextColor3 = Color3.fromRGB(150, 150, 150)})
    updatePhysics()
    updateStatusVisual()
end)

createToggle(ragePage, "Freeze Character", 70, settings.freezeEnabled, function(v) settings.freezeEnabled = v; updatePhysics() end)
createToggle(ragePage, "Auto Guessing", 110, settings.autoGuess, function(v) settings.autoGuess = v end)
createSlider(ragePage, "Teleport Speed (Delay)", 160, 0.04, 1.0, settings.actionDelay, function(v) settings.actionDelay = v end)
createSlider(ragePage, "Start Delay (Seconds)", 220, 0, 30, settings.startDelayTime, function(v) settings.startDelayTime = v end)

createSlider(legitPage, "Calculation Delay", 70, 0.1, 5.0, settings.calculateDelay, function(v) settings.calculateDelay = v end)

player.CharacterAdded:Connect(function()
    if settings.isAutoSolving or settings.isLegitActive then
        settings.isWaitingForRound = true
        waitTimeLeft = settings.startDelayTime
        updateStatusVisual()
        clearCaches()
        
        task.spawn(function()
            while waitTimeLeft > 0 do 
                updateStatusVisual()
                task.wait(0.1)
                waitTimeLeft = waitTimeLeft - 0.1 
            end
            settings.isWaitingForRound = false
            neighborCache = {}
            highlightCache = {}
            updatePhysics()
            updateStatusVisual()
        end)
    end
end)

updateStatusVisual()

task.spawn(function()
    while true do 
        pcall(mainLoop)
        task.wait(0.01) 
    end 
end)

chatNotify("Loaded...")
