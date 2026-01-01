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
    freezeEnabled = false, -- По умолчанию выключено
    autoGuess = true,
    actionDelay = 0.1,
    startDelayTime = 10,
    calculateDelay = 0.3,
    accentColor = Color3.fromRGB(130, 90, 255),
    bgColor = Color3.fromRGB(20, 20, 25),
    secColor = Color3.fromRGB(30, 30, 35),
    pathfindingEnabled = false,
    humanization = 0.5
}

local waitTimeLeft = 0
local neighborCache = {}
local highlightCache = {}
local lastCalcTime, lastNotifyTime = 0, 0
local isGuessing, stopCurrentExecution = false, false
local isWalking = false

local VisualsFolder = workspace:FindFirstChild("AutosolverVisuals") or Instance.new("Folder")
VisualsFolder.Name = "AutosolverVisuals"
VisualsFolder.Parent = workspace

local function getSafeParent()
    if gethui then return gethui() end
    return game:GetService("CoreGui")
end

for _, name in pairs({"autosolver_euler", "autosolver_final", "autosolver", "AutosolverUI"}) do
    pcall(function() getSafeParent()[name]:Destroy() end)
    pcall(function() player.PlayerGui[name]:Destroy() end)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function randomInRange(min, max)
    return min + math.random() * (max - min)
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
        StarterGui:SetCore("ChatMakeSystemMessage", {Text = "[autosolver]: " .. msg, Color = Color3.fromRGB(200, 200, 200)})
    end)
end

local function isCellOpen(part)
    if not part or not part.Parent then return true end
    if part.Transparency > 0.5 then return true end
    if part:FindFirstChild("NumberGui") then return true end
    return (part.Color.R > 0.7 and part.Color.G > 0.7 and part.Color.B < 0.6)
end

local function isMine(part)
    return part and part.Parent and part.Color == Color3.new(0, 0, 0)
end

local function isSafeMarked(part)
    return part and part.Parent and part.Color == Color3.new(1, 1, 1)
end

local function clearVisuals()
    VisualsFolder:ClearAllChildren()
end

local function clearCaches()
    neighborCache, highlightCache = {}, {}
    isGuessing, isWalking = false, false
    clearVisuals()
end

local function handleDeath()
    if not settings.isAutoSolving and not settings.isLegitActive then return end
    chatNotify(isGuessing and "didn't guess right." or "stepped on a mine.")
    stopCurrentExecution = true
    clearCaches()
end

local function setupChar(char)
    if not char then return end
    stopCurrentExecution, isWalking = false, false
    local hum = char:WaitForChild("Humanoid", 10)
    if hum then 
        hum.Died:Connect(handleDeath)
        hum.AutoJumpEnabled = false 
    end
end

if player.Character then setupChar(player.Character) end
player.CharacterAdded:Connect(setupChar)

local function updatePhysics()
    local char = player.Character
    if not char then return end
    local active = settings.isAutoSolving and not settings.isWaitingForRound and settings.freezeEnabled and settings.currentTab == "rage"
    for _, p in ipairs(char:GetDescendants()) do 
        if p:IsA("BasePart") then 
            p.Anchored = active 
        end 
    end
    if Controls then
        if active then Controls:Disable() else Controls:Enable() end
    end
end

local function getPartsFolder()
    local flag = workspace:FindFirstChild("Flag")
    return flag and flag:FindFirstChild("Parts")
end

local function getOpenCells()
    local folder = getPartsFolder()
    if not folder then return {} end
    local open = {}
    for _, cell in ipairs(folder:GetChildren()) do
        if isCellOpen(cell) and not isMine(cell) then
            table.insert(open, cell)
        end
    end
    return open
end

