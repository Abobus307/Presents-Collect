local player = game.Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local mathClamp, mathFloor, mathAbs, mathSqrt, mathMin, mathMax, mathRandom, mathHuge = math.clamp, math.floor, math.abs, math.sqrt, math.min, math.max, math.random, math.huge
local tableInsert, tableRemove, tableSort = table.insert, table.remove, table.sort
local tick, pcall, pairs, ipairs, tostring, tonumber = tick, pcall, pairs, ipairs, tostring, tonumber

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
local COLOR_GRAY = Color3.fromRGB(45, 45, 50)
local COLOR_TEXT = Color3.fromRGB(200, 200, 200)
local COLOR_INACTIVE = Color3.fromRGB(150, 150, 150)

local waitTimeLeft = 0
local solverNeighborCache = {}
local highlightCache = {}
local lastCalcTime = 0
local lastNotifyTime = 0
local lastActionTime = 0
local isGuessing = false
local stopCurrentExecution = false
local isWalking = false
local cachedPartsFolder = nil
local partsFolderTime = 0
local cachedWalkableCells = {}
local walkableCellsTime = 0
local cachedTargets = {}
local targetsTime = 0
local visualPool = {}
local activeVisuals = {}
local walkableCellsSet = {}
local guessHistory = {}
local consecutiveGuesses = 0
local lastStatusTime = 0

local VisualsFolder = Instance.new("Folder")
VisualsFolder.Name = "AutosolverVisuals"
VisualsFolder.Parent = workspace

local playerGui = player:WaitForChild("PlayerGui")

for _, name in ipairs({"autosolver_euler", "autosolver_final", "autosolver", "AutosolverUI"}) do
    local gui = playerGui:FindFirstChild(name)
    if gui then gui:Destroy() end
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
        StarterGui:SetCore("ChatMakeSystemMessage", {Text = "[autosolver]: " .. msg, Color = COLOR_TEXT})
    end)
end

local function isCellOpen(part)
    if not part or not part.Parent then return true end
    if part.Transparency > 0.5 or part:FindFirstChild("NumberGui") then return true end
    local c = part.Color
    return c.R > 0.7 and c.G > 0.7 and c.B < 0.6
end

local function isMine(part)
    return part and part.Parent and part.Color == COLOR_BLACK
end

local function isSafeMarked(part)
    return part and part.Parent and part.Color == COLOR_WHITE
end

local function isWalkable(part)
    if not part or not part.Parent or isMine(part) then return false end
    return isCellOpen(part) or isSafeMarked(part)
end

local function getVisual()
    local v = tableRemove(visualPool)
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
    cachedWalkableCells = {}
    cachedTargets = {}
    walkableCellsSet = {}
    walkableCellsTime = 0
    targetsTime = 0
    isGuessing = false
    isWalking = false
    guessHistory = {}
    consecutiveGuesses = 0
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
    for _, p in ipairs(char:GetDescendants()) do
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

