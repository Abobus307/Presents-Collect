if _G.AutoTP_Running then
    _G.AutoTP_Running = false
    task.wait(0.2)
end
_G.AutoTP_Running = true

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local oldGui = PlayerGui:FindFirstChild("AutoTP_GUI")
if oldGui then oldGui:Destroy() end

local Folder = Workspace:WaitForChild("Presents", 10)
if not Folder then return end

local LastGifts = {}
local TotalGifts = 0
local Enabled = false

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoTP_GUI"
ScreenGui.Parent = PlayerGui
ScreenGui.ResetOnSpawn = false

local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
MainFrame.Position = UDim2.new(0, 10, 0.25, 0)
MainFrame.Size = UDim2.new(0, 230, 0, 280)
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", MainFrame)
stroke.Color = Color3.fromRGB(80, 80, 120)
stroke.Thickness = 2

local Button = Instance.new("TextButton")
Button.Parent = MainFrame
Button.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
Button.Position = UDim2.new(0.05, 0, 0, 10)
Button.Size = UDim2.new(0.9, 0, 0, 40)
Button.Font = Enum.Font.GothamBold
Button.TextSize = 18
Button.Text = "TP: OFF"
Button.TextColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 8)

local StatsLabel = Instance.new("TextLabel")
StatsLabel.Parent = MainFrame
StatsLabel.BackgroundTransparency = 1
StatsLabel.Position = UDim2.new(0.05, 0, 0, 55)
StatsLabel.Size = UDim2.new(0.9, 0, 0, 60)
StatsLabel.Font = Enum.Font.Gotham
StatsLabel.TextSize = 13
StatsLabel.TextColor3 = Color3.new(1, 1, 1)
StatsLabel.TextWrapped = true
StatsLabel.TextXAlignment = Enum.TextXAlignment.Left
StatsLabel.Text = "📦 Собрано: 0\n🎰 Шанс Sprite: 0.00%\n⏳ Осталось ~1000"

local GiftsTitle = Instance.new("TextLabel")
GiftsTitle.Parent = MainFrame
GiftsTitle.BackgroundTransparency = 1
GiftsTitle.Position = UDim2.new(0.05, 0, 0, 120)
GiftsTitle.Size = UDim2.new(0.9, 0, 0, 20)
GiftsTitle.Font = Enum.Font.GothamBold
GiftsTitle.TextSize = 14
GiftsTitle.TextColor3 = Color3.fromRGB(255, 200, 50)
GiftsTitle.TextXAlignment = Enum.TextXAlignment.Left
GiftsTitle.Text = "🎁 Последние 3 подарка:"

local GiftLabels = {}
for i = 1, 3 do
    local label = Instance.new("TextLabel")
    label.Parent = MainFrame
    label.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    label.Position = UDim2.new(0.05, 0, 0, 140 + (i - 1) * 42)
    label.Size = UDim2.new(0.9, 0, 0, 38)
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextWrapped = true
    label.Text = i .. ". ---"
    Instance.new("UICorner", label).CornerRadius = UDim.new(0, 6)
    GiftLabels[i] = label
end

local function UpdateUI()
    local chance = 1 - (0.999 ^ TotalGifts)
    local remaining = math.max(0, 1000 - TotalGifts)
    StatsLabel.Text = string.format("📦 Собрано: %d\n🎰 Шанс Sprite: %.2f%%\n⏳ Осталось ~%d", TotalGifts, chance * 100, remaining)
    
    local colors = {"🟢", "🟡", "🔴"}
    for i = 1, 3 do
        GiftLabels[i].Text = LastGifts[i] and (colors[i] .. " " .. i .. ". " .. LastGifts[i]) or (i .. ". ---")
    end
    
    Button.BackgroundColor3 = Enabled and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(200, 50, 50)
    Button.Text = Enabled and "TP: ON" or "TP: OFF"
end

local function AddGift(name)
    table.insert(LastGifts, 1, name)
    if #LastGifts > 3 then table.remove(LastGifts) end
    TotalGifts = TotalGifts + 1
    UpdateUI()
end

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
        local targetCF = child:GetPivot()
        if targetCF then
            HRP.CFrame = targetCF + Vector3.new(0, 3, 0)
            AddGift(child.Name)
        end
    end
end)

UpdateUI()