local function createPathVisuals(path, target)
    clearVisuals()
    
    if target then
        local redBall = Instance.new("SphereHandleAdornment")
        redBall.Name = "TargetBall"
        redBall.Adornee = target
        redBall.Radius = 1.5
        redBall.Color3 = Color3.fromRGB(255, 50, 50)
        redBall.Transparency = 0.2
        redBall.AlwaysOnTop = true
        redBall.ZIndex = 5
        redBall.Parent = VisualsFolder
    end
    
    if path then
        for i, cell in ipairs(path) do
            local blueBall = Instance.new("SphereHandleAdornment")
            blueBall.Name = "PathBall_" .. i
            blueBall.Adornee = cell
            blueBall.Radius = 0.7
            blueBall.Color3 = Color3.fromRGB(0, 150, 255)
            blueBall.Transparency = 0.3
            blueBall.AlwaysOnTop = true
            blueBall.ZIndex = 4
            blueBall.Parent = VisualsFolder
        end
    end
end

local function getNeighbors(cell, allCells)
    local neighbors = {}
    local p1 = cell.Position
    local size = cell.Size.X
    local maxDist = size * 1.2
    
    for _, other in ipairs(allCells) do
        if other == cell then continue end
        local p2 = other.Position
        
        local dx = math.abs(p1.X - p2.X)
        local dz = math.abs(p1.Z - p2.Z)
        
        local alignedX = dx < 1
        local alignedZ = dz < 1
        
        if not alignedX and not alignedZ then continue end
        
        local dist = math.sqrt(dx*dx + dz*dz)
        if dist < maxDist and dist > 0.1 then
            table.insert(neighbors, other)
        end
    end
    return neighbors
end

local function findPathAStar(startCell, targetCell, openCells)
    if not startCell or not targetCell then return nil end
    if startCell == targetCell then return {startCell} end
    
    local openSet = {startCell}
    local closedSet = {}
    local cameFrom = {}
    local gScore = {}
    local fScore = {}
    
    gScore[startCell] = 0
    fScore[startCell] = (startCell.Position - targetCell.Position).Magnitude
    
    local iterations = 0
    
    while #openSet > 0 and iterations < 500 do
        iterations = iterations + 1
        
        local current = nil
        local lowestF = math.huge
        local currentIdx = 0
        
        for i, node in ipairs(openSet) do
            local f = fScore[node] or math.huge
            if f < lowestF then
                lowestF = f
                current = node
                currentIdx = i
            end
        end
        
        if current == targetCell then
            local path = {}
            local node = current
            while node do
                table.insert(path, 1, node)
                node = cameFrom[node]
            end
            return path
        end
        
        table.remove(openSet, currentIdx)
        closedSet[current] = true
        
        local neighbors = getNeighbors(current, openCells)
        
        for _, neighbor in ipairs(neighbors) do
            if closedSet[neighbor] then continue end
            
            local moveCost = (current.Position - neighbor.Position).Magnitude
            local tentativeG = (gScore[current] or math.huge) + moveCost
            
            if tentativeG < (gScore[neighbor] or math.huge) then
                cameFrom[neighbor] = current
                gScore[neighbor] = tentativeG
                fScore[neighbor] = tentativeG + (neighbor.Position - targetCell.Position).Magnitude
                
                local inOpen = false
                for _, n in ipairs(openSet) do
                    if n == neighbor then inOpen = true break end
                end
                if not inOpen then
                    table.insert(openSet, neighbor)
                end
            end
        end
    end
    
    return nil
end

local function findClosestCell(position, cells)
    local closest, closestDist = nil, math.huge
    for _, cell in ipairs(cells) do
        local dist = (cell.Position - position).Magnitude
        if dist < closestDist then
            closestDist, closest = dist, cell
        end
    end
    return closest
end

local function getAllSafeTargets()
    local folder = getPartsFolder()
    if not folder then return {} end
    local targets = {}
    for _, cell in ipairs(folder:GetChildren()) do
        if isSafeMarked(cell) and not isCellOpen(cell) then
            table.insert(targets, cell)
        end
    end
    return targets
end

local function getAdjacentOpenCell(targetCell, openCells)
    local size = targetCell.Size.X
    local maxDist = size * 1.2
    local closest, closestDist = nil, math.huge
    
    for _, cell in ipairs(openCells) do
        local dist = (cell.Position - targetCell.Position).Magnitude
        if dist < maxDist and dist < closestDist then
            closestDist = dist
            closest = cell
        end
    end
    return closest
end