local function getWalkableCells()
    local t = tick()
    if t - walkableCellsTime < 0.1 then return cachedWalkableCells, walkableCellsSet end
    walkableCellsTime = t
    
    local folder = getPartsFolder()
    if not folder then 
        cachedWalkableCells = {}
        walkableCellsSet = {}
        return cachedWalkableCells, walkableCellsSet 
    end
    
    local walkable, walkableSet = {}, {}
    for _, cell in ipairs(folder:GetChildren()) do
        if isWalkable(cell) then
            walkable[#walkable + 1] = cell
            walkableSet[cell] = true
        end
    end
    cachedWalkableCells = walkable
    walkableCellsSet = walkableSet
    return walkable, walkableSet
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
        local step = mathMax(1, mathFloor(#path / 10))
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

local function getPathNeighbors(cell, walkableCells, walkableSet)
    local neighbors = {}
    local p1 = cell.Position
    local maxDist = cell.Size.X * 1.5
    
    for i = 1, #walkableCells do
        local other = walkableCells[i]
        if other ~= cell then
            local p2 = other.Position
            local dx, dz = mathAbs(p1.X - p2.X), mathAbs(p1.Z - p2.Z)
            
            if dx <= maxDist and dz <= maxDist and (dx < 1 or dz < 1) then
                local dist = mathSqrt(dx*dx + dz*dz)
                if dist < maxDist and dist > 0.1 then
                    neighbors[#neighbors + 1] = other
                end
            end
        end
    end
    return neighbors
end

local function findPathAStar(startCell, targetCell, walkableCells, walkableSet)
    if not startCell or not targetCell then return nil end
    if startCell == targetCell then return {startCell} end
    if not walkableSet[startCell] or not walkableSet[targetCell] then return nil end
    
    local openList = {startCell}
    local closedSet = {}
    local cameFrom = {}
    local gScore = {[startCell] = 0}
    local fScore = {[startCell] = (startCell.Position - targetCell.Position).Magnitude}
    
    for iter = 1, 500 do
        if #openList == 0 then break end
        
        local current, currentIdx, lowestF = nil, 0, mathHuge
        
        for i = 1, #openList do
            local node = openList[i]
            local f = fScore[node] or mathHuge
            if f < lowestF then
                lowestF, current, currentIdx = f, node, i
            end
        end
        
        if current == targetCell then
            local path, node = {}, current
            while node do
                tableInsert(path, 1, node)
                node = cameFrom[node]
            end
            return path
        end
        
        tableRemove(openList, currentIdx)
        closedSet[current] = true
        
        for _, neighbor in ipairs(getPathNeighbors(current, walkableCells, walkableSet)) do
            if not closedSet[neighbor] and walkableSet[neighbor] then
                local tentativeG = (gScore[current] or mathHuge) + (current.Position - neighbor.Position).Magnitude
                
                if tentativeG < (gScore[neighbor] or mathHuge) then
                    cameFrom[neighbor] = current
                    gScore[neighbor] = tentativeG
                    fScore[neighbor] = tentativeG + (neighbor.Position - targetCell.Position).Magnitude
                    
                    local inOpen = false
                    for j = 1, #openList do
                        if openList[j] == neighbor then inOpen = true break end
                    end
                    if not inOpen then openList[#openList + 1] = neighbor end
                end
            end
        end
    end
    
    return nil
end

local function findClosestWalkableCell(position, cells)
    local closest, closestDist = nil, mathHuge
    for i = 1, #cells do
        local cell = cells[i]
        local diff = cell.Position - position
        local dist = diff.X*diff.X + diff.Z*diff.Z
        if dist < closestDist then
            closestDist, closest = dist, cell
        end
    end
    return closest
end

local function getAllSafeTargets()
    local t = tick()
    if t - targetsTime < 0.15 then return cachedTargets end
    targetsTime = t
    
    local folder = getPartsFolder()
    if not folder then 
        cachedTargets = {}
        return cachedTargets 
    end
    
    local targets = {}
    for _, cell in ipairs(folder:GetChildren()) do
        if isSafeMarked(cell) and not isCellOpen(cell) then
            targets[#targets + 1] = cell
        end
    end
    cachedTargets = targets
    return targets
end

local function findBestTarget(rootPos, walkableCells, walkableSet)
    local targets = getAllSafeTargets()
    if #targets == 0 then return nil, nil end
    
    local startCell = findClosestWalkableCell(rootPos, walkableCells)
    if not startCell then return nil, nil end
    
    tableSort(targets, function(a, b)
        return (a.Position - rootPos).Magnitude < (b.Position - rootPos).Magnitude
    end)
    
    for i = 1, mathMin(#targets, 5) do
        local target = targets[i]
        if walkableSet[target] then
            local path = findPathAStar(startCell, target, walkableCells, walkableSet)
            if path and #path <= 15 then return target, path end
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
    
    if h > 0.01 then task.wait(0.05 * h + mathRandom() * 0.15 * h) end
    
    local startIdx = (#path > 1 and (root.Position - path[1].Position).Magnitude < 2) and 2 or 1
    
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
            humanoid.WalkSpeed = mathClamp(baseSpeed + (mathRandom() - 0.5) * 6 * h, 12, 20)
        end
        
        local targetPos = cell.Position
        local acceptRadius = isLast and (0.8 + h * 0.7) or (1.0 + h * 1.5)
        local acceptRadiusSq = acceptRadius * acceptRadius
        local startTime = tick()
        
        humanoid:MoveTo(targetPos)
        
        while tick() - startTime < 3 do
            if stopCurrentExecution or not settings.isLegitActive or not settings.pathfindingEnabled then
                humanoid.WalkSpeed = baseSpeed
                isWalking = false
                clearVisuals()
                return false
            end
            
            local rootPos = root.Position
            local dx, dz = rootPos.X - targetPos.X, rootPos.Z - targetPos.Z
            if dx*dx + dz*dz < acceptRadiusSq then break end
            
            humanoid:MoveTo(targetPos)
            RunService.Heartbeat:Wait()
        end
        
        if h > 0.01 and not isLast then task.wait(0.02 * h + mathRandom() * 0.05 * h) end
    end
    
    if h > 0.01 then task.wait(0.03 * h + mathRandom() * 0.1 * h) end
    
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
    
    local walkableCells, walkableSet = getWalkableCells()
    if #walkableCells == 0 then return end
    
    local target, path = findBestTarget(root.Position, walkableCells, walkableSet)
    if target and path then task.spawn(walkPath, path, target) end
end

local function teleportTo(target)
    if stopCurrentExecution or not target or not target.Parent or isCellOpen(target) then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    local newCFrame = target.CFrame * CFrame.new(0, 5, 0)
    
    if settings.freezeEnabled and settings.currentTab == "rage" then
        for _, p in ipairs(char:GetDescendants()) do 
            if p:IsA("BasePart") then p.Anchored = false end 
        end
        root.CFrame = newCFrame
        root.Velocity = Vector3.new(0, -100, 0)
        task.wait(0.01)
        updatePhysics()
    else
        root.CFrame = newCFrame
    end
end

local function getSolverData()
    local folder = getPartsFolder()
    if not folder then return {} end
    
    local numberData = {}
    local allParts = folder:GetChildren()
    local cellSize = allParts[1] and allParts[1].Size.X * 1.8 or 5
    
    for _, cell in ipairs(allParts) do
        if not isCellOpen(cell) then continue end
        
        local gui = cell:FindFirstChild("NumberGui")
        if not gui then continue end
        local label = gui:FindFirstChildOfClass("TextLabel")
        local val = label and tonumber(label.Text) or 0
        
        local cached = solverNeighborCache[cell]
        if not cached then
            cached = {}
            local pos = cell.Position
            for _, n in ipairs(allParts) do 
                if n ~= cell and (n.Position - pos).Magnitude < cellSize then 
                    cached[#cached + 1] = n
                end 
            end
            solverNeighborCache[cell] = cached
        end
        
        local hidden, mines = {}, 0
        for _, n in ipairs(cached) do
            if not isCellOpen(n) then
                if n.Color == COLOR_BLACK then 
                    mines = mines + 1 
                else 
                    hidden[#hidden + 1] = n
                end
            end
        end
        
        if #hidden > 0 or val == 0 then 
            numberData[#numberData + 1] = {obj = cell, eVal = val - mines, hidden = hidden}
        end
    end
    
    return numberData
end

local function getNeighborCount(cell, allParts)
    local count = 0
    local pos = cell.Position
    local dist = cell.Size.X * 1.8
    for i = 1, #allParts do
        if allParts[i] ~= cell and (allParts[i].Position - pos).Magnitude < dist then
            count = count + 1
        end
    end
    return count
end

local function findBestGuess(data, allParts)
    local cellData = {}
    
    for _, d in ipairs(data) do
        if #d.hidden > 0 then
            local localProb = d.eVal > 0 and mathMin(1, d.eVal / #d.hidden) or 0
            
            for _, cell in ipairs(d.hidden) do
                if cell.Color ~= COLOR_BLACK then
                    local cd = cellData[cell]
                    if not cd then
                        cd = {maxProb = 0, minProb = 1, sumProb = 0, count = 0, neighborCount = getNeighborCount(cell, allParts)}
                        cellData[cell] = cd
                    end
                    cd.maxProb = mathMax(cd.maxProb, localProb)
                    cd.minProb = mathMin(cd.minProb, localProb)
                    cd.sumProb = cd.sumProb + localProb
                    cd.count = cd.count + 1
                end
            end
        end
    end
    
    local candidates = {}
    for cell, cd in pairs(cellData) do
        if cell.Color ~= COLOR_BLACK and not guessHistory[cell] then
            local avgProb = cd.count > 0 and (cd.sumProb / cd.count) or 0.5
            local risk = cd.maxProb * 0.5 + avgProb * 0.3 + cd.minProb * 0.2
            local edgeBonus = cd.neighborCount <= 3 and -0.15 or (cd.neighborCount <= 5 and -0.08 or 0)
            
            candidates[#candidates + 1] = {
                cell = cell,
                score = risk + edgeBonus - mathMin(cd.count * 0.02, 0.1),
                neighbors = cd.neighborCount,
                constraints = cd.count
            }
        end
    end
    
    if #candidates == 0 then
        local folder = getPartsFolder()
        if folder then
            for _, cell in ipairs(folder:GetChildren()) do
                if not isCellOpen(cell) and cell.Color ~= COLOR_BLACK and not cellData[cell] and not guessHistory[cell] then
                    local nc = getNeighborCount(cell, allParts)
                    candidates[#candidates + 1] = {
                        cell = cell,
                        score = nc <= 3 and 0.25 or (nc <= 5 and 0.35 or 0.5),
                        neighbors = nc,
                        constraints = 0
                    }
                end
            end
        end
    end
    
    if #candidates == 0 then return nil end
    
    tableSort(candidates, function(a, b)
        if mathAbs(a.score - b.score) < 0.01 then
            return a.neighbors ~= b.neighbors and a.neighbors < b.neighbors or a.constraints > b.constraints
        end
        return a.score < b.score
    end)
    
    return candidates[mathRandom(1, mathMin(3, #candidates))].cell
end

local function solve()
    if stopCurrentExecution then return end
    if settings.currentTab == "legit" and settings.isLegitActive and tick() - lastCalcTime < settings.calculateDelay then return end
    if (not settings.isAutoSolving and not settings.isLegitActive) or settings.isWaitingForRound then return end
    lastCalcTime = tick()
    
    local data = getSolverData()
    local safeQueue, mineQueue = {}, {}
    local foundAnything = false
    local dataLen = #data

    for i = 1, dataLen do
        local d1 = data[i]
        local pos1 = d1.obj.Position
        for j = 1, dataLen do
            if i ~= j then
                local d2 = data[j]
                if (pos1 - d2.obj.Position).Magnitude < 12 then
                    local s1, s2 = d1.hidden, d2.hidden
                    local s1Len, s2Len = #s1, #s2
                    
                    if s2Len > s1Len then
                        local isSubset = true
                        for k = 1, s1Len do
                            local found = false
                            for l = 1, s2Len do 
                                if s1[k] == s2[l] then found = true break end 
                            end
                            if not found then isSubset = false break end
                        end
                        
                        if isSubset then
                            local diffMines = d2.eVal - d1.eVal
                            local diffCells = {}
                            for k = 1, s2Len do
                                local inS1 = false
                                for l = 1, s1Len do 
                                    if s2[k] == s1[l] then inS1 = true break end 
                                end
                                if not inS1 then diffCells[#diffCells + 1] = s2[k] end
                            end
                            
                            if diffMines == 0 then
                                for k = 1, #diffCells do safeQueue[#safeQueue + 1] = diffCells[k] end
                                foundAnything = true
                            elseif diffMines == #diffCells then
                                for k = 1, #diffCells do mineQueue[#mineQueue + 1] = diffCells[k] end
                                foundAnything = true
                            end
                        end
                    end
                end
            end
        end
    end

    local basicSafe, basicMines = {}, {}
    for i = 1, dataLen do
        local d = data[i]
        local hiddenLen = #d.hidden
        if hiddenLen > 0 then
            if hiddenLen == d.eVal then
                for j = 1, hiddenLen do basicMines[#basicMines + 1] = d.hidden[j] end
                foundAnything = true
            elseif d.eVal <= 0 then
                for j = 1, hiddenLen do basicSafe[#basicSafe + 1] = d.hidden[j] end
                foundAnything = true
            end
        end
    end

    if settings.currentTab == "rage" and settings.isAutoSolving then
        for i = 1, #mineQueue do mineQueue[i].Color = COLOR_BLACK end
        for i = 1, #basicMines do basicMines[i].Color = COLOR_BLACK end
        
        local targetQueue = #safeQueue > 0 and safeQueue or basicSafe
        if #targetQueue > 0 then
            isGuessing = false
            consecutiveGuesses = 0
            guessHistory = {}
            for i = 1, #targetQueue do 
                if stopCurrentExecution or not settings.isAutoSolving then break end 
                local s = targetQueue[i]
                if not isCellOpen(s) then 
                    teleportTo(s)
                    task.wait(settings.actionDelay) 
                end
            end
        elseif settings.autoGuess and not foundAnything and tick() - lastActionTime > 0.5 then
            local folder = getPartsFolder()
            local allParts = folder and folder:GetChildren() or {}
            local bestGuess = findBestGuess(data, allParts)
            
            if bestGuess then
                isGuessing = true
                consecutiveGuesses = consecutiveGuesses + 1
                guessHistory[bestGuess] = true
                
                if consecutiveGuesses > 10 then
                    guessHistory = {}
                    consecutiveGuesses = 0
                end
                
                teleportTo(bestGuess)
                lastActionTime = tick()
            end
        end
        
    elseif settings.currentTab == "legit" and settings.isLegitActive then
        local finalMines = #mineQueue > 0 and mineQueue or basicMines
        local finalSafe = #safeQueue > 0 and safeQueue or basicSafe
        
        for i = 1, #finalMines do finalMines[i].Color = COLOR_BLACK end
        for i = 1, #finalSafe do 
            finalSafe[i].Color = COLOR_WHITE
            highlightCache[finalSafe[i]] = "safe"
        end
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutosolverUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

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
    btn.TextColor3 = active and settings.accentColor or COLOR_INACTIVE
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
        statusBtn.Text = isGuessing and "ACTIVE - " .. string.upper(settings.currentTab) .. " [GUESSING]" or "ACTIVE - " .. string.upper(settings.currentTab)
        statusBtn.TextColor3 = isGuessing and Color3.fromRGB(255, 200, 100) or Color3.fromRGB(100, 255, 100)
        statusBtn.BackgroundColor3 = isGuessing and Color3.fromRGB(50, 40, 30) or Color3.fromRGB(30, 50, 30)
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
    lbl.TextColor3 = COLOR_TEXT
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    
    local toggle = Instance.new("TextButton", frame)
    toggle.Size = UDim2.new(0, 44, 0, 22)
    toggle.Position = UDim2.new(1, -50, 0.5, -11)
    toggle.BackgroundColor3 = value and settings.accentColor or COLOR_GRAY
    toggle.Text = ""
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(1, 0)
    
    local circle = Instance.new("Frame", toggle)
    circle.Size = UDim2.new(0, 18, 0, 18)
    circle.Position = value and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    circle.BackgroundColor3 = COLOR_WHITE
    Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)
    
    toggle.MouseButton1Click:Connect(function()
        value = not value
        TweenService:Create(toggle, TweenInfo.new(0.15), {BackgroundColor3 = value and settings.accentColor or COLOR_GRAY}):Play()
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
    lbl.TextColor3 = COLOR_TEXT
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    
    local inputBox = Instance.new("TextBox", frame)
    inputBox.Size = UDim2.new(0, 60, 0, 20)
    inputBox.Position = UDim2.new(1, -65, 0, 0)
    inputBox.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    inputBox.Text = tostring(default)
    inputBox.Font = Enum.Font.Code
    inputBox.TextColor3 = COLOR_TEXT
    inputBox.TextSize = 11
    inputBox.ClearTextOnFocus = false
    Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 4)
    
    local bar = Instance.new("Frame", frame)
    bar.Size = UDim2.new(1, 0, 0, 4)
    bar.Position = UDim2.new(0, 0, 0, 28)
    bar.BackgroundColor3 = COLOR_GRAY
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
    
    local fill = Instance.new("Frame", bar)
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = settings.accentColor
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
    
    local currentValue, dragging = default, false
    
    local function updateValue(val)
        val = mathFloor(mathClamp(val, min, max) * 100) / 100
        currentValue = val
        fill.Size = UDim2.new((val - min) / (max - min), 0, 1, 0)
        inputBox.Text = tostring(val)
        callback(val)
    end
    
    inputBox.FocusLost:Connect(function()
        local num = tonumber(inputBox.Text)
        if num then updateValue(num) else inputBox.Text = tostring(currentValue) end
    end)
    
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then 
            dragging = true 
            updateValue(min + (max - min) * mathClamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1))
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateValue(min + (max - min) * mathClamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1))
        end
    end)
end

createToggle(ragePage, "Freeze Character", 10, settings.freezeEnabled, function(v) settings.freezeEnabled = v updatePhysics() end)
createToggle(ragePage, "Auto Guessing", 45, settings.autoGuess, function(v) settings.autoGuess = v end)
createSlider(ragePage, "Teleport Delay", 90, 0.04, 1, settings.actionDelay, function(v) settings.actionDelay = v end)

createSlider(legitPage, "Calculation Delay", 10, 0.1, 5, settings.calculateDelay, function(v) settings.calculateDelay = v end)
createToggle(legitPage, "Auto Walk", 65, settings.pathfindingEnabled, function(v) 
    settings.pathfindingEnabled = v 
    if not v then isWalking = false clearVisuals() end
end)
createSlider(legitPage, "Humanization", 110, 0, 1, settings.humanization, function(v) settings.humanization = v end)

createSlider(settingsPage, "Start Delay", 10, 0, 30, settings.startDelayTime, function(v) settings.startDelayTime = v end)

local function updateTabs()
    local tabs = {rage = btnRage, legit = btnLegit, settings = btnSettings}
    local pages = {rage = ragePage, legit = legitPage, settings = settingsPage}
    
    for name, btn in pairs(tabs) do
        local active = settings.currentTab == name
        btn.BackgroundColor3 = active and settings.bgColor or settings.secColor
        btn.TextColor3 = active and settings.accentColor or COLOR_INACTIVE
    end
    
    for name, page in pairs(pages) do
        page.Visible = settings.currentTab == name
    end
    
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

task.spawn(function()
    while true do
        pcall(solve)
        
        if settings.currentTab == "legit" and settings.isLegitActive and settings.pathfindingEnabled and not isWalking and not settings.isWaitingForRound then
            pcall(doPathfinding)
        end
        
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
