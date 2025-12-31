local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local MY_NAME = "CRISTIAN2012q"
local FRIEND_NAME = "GAMER_Cyber88"

if LocalPlayer.Name ~= MY_NAME then
	script:Destroy()
	return
end

local Folder = Workspace:WaitForChild("Presents", 10)
if not Folder then return end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoTP_GUI"
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
ScreenGui.ResetOnSpawn = false

local Button = Instance.new("TextButton")
Button.Name = "ToggleBtn"
Button.Parent = ScreenGui
Button.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
Button.Position = UDim2.new(0, 10, 0.5, 0)
Button.Size = UDim2.new(0, 160, 0, 50)
Button.Font = Enum.Font.SourceSansBold
Button.TextSize = 18
Button.Text = "TP: OFF"
Button.TextColor3 = Color3.new(1, 1, 1)

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = Button

local Enabled = false
local IsSafe = false

local function UpdateSafety()
	local count = #Players:GetPlayers()
	local friend = Players:FindFirstChild(FRIEND_NAME)
	
	-- ЛОГИКА ЗАЩИТЫ:
	-- 1. Если больше 2 человек -> ОПАСНО (даже если друг есть)
	if count > 2 then
		IsSafe = false
		Button.Text = "BLOCKED (>2 Players)"
	
	-- 2. Если друга нет -> ОПАСНО (даже если сервер пустой)
	elseif not friend then
		IsSafe = false
		Button.Text = "BLOCKED (No Gamer)"
	
	-- 3. Если <= 2 человек И друг есть -> БЕЗОПАСНО
	else
		IsSafe = true
	end

	if not IsSafe then
		Enabled = false -- Вырубаем скрипт
		Button.Active = false -- Запрещаем нажимать
		Button.BackgroundColor3 = Color3.fromRGB(100, 0, 0) -- Темно-красный
	else
		Button.Active = true -- Разрешаем нажимать
		if Enabled then
			Button.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
			Button.Text = "TP: ON"
		else
			Button.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
			Button.Text = "TP: OFF"
		end
	end
end

Button.MouseButton1Click:Connect(function()
	if not IsSafe then return end
	Enabled = not Enabled
	UpdateSafety()
end)

Folder.ChildAdded:Connect(function(child)
	if not Enabled then return end
	task.wait(0.1)
	
	local Char = LocalPlayer.Character
	local HRP = Char and Char:FindFirstChild("HumanoidRootPart")
	
	if HRP and child then
		local targetCF = child:GetPivot()
		if targetCF then
			HRP.CFrame = targetCF + Vector3.new(0, 3, 0)
		end
	end
end)

Players.PlayerAdded:Connect(UpdateSafety)
Players.PlayerRemoving:Connect(UpdateSafety) -- ИСПРАВЛЕНО ЗДЕСЬ

UpdateSafety()
