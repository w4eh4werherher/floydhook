local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Create mobile button
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
ScreenGui.ResetOnSpawn = false -- Prevent GUI from disappearing on respawn

local AimButton = Instance.new("TextButton")
AimButton.Size = UDim2.new(0, 100, 0, 100) -- Made button bigger
AimButton.Position = UDim2.new(0.85, 0, 0.5, 0) -- Positioned on right side of screen
AimButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- Start red (off)
AimButton.BackgroundTransparency = 0.3 -- Made more visible
AimButton.Text = "AIM OFF"
AimButton.TextColor3 = Color3.fromRGB(255, 255, 255) -- White text
AimButton.TextSize = 24 -- Bigger text
AimButton.Font = Enum.Font.GothamBold -- Bold font
AimButton.Parent = ScreenGui
AimButton.Active = true
AimButton.Draggable = true
AimButton.AutoButtonColor = true -- Button darkens when pressed
AimButton.BorderSizePixel = 2
AimButton.BorderColor3 = Color3.fromRGB(255, 255, 255)

-- Configuration
local CONFIG = {
    AimKey = Enum.KeyCode.Q,
    Smoothing = 0.85,
    TargetPart = "HumanoidRootPart",
    MaxDistance = 2500,
    Prediction = 0.163,
    AirPrediction = 0.145,
    UpdateRate = 1/3000,
    IsMobile = false
}

local CurrentTarget = nil
local IsAiming = false -- Start disabled
local LastUpdate = 0

local function IsTargetValid(Player)
    if not Player or not Player.Character then return false end
    
    local Character = Player.Character
    local Humanoid = Character:FindFirstChild("Humanoid")
    local TargetPart = Character:FindFirstChild(CONFIG.TargetPart)
    
    if not Humanoid or not TargetPart or Humanoid.Health <= 0 then return false end
    
    local _, OnScreen = Camera:WorldToScreenPoint(TargetPart.Position)
    if not OnScreen then return false end
    
    return true
end

local function GetClosestPlayer()
    if CurrentTarget and IsTargetValid(CurrentTarget) then
        return CurrentTarget
    end

    local ClosestPlayer = nil
    local ShortestDistance = math.huge
    local MousePos = UserInputService:GetMouseLocation()

    for _, Player in pairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer then
            local Character = Player.Character
            if Character then
                local Humanoid = Character:FindFirstChild("Humanoid")
                local TargetPart = Character:FindFirstChild(CONFIG.TargetPart)
                
                if Humanoid and Humanoid.Health > 0 and TargetPart then
                    local Distance = (TargetPart.Position - Camera.CFrame.Position).Magnitude
                    if Distance > CONFIG.MaxDistance then continue end
                    
                    local ScreenPoint, OnScreen = Camera:WorldToScreenPoint(TargetPart.Position)
                    if OnScreen then
                        local ScreenDistance = (Vector2.new(MousePos.X, MousePos.Y) - Vector2.new(ScreenPoint.X, ScreenPoint.Y)).Magnitude
                        if ScreenDistance < ShortestDistance then
                            ClosestPlayer = Player
                            ShortestDistance = ScreenDistance
                        end
                    end
                end
            end
        end
    end
    
    return ClosestPlayer
end

-- Handle mobile button
local function ToggleAim()
    IsAiming = not IsAiming
    AimButton.BackgroundColor3 = IsAiming and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
    AimButton.Text = IsAiming and "AIM ON" or "AIM OFF"
    if not IsAiming then
        CurrentTarget = nil
    end
end

AimButton.MouseButton1Click:Connect(function()
    CONFIG.IsMobile = true
    ToggleAim()
end)

AimButton.TouchTap:Connect(function()
    CONFIG.IsMobile = true
    ToggleAim()
end)

-- Handle keyboard input
UserInputService.InputBegan:Connect(function(Input, GameProcessed)
    if not GameProcessed and Input.KeyCode == CONFIG.AimKey and not CONFIG.IsMobile then
        ToggleAim()
    end
end)

RunService.RenderStepped:Connect(function()
    local CurrentTime = tick()
    if CurrentTime - LastUpdate < CONFIG.UpdateRate then return end
    LastUpdate = CurrentTime

    if IsAiming then
        if not CurrentTarget or not IsTargetValid(CurrentTarget) then
            CurrentTarget = GetClosestPlayer()
        end
        
        if CurrentTarget and CurrentTarget.Character then
            local Humanoid = CurrentTarget.Character:FindFirstChild("Humanoid")
            local TargetPart = CurrentTarget.Character:FindFirstChild(CONFIG.TargetPart)
            
            if Humanoid and Humanoid.Health > 0 and TargetPart then
                local Velocity = TargetPart.Velocity
                local Distance = (TargetPart.Position - Camera.CFrame.Position).Magnitude
                local PredictionOffset = Vector3.new(0, 0, 0)

                if Velocity.Magnitude > 0 then
                    if Humanoid.Jump or Velocity.Y > 1 then
                        -- Separate axis prediction for better accuracy
                        local XZSpeed = Vector3.new(Velocity.X, 0, Velocity.Z).Magnitude
                        local YSpeed = math.abs(Velocity.Y)
                        
                        -- Reduce prediction more as Y velocity increases
                        local YMultiplier = math.clamp(1 - (YSpeed / 50), 0.4, 1)
                        PredictionOffset = Vector3.new(
                            Velocity.X * CONFIG.AirPrediction * YMultiplier,
                            Velocity.Y * CONFIG.AirPrediction * 0.7,
                            Velocity.Z * CONFIG.AirPrediction * YMultiplier
                        )
                        
                        -- Minimal gravity compensation
                        local GravityCompensation = Vector3.new(0, math.abs(Velocity.Y) * 0.065, 0)
                        PredictionOffset = PredictionOffset + GravityCompensation
                    else
                        local SpeedMultiplier = math.clamp(Velocity.Magnitude / 18, 0.85, 1.15)
                        PredictionOffset = Velocity * (CONFIG.Prediction * SpeedMultiplier)
                    end
                    
                    -- Adjust prediction based on distance - increased range for more movement at distance
                    local DistanceScale = math.clamp(Distance / 300, 1, 1.8)
                    PredictionOffset = PredictionOffset * DistanceScale
                end

                local PredictedPosition = TargetPart.Position + PredictionOffset
                local _, OnScreen = Camera:WorldToScreenPoint(PredictedPosition)
                
                if OnScreen then
                    local TargetAim = (PredictedPosition - Camera.CFrame.Position).Unit
                    local CurrentLook = Camera.CFrame.LookVector
                    
                    local BaseSmoothing = CONFIG.Smoothing
                    -- Adjust smoothing based on distance - less smoothing at greater distances
                    local DistanceFactor = math.clamp(1 - (Distance / CONFIG.MaxDistance), 0.6, 1)
                    local SpeedFactor = math.clamp(1 - (Velocity.Magnitude / 40), 0.8, 1.1)
                    local AdaptiveSmoothing = BaseSmoothing * SpeedFactor * DistanceFactor
                    
                    local NewLook = CurrentLook:Lerp(TargetAim, AdaptiveSmoothing)
                    Camera.CFrame = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + NewLook)
                end
            end
        end
    end
end)