local function findBestTarget(rootPos, openCells)
    local targets = getAllSafeTargets()
    if #targets == 0 then return nil, nil end
    
    table.sort(targets, function(a, b)
        return (a.Position - rootPos).Magnitude < (b.Position - rootPos).Magnitude
    end)
    
    local startCell = findClosestCell(rootPos, openCells)
    if not startCell then return nil, nil end
    
    for _, target in ipairs(targets) do
        local adjacentCell = getAdjacentOpenCell(target, openCells)
        if adjacentCell then
            local path = findPathAStar(startCell, adjacentCell, openCells)
            if path then
                return target, path
            end
        end
    end
    
    return nil, nil
end

local function getHumanOffset(intensity)
    local angle = math.random() * math.pi * 2
    local distance = math.random() * 1.0 * intensity
    return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function walkPath(path, targetCell)
    if not path or #path == 0 then return false end
    
    local char = player.Character
    local humanoid = char and char:FindFirstChild("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return false end
    
    isWalking = true
    createPathVisuals(path, targetCell)
    
    local h = settings.humanization
    local baseSpeed = 16
    
    if h > 0 then
        task.wait(randomInRange(0.02, 0.15) * h)
    end
    
    local startIdx = 1
    if #path > 1 and (root.Position - path[1].Position).Magnitude < 3 then
        startIdx = 2
    end
    
    for i = startIdx, #path do
        if stopCurrentExecution or not settings.isLegitActive or not settings.pathfindingEnabled then
            humanoid.WalkSpeed = baseSpeed
            isWalking = false
            clearVisuals()
            return false
        end
        
        local cell = path[i]
        local isLastPoint = (i == #path)
        
        local walkSpeed = baseSpeed + randomInRange(-2, 2) * h
        humanoid.WalkSpeed = math.clamp(walkSpeed, 12, 18)
        
        local offset = getHumanOffset(h * 0.3)
        local targetPos = cell.Position + offset
        
        humanoid:MoveTo(targetPos)
        
        local acceptanceRadius = isLastPoint and 1.0 or 2.0
        
        local startTime = tick()
        while tick() - startTime < 5 do
            if stopCurrentExecution or not settings.isLegitActive or not settings.pathfindingEnabled then
                humanoid.WalkSpeed = baseSpeed
                isWalking = false
                clearVisuals()
                return false
            end
            
            local currentPos = Vector3.new(root.Position.X, 0, root.Position.Z)
            local destPos = Vector3.new(targetPos.X, 0, targetPos.Z)
            local dist = (currentPos - destPos).Magnitude
            
            if dist < acceptanceRadius then
                break
            end
            
            humanoid:MoveTo(targetPos)
            RunService.Heartbeat:Wait()
        end
        
        if h > 0 and i < #path then
            task.wait(randomInRange(0.01, 0.05) * h)
        end
    end
    
    if targetCell then
        humanoid:MoveTo(targetCell.Position)
        local startTime = tick()
        while tick() - startTime < 3 do
            if stopCurrentExecution or not settings.isLegitActive then break end
            if isCellOpen(targetCell) then break end
            
            local currentPos = Vector3.new(root.Position.X, 0, root.Position.Z)
            local destPos = Vector3.new(targetCell.Position.X, 0, targetCell.Position.Z)
            if (currentPos - destPos).Magnitude < 1.5 then
                task.wait(0.2)
                break
            end
            RunService.Heartbeat:Wait()
        end
    end
    
    if h > 0 then
        task.wait(randomInRange(0.05, 0.2) * h)
    end
    
    humanoid.WalkSpeed = baseSpeed
    isWalking = false
    clearVisuals()
    return true
end

local function doPathfinding()
    if isWalking or not settings.pathfindingEnabled or not settings.isLegitActive then return end
    
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    local openCells = getOpenCells()
    if #openCells == 0 then return end
    
    local target, path = findBestTarget(root.Position, openCells)
    if not target or not path then return end
    
    task.spawn(function()
        walkPath(path, target)
    end)
end

local function teleportTo(target)
    if stopCurrentExecution or not target or not target.Parent or isCellOpen(target) then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    for _, p in ipairs(char:GetDescendants()) do 
        if p:IsA("BasePart") then p.Anchored = false end 
    end
    root.CFrame = target.CFrame * CFrame.new(0, 5, 0)
    task.wait(0.01)
    updatePhysics()
end

local function getSolverData()
    local folder = getPartsFolder()
    if not folder then return {} end
    
    local numberData = {}
    local allParts = folder:GetChildren()
    
    for _, cell in ipairs(allParts) do
        if not isCellOpen(cell) then continue end
        
        local label = cell:FindFirstChild("NumberGui") and cell.NumberGui:FindFirstChildOfClass("TextLabel")
        local val = label and tonumber(label.Text) or 0
        if val == 0 then continue end
        
        if not neighborCache[cell] then
            local nbs = {}
            local pos, dist = cell.Position, cell.Size.X * 1.8
            for _, n in ipairs(allParts) do 
                if n ~= cell and (n.Position - pos).Magnitude < dist then 
                    table.insert(nbs, n) 
                end 
            end
            neighborCache[cell] = nbs
        end
        
        local hidden, mines = {}, 0
        for _, n in ipairs(neighborCache[cell]) do
            if not isCellOpen(n) then
                if isMine(n) then mines = mines + 1 
                else table.insert(hidden, n) end
            end
        end
        
        if #hidden > 0 then 
            table.insert(numberData, {obj = cell, eVal = val - mines, hidden = hidden}) 
        end
    end
    return numberData
end

local function solve()
    if stopCurrentExecution or settings.isWaitingForRound then return end
    if not settings.isAutoSolving and not settings.isLegitActive then return end
    if tick() - lastCalcTime < settings.calculateDelay then return end
    
    lastCalcTime = tick()
    local data = getSolverData()
    local safeQueue, mineQueue = {}, {}
    local foundAnything = false

    for i = 1, #data do
        for j = 1, #data do
            if i == j then continue end
            local d1, d2 = data[i], data[j]
            if (d1.obj.Position - d2.obj.Position).Magnitude > 12 then continue end
            
            local s1, s2 = d1.hidden, d2.hidden
            if #s2 <= #s1 then continue end
            
            local isSubset = true
            for _, x in ipairs(s1) do
                local found = false
                for _, y in ipairs(s2) do 
                    if x == y then found = true break end 
                end
                if not found then isSubset = false break end
            end
            
            if isSubset then
                local diffMines = d2.eVal - d1.eVal
                local diffCells = {}
                for _, x in ipairs(s2) do
                    local inS1 = false
                    for _, y in ipairs(s1) do 
                        if x == y then inS1 = true break end 
                    end
                    if not inS1 then table.insert(diffCells, x) end
                end
                
                if diffMines == 0 then
                    for _, n in ipairs(diffCells) do safeQueue[n] = true end
                    foundAnything = true
                elseif diffMines == #diffCells then
                    for _, n in ipairs(diffCells) do mineQueue[n] = true end
                    foundAnything = true
                end
            end
        end
    end

    for _, d in ipairs(data) do
        if #d.hidden == d.eVal then
            for _, n in ipairs(d.hidden) do mineQueue[n] = true end
            foundAnything = true
        elseif d.eVal <= 0 then
            for _, n in ipairs(d.hidden) do safeQueue[n] = true end
            foundAnything = true
        end
    end

    for m in pairs(mineQueue) do 
        if m and m.Parent then m.Color = Color3.new(0, 0, 0) end
    end

    if settings.currentTab == "rage" and settings.isAutoSolving then
        for s in pairs(safeQueue) do 
            if stopCurrentExecution or not settings.isAutoSolving then break end 
            if not isCellOpen(s) and not isMine(s) then 
                teleportTo(s)
                task.wait(settings.actionDelay) 
            end
        end
        
        if settings.autoGuess and not foundAnything then
            local riskyCells = {}
            for _, d in ipairs(data) do 
                for _, n in ipairs(d.hidden) do 
                    if not isMine(n) then 
                        riskyCells[n] = (riskyCells[n] or 0) + 1 
                    end 
                end 
            end
            local best, maxW = nil, -1
            for c, w in pairs(riskyCells) do 
                if w > maxW then maxW, best = w, c end 
            end
            if best then 
                isGuessing = true
                teleportTo(best)
            end
        end
        
    elseif settings.currentTab == "legit" and settings.isLegitActive then
        for s in pairs(safeQueue) do 
            if s and s.Parent and highlightCache[s] ~= "safe" then
                s.Color = Color3.new(1, 1, 1)
                highlightCache[s] = "safe"
            end
        end
        
        if settings.pathfindingEnabled and not isWalking then
            doPathfinding()
        end
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutosolverUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = getSafeParent()

local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 480, 0, 360)
mainFrame.Position = UDim2.new(0.5, -240, 0.4, -180)
mainFrame.BackgroundColor3 = settings.bgColor
mainFrame.Active, mainFrame.Draggable = true, true
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)
Instance.new("UIStroke", mainFrame).Color = Color3.fromRGB(60, 60, 70)

