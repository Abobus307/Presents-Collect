if _G.AutoTP_Running then
    _G.AutoTP_Running = false
    task.wait(0.2)
end
_G.AutoTP_Running = true

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local oldGui = PlayerGui:FindFirstChild("AutoTP_GUI")
if oldGui then oldGui:Destroy() end

local Folder = Workspace:WaitForChild("Presents", 10)
if not Folder then return end

local LastGifts = {}
local TotalGifts = 0
local Enabled = false
local Use3D = false
local Minimized = false

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoTP_GUI"
ScreenGui.Parent = PlayerGui
ScreenGui.ResetOnSpawn = false

local function MakeDraggable(frame, handle)
    local dragging, dragInput, dragStart, startPos
    handle = handle or frame
    
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local SelectFrame = Instance.new("Frame")
SelectFrame.Parent = ScreenGui
SelectFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
SelectFrame.Position = UDim2.new(0.5, -120, 0.5, -60)
SelectFrame.Size = UDim2.new(0, 240, 0, 120)
Instance.new("UICorner", SelectFrame).CornerRadius = UDim.new(0, 12)
local ss = Instance.new("UIStroke", SelectFrame)
ss.Color = Color3.fromRGB(80, 80, 120)
ss.Thickness = 2

MakeDraggable(SelectFrame)

local SelectTitle = Instance.new("TextLabel")
SelectTitle.Parent = SelectFrame
SelectTitle.BackgroundTransparency = 1
SelectTitle.Position = UDim2.new(0, 0, 0, 10)
SelectTitle.Size = UDim2.new(1, 0, 0, 25)
SelectTitle.Font = Enum.Font.GothamBold
SelectTitle.TextSize = 16
SelectTitle.TextColor3 = Color3.new(1, 1, 1)
SelectTitle.Text = "Select Display Mode"

local Btn3D = Instance.new("TextButton")
Btn3D.Parent = SelectFrame
Btn3D.BackgroundColor3 = Color3.fromRGB(50, 150, 250)
Btn3D.Position = UDim2.new(0.05, 0, 0, 50)
Btn3D.Size = UDim2.new(0.43, 0, 0, 50)
Btn3D.Font = Enum.Font.GothamBold
Btn3D.TextSize = 14
Btn3D.Text = "🎁 3D Models"
Btn3D.TextColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", Btn3D).CornerRadius = UDim.new(0, 8)

local BtnText = Instance.new("TextButton")
BtnText.Parent = SelectFrame
BtnText.BackgroundColor3 = Color3.fromRGB(150, 100, 250)
BtnText.Position = UDim2.new(0.52, 0, 0, 50)
BtnText.Size = UDim2.new(0.43, 0, 0, 50)
BtnText.Font = Enum.Font.GothamBold
BtnText.TextSize = 14
BtnText.Text = "📝 Text"
BtnText.TextColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", BtnText).CornerRadius = UDim.new(0, 8)

local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
MainFrame.Position = UDim2.new(0, 10, 0.2, 0)
MainFrame.Size = UDim2.new(0, 250, 0, 340)
MainFrame.Visible = false
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)
local ms = Instance.new("UIStroke", MainFrame)
ms.Color = Color3.fromRGB(80, 80, 120)
ms.Thickness = 2

local TopBar = Instance.new("Frame")
TopBar.Parent = MainFrame
TopBar.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
TopBar.Size = UDim2.new(1, 0, 0, 30)
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 12)

MakeDraggable(MainFrame, TopBar)

local Title = Instance.new("TextLabel")
Title.Parent = TopBar
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 10, 0, 0)
Title.Size = UDim2.new(0.6, 0, 1, 0)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 12
Title.TextColor3 = Color3.new(1, 1, 1)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "⠀Auto TP"

local CloseBtn = Instance.new("TextButton")
CloseBtn.Parent = TopBar
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseBtn.Position = UDim2.new(1, -28, 0, 3)
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.Text = "−"
CloseBtn.TextColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

