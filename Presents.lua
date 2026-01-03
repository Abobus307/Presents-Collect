local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

if LocalPlayer.Name ~= "CRISTIAN2012q" then
	return
end

local Folder = Workspace:WaitForChild("Presents", 10)
if not Folder then return end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local Button = Instance.new("TextButton")
Button.Size = UDim2.new(0, 160, 0, 50)
Button.Position = UDim2.new(0, 10, 0.5, -25)
Button.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
Button.Text = "TP: OFF"
Button.TextColor3 = Color3.new(1, 1, 1)
Button.Font = Enum.Font.GothamBold
Button.TextSize = 20
Button.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = Button

local Enabled = false

Button.MouseButton1Click:Connect(function()
	Enabled = not Enabled
	Button.BackgroundColor3 = Enabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
	Button.Text = Enabled and "TP: ON" or "TP: OFF"
end)

Folder.ChildAdded:Connect(function(child)
	if not Enabled then return end
	local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local HRP = Character:FindFirstChild("HumanoidRootPart")
	if HRP and child then
		HRP.CFrame = child:GetPivot() + Vector3.new(0, 4, 0)
	end
end)