local openBtn = Instance.new("TextButton", screenGui)
openBtn.Size = UDim2.new(0, 100, 0, 30)
openBtn.Position = UDim2.new(0.5, -50, 0, 10)
openBtn.BackgroundColor3 = settings.secColor
openBtn.Text = "OPEN"
openBtn.Font = Enum.Font.GothamBold
openBtn.TextColor3 = settings.accentColor
openBtn.Visible = false
Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0, 8)

local function toggleUI(state)
    mainFrame.Visible, openBtn.Visible = state, not state
end

openBtn.MouseButton1Click:Connect(function() toggleUI(true) end)
UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.LeftControl then
        toggleUI(not mainFrame.Visible)
    end
end)

local sidebar = Instance.new("Frame", mainFrame)
sidebar.Size = UDim2.new(0, 130, 1, 0)
sidebar.BackgroundColor3 = settings.secColor
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 10)

local closeBtn = Instance.new("TextButton", sidebar)
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(0.5, -16, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function() toggleUI(false) end)

local titleLbl = Instance.new("TextLabel", sidebar)
titleLbl.Size = UDim2.new(1, 0, 0, 30)
titleLbl.Position = UDim2.new(0, 0, 0, 45)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "AUTOSOLVER"
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextColor3 = settings.accentColor
titleLbl.TextSize = 14

