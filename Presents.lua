local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local TARGET_NICKNAME = "CRISTIAN2012q" -- Ник, для которого работает скрипт

-- Проверка ника (если это не ты, скрипт не сработает)
if LocalPlayer.Name ~= TARGET_NICKNAME then
	warn("Этот скрипт не для тебя!")
	script:Destroy()
	return
end

-- Папка с подарками
local presentsFolder = Workspace:WaitForChild("Presents", 10)
if not presentsFolder then
	warn("Папка Presents не найдена!")
	return
end

-------------------------------------------------------------------------
-- СОЗДАНИЕ ИНТЕРФЕЙСА (КНОПКИ)
-------------------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TeleportGUI"
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "ToggleBtn"
ToggleButton.Parent = ScreenGui
ToggleButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- Красный по умолчанию
ToggleButton.Position = UDim2.new(0, 10, 0.5, 0) -- Слева по центру
ToggleButton.Size = UDim2.new(0, 150, 0, 50)
ToggleButton.Font = Enum.Font.SourceSansBold
ToggleButton.TextSize = 20
ToggleButton.Text = "TP: ВЫКЛ"
ToggleButton.TextColor3 = Color3.new(1, 1, 1)

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = ToggleButton

-------------------------------------------------------------------------
-- ЛОГИКА
-------------------------------------------------------------------------
local isEnabled = false -- Включен ли авто-телепорт
local isSafe = true -- Безопасно ли (мало игроков)

-- Функция проверки количества игроков
local function checkPlayerCount()
	local count = #Players:GetPlayers()
	
	if count > 2 then
		-- Если больше 2 человек
		isSafe = false
		isEnabled = false -- Принудительно выключаем
		ToggleButton.BackgroundColor3 = Color3.fromRGB(100, 0, 0) -- Темно-красный
		ToggleButton.Text = "БЛОК (>2 Игроков)"
		ToggleButton.Active = false -- Запрещаем нажимать
	else
		-- Если 2 человека или меньше
		isSafe = true
		ToggleButton.Active = true -- Разрешаем нажимать
		if not isEnabled then
			ToggleButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
			ToggleButton.Text = "TP: ВЫКЛ"
		end
	end
end

-- Обработка нажатия кнопки
ToggleButton.MouseButton1Click:Connect(function()
	if not isSafe then return end -- Не даем включить, если опасно

	isEnabled = not isEnabled -- Переключаем состояние
	
	if isEnabled then
		ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0) -- Зеленый
		ToggleButton.Text = "TP: ВКЛЮЧЕНО"
	else
		ToggleButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- Красный
		ToggleButton.Text = "TP: ВЫКЛ"
	end
end)

-- Функция телепортации
local function teleportTo(object)
	if not isEnabled then return end
	if not isSafe then return end

	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	
	if hrp then
		-- Используем :GetPivot(), чтобы работало и для Part, и для Model
		local targetCFrame = object:GetPivot()
		
		if targetCFrame then
			-- Телепортируем немного выше объекта, чтобы не застрять
			hrp.CFrame = targetCFrame + Vector3.new(0, 3, 0)
		end
	end
end

-- Следим за новыми объектами в папке Presents
presentsFolder.ChildAdded:Connect(function(child)
	-- Ждем долю секунды, чтобы объект прогрузился физически
	task.wait(0.1)
	teleportTo(child)
end)

-- Подключаем проверку игроков
Players.PlayerAdded:Connect(checkPlayerCount)
Players.PlayerRemoved:Connect(checkPlayerCount)

-- Запускаем проверку сразу при старте
checkPlayerCount()