local MinBtn = Instance.new("TextButton")
MinBtn.Parent = ScreenGui
MinBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
MinBtn.Position = UDim2.new(0, 10, 0.2, -35)
MinBtn.Size = UDim2.new(0, 100, 0, 30)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 12
MinBtn.Text = "TP: OFF"
MinBtn.TextColor3 = Color3.new(1, 1, 1)
MinBtn.Visible = false
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 8)

MakeDraggable(MinBtn)

local Button = Instance.new("TextButton")
Button.Parent = MainFrame
Button.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
Button.Position = UDim2.new(0.05, 0, 0, 40)
Button.Size = UDim2.new(0.9, 0, 0, 40)
Button.Font = Enum.Font.GothamBold
Button.TextSize = 18
Button.Text = "TP: OFF"
Button.TextColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 8)

local StatsLabel = Instance.new("TextLabel")
StatsLabel.Parent = MainFrame
StatsLabel.BackgroundTransparency = 1
StatsLabel.Position = UDim2.new(0.05, 0, 0, 85)
StatsLabel.Size = UDim2.new(0.9, 0, 0, 70)
StatsLabel.Font = Enum.Font.Gotham
StatsLabel.TextSize = 12
StatsLabel.TextColor3 = Color3.new(1, 1, 1)
StatsLabel.TextWrapped = true
StatsLabel.TextXAlignment = Enum.TextXAlignment.Left
StatsLabel.Text = "📦 Collected: 0\n🥤 Sprite Cranberry chance: 0.00%\n⏳ Remaining to avg: ~1000"

local GiftsTitle = Instance.new("TextLabel")
GiftsTitle.Parent = MainFrame
GiftsTitle.BackgroundTransparency = 1
GiftsTitle.Position = UDim2.new(0.05, 0, 0, 160)
GiftsTitle.Size = UDim2.new(0.9, 0, 0, 20)
GiftsTitle.Font = Enum.Font.GothamBold
GiftsTitle.TextSize = 13
GiftsTitle.TextColor3 = Color3.fromRGB(255, 200, 50)
GiftsTitle.TextXAlignment = Enum.TextXAlignment.Left
GiftsTitle.Text = "🎁 Last 3 Gifts:"

local GiftContainer = Instance.new("Frame")
GiftContainer.Parent = MainFrame
GiftContainer.BackgroundTransparency = 1
GiftContainer.Position = UDim2.new(0.05, 0, 0, 185)
GiftContainer.Size = UDim2.new(0.9, 0, 0, 145)

local GiftFrames = {}

for i = 1, 3 do
    local frame = Instance.new("Frame")
    frame.Parent = GiftContainer
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    frame.Position = UDim2.new(0, 0, 0, (i - 1) * 48)
    frame.Size = UDim2.new(1, 0, 0, 45)
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    
    local vpf = Instance.new("ViewportFrame")
    vpf.Parent = frame
    vpf.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    vpf.Position = UDim2.new(0, 3, 0, 3)
    vpf.Size = UDim2.new(0, 39, 0, 39)
    vpf.Visible = false
    Instance.new("UICorner", vpf).CornerRadius = UDim.new(0, 4)
    
    local cam = Instance.new("Camera")
    cam.Parent = vpf
    vpf.CurrentCamera = cam
    
    local label = Instance.new("TextLabel")
    label.Parent = frame
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, 5, 0, 0)
    label.Size = UDim2.new(1, -10, 1, 0)
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = i .. ". ---"
    
    GiftFrames[i] = {frame = frame, vpf = vpf, cam = cam, label = label}
end

local function SetupViewportCamera(vpf, cam, model)
    for _, c in pairs(vpf:GetChildren()) do
        if c:IsA("Model") or c:IsA("BasePart") then c:Destroy() end
    end
    
    local clone
    if model:IsA("Model") then
        clone = model:Clone()
    else
        clone = Instance.new("Model")
        local part = model:Clone()
        part.Parent = clone
        clone.PrimaryPart = part
    end
    
    clone.Parent = vpf
    
    local cf, size
    if clone:IsA("Model") and clone.PrimaryPart then
        cf, size = clone:GetBoundingBox()
    elseif clone:IsA("Model") then
        local primary = clone:FindFirstChildWhichIsA("BasePart")
        if primary then
            clone.PrimaryPart = primary
            cf, size = clone:GetBoundingBox()
        else
            return
        end
    else
        return
    end
    
    clone:PivotTo(CFrame.new(0, 0, 0))
    
    local maxSize = math.max(size.X, size.Y, size.Z)
    local distance = maxSize * 2
    
    cam.CFrame = CFrame.new(Vector3.new(distance * 0.7, distance * 0.5, distance * 0.7), Vector3.new(0, 0, 0))