local tabFrame = Instance.new("Frame", sidebar)
tabFrame.Size = UDim2.new(1, -20, 0, 120)
tabFrame.Position = UDim2.new(0, 10, 0, 85)
tabFrame.BackgroundTransparency = 1
Instance.new("UIListLayout", tabFrame).Padding = UDim.new(0, 8)

local function createTabBtn(name, active)
    local btn = Instance.new("TextButton", tabFrame)
    btn.Size = UDim2.new(1, 0, 0, 35)
    btn.BackgroundColor3 = active and settings.bgColor or settings.secColor
    btn.Text = name
    btn.Font = Enum.Font.GothamBold
    btn.TextColor3 = active and settings.accentColor or Color3.fromRGB(150, 150, 150)
    btn.TextSize = 12
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local btnRage = createTabBtn("RAGE", true)
local btnLegit = createTabBtn("LEGIT", false)
local btnSettings = createTabBtn("SETTINGS", false)

local content = Instance.new("Frame", mainFrame)
content.Size = UDim2.new(1, -140, 1, -20)
content.Position = UDim2.new(0, 135, 0, 10)
content.BackgroundTransparency = 1

local statusBtn = Instance.new("TextButton", content)
statusBtn.Size = UDim2.new(1, 0, 0, 40)
statusBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
statusBtn.Text = "STATUS: OFF"
statusBtn.Font = Enum.Font.GothamBold
statusBtn.TextColor3 = Color3.fromRGB(200, 80, 80)
statusBtn.TextSize = 14
Instance.new("UICorner", statusBtn).CornerRadius = UDim.new(0, 6)

local ragePage = Instance.new("Frame", content)
ragePage.Size = UDim2.new(1, 0, 1, -50)
ragePage.Position = UDim2.new(0, 0, 0, 50)
ragePage.BackgroundTransparency = 1

local legitPage = Instance.new("Frame", content)
legitPage.Size = UDim2.new(1, 0, 1, -50)
legitPage.Position = UDim2.new(0, 0, 0, 50)
legitPage.BackgroundTransparency = 1
legitPage.Visible = false

