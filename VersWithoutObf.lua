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
    freezeEnabled = false,
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

local COLOR_BLACK = Color3.new(0, 0, 0)
local COLOR_WHITE = Color3.new(1, 1, 1)
local COLOR_RED = Color3.fromRGB(255, 50, 50)
local COLOR_BLUE = Color3.fromRGB(0, 150, 255)

local waitTimeLeft = 0
local solverNeighborCache = {}
local highlightCache = {}
local lastCalcTime = 0
local lastNotifyTime = 0
local isGuessing = false
local stopCurrentExecution = false
local isWalking = false
local cachedPartsFolder = nil
local partsFolderTime = 0
local cachedOpenCells = {}
local openCellsTime = 0
local cachedTargets = {}
local targetsTime = 0
local solverDataCache = {}
local solverDataTime = 0
local visualPool = {}
local activeVisuals = {}
local openCellsSet = {}

local VisualsFolder = workspace:FindFirstChild("AutosolverVisuals")
if not VisualsFolder then
    VisualsFolder = Instance.new("Folder")
    VisualsFolder.Name = "AutosolverVisuals"
    VisualsFolder.Parent = workspace
end

local function getSafeParent()
    if gethui then return gethui() end
    return game:GetService("CoreGui")
end

for _, name in pairs({"autosolver_euler", "autosolver_final", "autosolver", "AutosolverUI"}) do
    pcall(function() getSafeParent()[name]:Destroy() end)
    pcall(function() player.PlayerGui[name]:Destroy() end)
end

local function chatNotify(msg)
    local t = tick()
    if t - lastNotifyTime < 0.5 then return end 
    lastNotifyTime = t
    pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local channels = TextChatService:FindFirstChild("TextChannels")
            local channel = channels and channels:FindFirstChild("RBXSystem")
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
    local c = part.Color
    return c.R > 0.7 and c.G > 0.7 and c.B < 0.6
end

local function isMine(part)
    return part and part.Parent and part.Color == COLOR_BLACK
end

local function isSafeMarked(part)
    return part and part.Parent and part.Color == COLOR_WHITE
end

local function getVisual()
    local v = table.remove(visualPool)
    if v then return v end
    local ball = Instance.new("SphereHandleAdornment")
    ball.AlwaysOnTop = true
    return ball
end