end

local function UpdateUI()
    local chance = 1 - (0.999 ^ TotalGifts)
    local remaining = math.max(0, 1000 - TotalGifts)
    StatsLabel.Text = string.format(
        "📦 Collected: %d\n🥤 Sprite Cranberry chance: %.2f%%\n⏳ Remaining to avg: ~%d",
        TotalGifts,
        chance * 100,
        remaining
    )
    
    local colors = {"🟢", "🟡", "🔴"}
    for i = 1, 3 do
        local gf = GiftFrames[i]
        if LastGifts[i] then
            if Use3D and LastGifts[i].model then
                gf.vpf.Visible = true
                gf.label.Position = UDim2.new(0, 47, 0, 0)
                gf.label.Size = UDim2.new(1, -52, 1, 0)
                gf.label.Text = colors[i] .. " " .. LastGifts[i].name
                
                pcall(function()
                    SetupViewportCamera(gf.vpf, gf.cam, LastGifts[i].model)
                end)
            else
                gf.vpf.Visible = false
                gf.label.Position = UDim2.new(0, 5, 0, 0)
                gf.label.Size = UDim2.new(1, -10, 1, 0)
                gf.label.Text = colors[i] .. " " .. i .. ". " .. (LastGifts[i].name or LastGifts[i])
            end
        else
            gf.vpf.Visible = false
            gf.label.Position = UDim2.new(0, 5, 0, 0)
            gf.label.Size = UDim2.new(1, -10, 1, 0)
            gf.label.Text = i .. ". ---"
        end
    end
    
    local col = Enabled and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(200, 50, 50)
    local txt = Enabled and "TP: ON" or "TP: OFF"
    Button.BackgroundColor3 = col
    Button.Text = txt
    MinBtn.BackgroundColor3 = col
    MinBtn.Text = txt
end

local function AddGift(name, model)
    local clonedModel = nil
    if Use3D and model then
        pcall(function()
            clonedModel = model:Clone()
        end)
    end
    local data = {name = name, model = clonedModel}
    table.insert(LastGifts, 1, data)
    if #LastGifts > 3 then 
        local old = table.remove(LastGifts)
        if old and old.model then
            old.model:Destroy()
        end
    end
    TotalGifts = TotalGifts + 1
    UpdateUI()
end

local function StartMain()
    SelectFrame.Visible = false
    MainFrame.Visible = true
    MinBtn.Visible = true
    UpdateUI()
end

Btn3D.MouseButton1Click:Connect(function()
    Use3D = true
    StartMain()
end)

BtnText.MouseButton1Click:Connect(function()
    Use3D = false
    StartMain()
end)

CloseBtn.MouseButton1Click:Connect(function()
    Minimized = true
    MainFrame.Visible = false
    MinBtn.Visible = true
end)

MinBtn.MouseButton1Click:Connect(function()
    Minimized = false
    MainFrame.Visible = true
end)

Button.MouseButton1Click:Connect(function()
    Enabled = not Enabled
    UpdateUI()
end)

local Connection
Connection = Folder.ChildAdded:Connect(function(child)
    if not _G.AutoTP_Running then
        Connection:Disconnect()
        return
    end
    if not Enabled then return end
    task.wait(0.1)
    
    local Char = LocalPlayer.Character
    local HRP = Char and Char:FindFirstChild("HumanoidRootPart")
    
    if HRP and child then
        local ok, targetCF = pcall(function() return child:GetPivot() end)
        if ok and targetCF then
            HRP.CFrame = targetCF + Vector3.new(0, 3, 0)
            AddGift(child.Name, child)
        end
    end
end)

UpdateUI()