local settingsPage = Instance.new("Frame", content)
settingsPage.Size = UDim2.new(1, 0, 1, -50)
settingsPage.Position = UDim2.new(0, 0, 0, 50)
settingsPage.BackgroundTransparency = 1
settingsPage.Visible = false

local function updateStatus()
    local active = (settings.currentTab == "rage" and settings.isAutoSolving) or (settings.currentTab == "legit" and settings.isLegitActive)
    
    if settings.isWaitingForRound then
        statusBtn.Text = string.format("WAITING (%.2fs)", waitTimeLeft)
        statusBtn.TextColor3 = Color3.fromRGB(255, 180, 50)
        statusBtn.BackgroundColor3 = Color3.fromRGB(50, 40, 30)
    elseif isWalking then
        statusBtn.Text = "WALKING..."
        statusBtn.TextColor3 = Color3.fromRGB(100, 200, 255)
        statusBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 50)
    elseif active then
        statusBtn.Text = "ACTIVE - " .. string.upper(settings.currentTab)
        statusBtn.TextColor3 = Color3.fromRGB(100, 255, 100)
        statusBtn.BackgroundColor3 = Color3.fromRGB(30, 50, 30)
    else
        statusBtn.Text = "STATUS: OFF"
        statusBtn.TextColor3 = Color3.fromRGB(200, 80, 80)
        statusBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    end
end

statusBtn.MouseButton1Click:Connect(function()
    if settings.currentTab == "rage" then
        settings.isAutoSolving = not settings.isAutoSolving
    elseif settings.currentTab == "legit" then
        settings.isLegitActive = not settings.isLegitActive
        if not settings.isLegitActive then 
            isWalking = false 
            clearVisuals() 
        end
    end
    updatePhysics()
    updateStatus()
end)

local function createToggle(parent, text, yPos, value, callback)
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(1, 0, 0, 30)
    frame.Position = UDim2.new(0, 0, 0, yPos)
    frame.BackgroundTransparency = 1
    
    local lbl = Instance.new("TextLabel", frame)
    lbl.Size = UDim2.new(0.7, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    
    local toggle = Instance.new("TextButton", frame)
    toggle.Size = UDim2.new(0, 44, 0, 22)
    toggle.Position = UDim2.new(1, -50, 0.5, -11)
    toggle.BackgroundColor3 = value and settings.accentColor or Color3.fromRGB(45, 45, 50)
    toggle.Text = ""
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(1, 0)
    
    local circle = Instance.new("Frame", toggle)
    circle.Size = UDim2.new(0, 18, 0, 18)
    circle.Position = value and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    circle.BackgroundColor3 = Color3.new(1, 1, 1)
    Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)
    
    toggle.MouseButton1Click:Connect(function()
        value = not value
        TweenService:Create(toggle, TweenInfo.new(0.2), {BackgroundColor3 = value and settings.accentColor or Color3.fromRGB(45, 45, 50)}):Play()
        TweenService:Create(circle, TweenInfo.new(0.2), {Position = value and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)}):Play()
        callback(value)
    end)
end

local function createSlider(parent, text, yPos, min, max, default, callback)
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(1, 0, 0, 45)
    frame.Position = UDim2.new(0, 0, 0, yPos)
    frame.BackgroundTransparency = 1
    
    local lbl = Instance.new("TextLabel", frame)
    lbl.Size = UDim2.new(0.5, 0, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    
    local inputBox = Instance.new("TextBox", frame)
    inputBox.Size = UDim2.new(0, 60, 0, 20)
    inputBox.Position = UDim2.new(1, -65, 0, 0)
    inputBox.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    inputBox.Text = tostring(default)
    inputBox.Font = Enum.Font.Code
    inputBox.TextColor3 = Color3.fromRGB(200, 200, 200)
    inputBox.TextSize = 11
    inputBox.ClearTextOnFocus = false
    Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 4)
    
    local bar = Instance.new("Frame", frame)
    bar.Size = UDim2.new(1, 0, 0, 4)
    bar.Position = UDim2.new(0, 0, 0, 28)
    bar.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
    
    local fill = Instance.new("Frame", bar)
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = settings.accentColor
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
    
    local currentValue = default
    
    local function updateValue(val)
        val = math.clamp(val, min, max)
        val = math.floor(val * 100) / 100
        currentValue = val
        fill.Size = UDim2.new((val - min) / (max - min), 0, 1, 0)
        inputBox.Text = tostring(val)
        callback(val)
    end
    
    inputBox.FocusLost:Connect(function()
        local num = tonumber(inputBox.Text)
        if num then
            updateValue(num)
        else
            inputBox.Text = tostring(currentValue)
        end
    end)
    
    local dragging = false
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then 
            dragging = true 
            local rel = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local val = min + (max - min) * rel
            updateValue(val)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local rel = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local val = min + (max - min) * rel
            updateValue(val)
        end
    end)