local function returnVisual(v)
    v.Adornee = nil
    v.Parent = nil
    visualPool[#visualPool + 1] = v
end

local function clearVisuals()
    for i = #activeVisuals, 1, -1 do
        returnVisual(activeVisuals[i])
        activeVisuals[i] = nil
    end
end

local function clearCaches()
    solverNeighborCache = {}
    highlightCache = {}
    cachedOpenCells = {}
    cachedTargets = {}
    solverDataCache = {}
    openCellsSet = {}
    openCellsTime = 0
    targetsTime = 0
    solverDataTime = 0
    isGuessing = false
    isWalking = false
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
    stopCurrentExecution = false
    isWalking = false
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
    local parts = char:GetDescendants()
    for i = 1, #parts do
        local p = parts[i]
        if p:IsA("BasePart") then p.Anchored = active end
    end
    if Controls then
        if active then Controls:Disable() else Controls:Enable() end
    end
end

local function getPartsFolder()
    local t = tick()
    if cachedPartsFolder and cachedPartsFolder.Parent and t - partsFolderTime < 2 then
        return cachedPartsFolder
    end
    partsFolderTime = t
    local flag = workspace:FindFirstChild("Flag")
    cachedPartsFolder = flag and flag:FindFirstChild("Parts")
    return cachedPartsFolder
end

local function getOpenCells()
    local t = tick()
    if t - openCellsTime < 0.15 then return cachedOpenCells, openCellsSet end
    openCellsTime = t
    
    local folder = getPartsFolder()
    if not folder then 
        cachedOpenCells = {}
        openCellsSet = {}
        return cachedOpenCells, openCellsSet 
    end
    
    local open = {}
    local openSet = {}
    local children = folder:GetChildren()
    for i = 1, #children do
        local cell = children[i]
        if isCellOpen(cell) and not isMine(cell) then
            open[#open + 1] = cell
            openSet[cell] = true
        end
    end
    cachedOpenCells = open
    openCellsSet = openSet
    return open, openSet
end

local function createPathVisuals(path, target)
    clearVisuals()
    
    if target then
        local ball = getVisual()
        ball.Adornee = target
        ball.Radius = 1.5
        ball.Color3 = COLOR_RED
        ball.Transparency = 0.2
        ball.ZIndex = 5
        ball.Parent = VisualsFolder
        activeVisuals[#activeVisuals + 1] = ball
    end
    
    if path then
        local step = math.max(1, math.floor(#path / 10))
        for i = 1, #path, step do
            local ball = getVisual()
            ball.Adornee = path[i]
            ball.Radius = 0.7
            ball.Color3 = COLOR_BLUE
            ball.Transparency = 0.3
            ball.ZIndex = 4
            ball.Parent = VisualsFolder
            activeVisuals[#activeVisuals + 1] = ball
        end
    end
end

local function getPathNeighbors(cell, openCells, openSet)
    local neighbors = {}
    local p1 = cell.Position
    local size = cell.Size.X
    local maxDist = size * 1.5
    
    for i = 1, #openCells do
        local other = openCells[i]
        if other == cell then continue end
        
        local p2 = other.Position
        local dx = math.abs(p1.X - p2.X)
        local dz = math.abs(p1.Z - p2.Z)
        
        if dx > maxDist or dz > maxDist then continue end
        
        local alignedX = dx < 1
        local alignedZ = dz < 1
        
        if not alignedX and not alignedZ then continue end
        
        local dist = math.sqrt(dx*dx + dz*dz)
        if dist < maxDist and dist > 0.1 then
            neighbors[#neighbors + 1] = other
        end
    end
    return neighbors
end

local function findPathAStar(startCell, targetCell, openCells, openSet)
    if not startCell or not targetCell then return nil end
    if startCell == targetCell then return {startCell} end
    if not openSet[startCell] or not openSet[targetCell] then return nil end
    
    local openList = {startCell}
    local closedSet = {}
    local cameFrom = {}
    local gScore = {[startCell] = 0}
    local fScore = {[startCell] = (startCell.Position - targetCell.Position).Magnitude}
    
    local iterations = 0
    
    while #openList > 0 and iterations < 400 do
        iterations = iterations + 1
        
        local current = nil
        local currentIdx = 0
        local lowestF = math.huge
        
        for i = 1, #openList do
            local node = openList[i]
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
        
        table.remove(openList, currentIdx)
        closedSet[current] = true
        
        local neighbors = getPathNeighbors(current, openCells, openSet)
        
        for i = 1, #neighbors do
            local neighbor = neighbors[i]
            if closedSet[neighbor] then continue end
            if not openSet[neighbor] then continue end
            
            local moveCost = (current.Position - neighbor.Position).Magnitude
            local tentativeG = (gScore[current] or math.huge) + moveCost
            
            if tentativeG < (gScore[neighbor] or math.huge) then
                cameFrom[neighbor] = current
                gScore[neighbor] = tentativeG
                fScore[neighbor] = tentativeG + (neighbor.Position - targetCell.Position).Magnitude
                
                local inOpen = false
                for j = 1, #openList do
                    if openList[j] == neighbor then 
                        inOpen = true 
                        break 
                    end
                end
                if not inOpen then
                    openList[#openList + 1] = neighbor
                end
            end
        end
    end
    
    return nil
end

local function findClosestCell(position, cells)
    local closest = nil
    local closestDist = math.huge
    for i = 1, #cells do
        local cell = cells[i]
        local diff = cell.Position - position
        local dist = diff.X*diff.X + diff.Z*diff.Z
        if dist < closestDist then
            closestDist = dist
            closest = cell
        end
    end
    return closest
end

local function getAllSafeTargets()
    local t = tick()
    if t - targetsTime < 0.3 then return cachedTargets end
    targetsTime = t
    
    local folder = getPartsFolder()
    if not folder then 
        cachedTargets = {}
        return cachedTargets 
    end
    
    local targets = {}
    local children = folder:GetChildren()
    for i = 1, #children do
        local cell = children[i]
        if isSafeMarked(cell) and not isCellOpen(cell) then
            targets[#targets + 1] = cell
        end
    end
    cachedTargets = targets
    return targets
end

local function getAdjacentOpenCell(targetCell, openCells, openSet)
    local size = targetCell.Size.X
    local maxDist = size * 1.5
    local closest = nil
    local closestDist = math.huge
    local targetPos = targetCell.Position
    
    for i = 1, #openCells do
        local cell = openCells[i]
        local p2 = cell.Position
        
        local dx = math.abs(targetPos.X - p2.X)
        local dz = math.abs(targetPos.Z - p2.Z)
        
        if dx > maxDist or dz > maxDist then continue end
        
        local alignedX = dx < 1
        local alignedZ = dz < 1
        
        if not alignedX and not alignedZ then continue end
        
        local dist = math.sqrt(dx*dx + dz*dz)
        if dist < maxDist and dist > 0.1 and dist < closestDist then
            closestDist = dist
            closest = cell
        end
    end
    return closest
end

local function findBestTarget(rootPos, openCells, openSet)
    local targets = getAllSafeTargets()
    if #targets == 0 then return nil, nil end
    
    local startCell = findClosestCell(rootPos, openCells)
    if not startCell then return nil, nil end
    
    table.sort(targets, function(a, b)
        local da = (a.Position - rootPos).Magnitude
        local db = (b.Position - rootPos).Magnitude
        return da < db
    end)
    
    for i = 1, math.min(#targets, 8) do
        local target = targets[i]
        local adjacentCell = getAdjacentOpenCell(target, openCells, openSet)
        if adjacentCell then
            local path = findPathAStar(startCell, adjacentCell, openCells, openSet)
            if path then
                return target, path
            end
        end
    end
    
    return nil, nil
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
    
    humanoid.WalkSpeed = baseSpeed
    
    if h > 0.01 then
        task.wait(0.05 * h + math.random() * 0.15 * h)
    end
    
    local startIdx = 1
    if #path > 1 then
        local distToFirst = (root.Position - path[1].Position).Magnitude
        if distToFirst < 2 then
            startIdx = 2
        end
    end
    
    for i = startIdx, #path do
        if stopCurrentExecution or not settings.isLegitActive or not settings.pathfindingEnabled then
            humanoid.WalkSpeed = baseSpeed
            isWalking = false
            clearVisuals()
            return false
        end
        
        local cell = path[i]
        local isLast = (i == #path)
        
        if h > 0.01 then
            local speedVariation = (math.random() - 0.5) * 6 * h
            humanoid.WalkSpeed = math.clamp(baseSpeed + speedVariation, 12, 20)
        end
        
        local targetPos = cell.Position
        humanoid:MoveTo(targetPos)
        
        local acceptRadius = 1.0 + h * 1.5
        if isLast then
            acceptRadius = 0.8 + h * 0.7
        end
        
        local timeout = 4
        local startTime = tick()
        
        while tick() - startTime < timeout do
            if stopCurrentExecution or not settings.isLegitActive or not settings.pathfindingEnabled then
                humanoid.WalkSpeed = baseSpeed
                isWalking = false
                clearVisuals()
                return false
            end
            
            local rootPos = root.Position
            local dx = rootPos.X - targetPos.X
            local dz = rootPos.Z - targetPos.Z
            local distSq = dx*dx + dz*dz
            
            if distSq < acceptRadius * acceptRadius then
                break
            end
            
            humanoid:MoveTo(targetPos)
            RunService.Heartbeat:Wait()
        end
        
        if h > 0.01 and not isLast then
            task.wait(0.02 * h + math.random() * 0.06 * h)
        end
    end
    
    if targetCell and not isCellOpen(targetCell) then
        local targetPos = targetCell.Position
        humanoid:MoveTo(targetPos)
        
        local finalRadius = 1.0 + h * 0.5
        local startTime = tick()
        
        while tick() - startTime < 3 do
            if stopCurrentExecution or not settings.isLegitActive then break end
            if isCellOpen(targetCell) then break end
            
            local rootPos = root.Position
            local dx = rootPos.X - targetPos.X
            local dz = rootPos.Z - targetPos.Z
            
            if dx*dx + dz*dz < finalRadius * finalRadius then
                break
            end
            
            humanoid:MoveTo(targetPos)
            RunService.Heartbeat:Wait()
        end
    end
    
    if h > 0.01 then
        task.wait(0.05 * h + math.random() * 0.15 * h)
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
    
    local openCells, openSet = getOpenCells()
    if #openCells == 0 then return end
    
    local target, path = findBestTarget(root.Position, openCells, openSet)
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
    
    local parts = char:GetDescendants()
    for i = 1, #parts do
        local p = parts[i]
        if p:IsA("BasePart") then p.Anchored = false end
    end
    root.CFrame = target.CFrame * CFrame.new(0, 5, 0)
    task.wait(0.01)
    updatePhysics()
end

local function getSolverNeighbors(cell, allParts)
    local cached = solverNeighborCache[cell]
    if cached then return cached end
    
    local nbs = {}
    local pos = cell.Position
    local dist = cell.Size.X * 1.8
    for i = 1, #allParts do
        local n = allParts[i]
        if n ~= cell and (n.Position - pos).Magnitude < dist then 
            nbs[#nbs + 1] = n
        end
    end
    solverNeighborCache[cell] = nbs
    return nbs
end

local function getSolverData()
    local folder = getPartsFolder()
    if not folder then return {} end
    
    local t = tick()
    local cacheTime = settings.currentTab == "legit" and 0.2 or 0.08
    if t - solverDataTime < cacheTime then return solverDataCache end
    solverDataTime = t
    
    local numberData = {}
    local allParts = folder:GetChildren()
    
    for i = 1, #allParts do
        local cell = allParts[i]
        if not isCellOpen(cell) then continue end
        
        local gui = cell:FindFirstChild("NumberGui")
        if not gui then continue end
        local label = gui:FindFirstChildOfClass("TextLabel")
        local val = label and tonumber(label.Text) or 0
        if val == 0 then continue end
        
        local nbs = getSolverNeighbors(cell, allParts)
        
        local hidden = {}
        local mines = 0
        for j = 1, #nbs do
            local n = nbs[j]
            if not isCellOpen(n) then
                if isMine(n) then 
                    mines = mines + 1 
                else 
                    hidden[#hidden + 1] = n 
                end
            end
        end
        
        if #hidden > 0 then 
            numberData[#numberData + 1] = {obj = cell, eVal = val - mines, hidden = hidden}
        end
    end
    
    solverDataCache = numberData
    return numberData
end

local function solve()
    if stopCurrentExecution or settings.isWaitingForRound then return end
    if not settings.isAutoSolving and not settings.isLegitActive then return end
    
    local t = tick()
    local delay = settings.currentTab == "legit" and settings.calculateDelay or 0.08
    if t - lastCalcTime < delay then return end
    
    lastCalcTime = t
    local data = getSolverData()
    local safeQueue = {}
    local mineQueue = {}
    local foundAnything = false
    
    local dataCount = #data
    for i = 1, dataCount do
        local d1 = data[i]
        for j = 1, dataCount do
            if i == j then continue end
            local d2 = data[j]
            if (d1.obj.Position - d2.obj.Position).Magnitude > 12 then continue end
            
            local s1, s2 = d1.hidden, d2.hidden
            if #s2 <= #s1 then continue end
            
            local isSubset = true
            for k = 1, #s1 do
                local x = s1[k]
                local found = false
                for l = 1, #s2 do
                    if x == s2[l] then found = true break end
                end
                if not found then isSubset = false break end
            end
            
            if isSubset then
                local diffMines = d2.eVal - d1.eVal
                local diffCells = {}
                for k = 1, #s2 do
                    local x = s2[k]
                    local inS1 = false
                    for l = 1, #s1 do
                        if x == s1[l] then inS1 = true break end
                    end
                    if not inS1 then diffCells[#diffCells + 1] = x end
                end
                
                if diffMines == 0 then
                    for k = 1, #diffCells do safeQueue[diffCells[k]] = true end
                    foundAnything = true
                elseif diffMines == #diffCells then
                    for k = 1, #diffCells do mineQueue[diffCells[k]] = true end
                    foundAnything = true
                end
            end
        end
    end

    for i = 1, dataCount do
        local d = data[i]
        if #d.hidden == d.eVal then
            for j = 1, #d.hidden do mineQueue[d.hidden[j]] = true end
            foundAnything = true
        elseif d.eVal <= 0 then
            for j = 1, #d.hidden do safeQueue[d.hidden[j]] = true end
            foundAnything = true
        end
    end

    for m in pairs(mineQueue) do 
        if m and m.Parent then m.Color = COLOR_BLACK end
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
            for i = 1, dataCount do
                local d = data[i]
                for j = 1, #d.hidden do
                    local n = d.hidden[j]
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
                s.Color = COLOR_WHITE
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
mainFrame.Active = true
mainFrame.Draggable = true
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
    mainFrame.Visible = state
    openBtn.Visible = not state
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
        statusBtn.Text = string.format("WAITING (%.1fs)", waitTimeLeft)
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
        TweenService:Create(toggle, TweenInfo.new(0.15), {BackgroundColor3 = value and settings.accentColor or Color3.fromRGB(45, 45, 50)}):Play()
        TweenService:Create(circle, TweenInfo.new(0.15), {Position = value and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)}):Play()
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
            updateValue(min + (max - min) * rel)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local rel = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            updateValue(min + (max - min) * rel)
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
    statusBtn.Visible = settings.currentTab ~= "settings"
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
                task.wait(0.1)
                waitTimeLeft = waitTimeLeft - 0.1 
            end
            settings.isWaitingForRound = false
            updatePhysics()
            updateStatus()
        end)
    end
end)

local lastStatusTime = 0
task.spawn(function()
    while true do
        pcall(solve)
        local t = tick()
        if t - lastStatusTime > 0.25 then
            lastStatusTime = t
            updateStatus()
        end
        task.wait()
    end
end)

updateStatus()
chatNotify("Loaded!")
