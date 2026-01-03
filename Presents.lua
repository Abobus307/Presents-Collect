local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

if LocalPlayer.Name ~= "CRISTIAN2012q" then
	return
end

local Folder = Workspace:WaitForChild("Presents", 10)
if not Folder then return end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TPGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = gethui and gethui() or LocalPlayer:WaitForChild("PlayerGui")

local Button = Instance.new("TextButton")
Button.Size = UDim2.new(0, 160, 0, 50)
Button.Position = UDim2.new(0, 15, 0.5, -25)
Button.AnchorPoint = Vector2.new(0, 0.5)
Button.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
Button.Text = "TP: OFF"
Button.TextColor3 = Color3.new(1, 1, 1)
Button.Font = Enum.Font.GothamBold
Button.TextSize = 24
Button.AutoButtonColor = false
Button.Parent = ScreenGui

Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 12)

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
	if not HRP then return end
	task.wait(0.1)
	if child and child:IsA("BasePart") then
		HRP.CFrame = child.CFrame + Vector3.new(0, 5, 0)
	elseif child:IsA("Model") and child.PrimaryPart then
		HRP.CFrame = child:GetPrimaryPartCFrame() + Vector3.new(0, 5, 0)
	end
end)