end

createToggle(ragePage, "Freeze Character", 10, settings.freezeEnabled, function(v) settings.freezeEnabled = v updatePhysics() end)
createToggle(ragePage, "Auto Guessing", 45, settings.autoGuess, function(v) settings.autoGuess = v end)
createSlider(ragePage, "Teleport Delay", 90, 0.04, 1, settings.actionDelay, function(v) settings.actionDelay = v end)

createSlider(legitPage, "Calculation Delay", 10, 0.1, 5, settings.calculateDelay, function(v) settings.calculateDelay = v end)
createToggle(legitPage, "Auto Walk", 65, settings.pathfindingEnabled, function(v) 
    settings.pathfindingEnabled = v 
    if not v then 
        isWalking = false 
        clearVisuals()
    end
end)
createSlider(legitPage, "Humanization", 110, 0, 1, settings.humanization, function(v) settings.humanization = v end)

createSlider(settingsPage, "Start Delay", 10, 0, 30, settings.startDelayTime, function(v) settings.startDelayTime = v end)

local function updateTabs()
    btnRage.BackgroundColor3 = settings.currentTab == "rage" and settings.bgColor or settings.secColor
    btnRage.TextColor3 = settings.currentTab == "rage" and settings.accentColor or Color3.fromRGB(150, 150, 150)
    btnLegit.BackgroundColor3 = settings.currentTab == "legit" and settings.bgColor or settings.secColor
    btnLegit.TextColor3 = settings.currentTab == "legit" and settings.accentColor or Color3.fromRGB(150, 150, 150)
    btnSettings.BackgroundColor3 = settings.currentTab == "settings" and settings.bgColor or settings.secColor
    btnSettings.TextColor3 = settings.currentTab == "settings" and settings.accentColor or Color3.fromRGB(150, 150, 150)
    ragePage.Visible = settings.currentTab == "rage"
    legitPage.Visible = settings.currentTab == "legit"
    settingsPage.Visible = settings.currentTab == "settings"
    statusBtn.Visible = settings.currentTab ~= "settings" -- Скрывает кнопку запуска во вкладке настроек
end

btnRage.MouseButton1Click:Connect(function()
    settings.currentTab = "rage"
    updateTabs()
    updatePhysics()
    updateStatus()
    clearVisuals()
end)

btnLegit.MouseButton1Click:Connect(function()
    settings.currentTab = "legit"
    updateTabs()
    updatePhysics()
    updateStatus()
end)

btnSettings.MouseButton1Click:Connect(function()
    settings.currentTab = "settings"
    updateTabs()
    updateStatus()
end)

player.CharacterAdded:Connect(function()
    if settings.isAutoSolving or settings.isLegitActive then
        settings.isWaitingForRound = true
        waitTimeLeft = settings.startDelayTime
        clearCaches()
        
        task.spawn(function()
            while waitTimeLeft > 0 do 
                updateStatus()
                task.wait(0.01)
                waitTimeLeft = waitTimeLeft - 0.01 
            end
            settings.isWaitingForRound = false
            updatePhysics()
            updateStatus()
        end)
    end
end)

task.spawn(function()
    while true do
        pcall(solve)
        updateStatus()
        task.wait()
    end
end)

updateStatus()
chatNotify("Loaded!")
