-- GitHub Repository Configuration
local GITHUB_USER = "gag-link"
local REPO_NAME = "Auto-Utilities-Hub"
local BRANCH = "main"
local BASE_URL = string.format("https://raw.githubusercontent.com/%s/%s/%s/", GITHUB_USER, REPO_NAME, BRANCH)

local function fetchModule(fileName)
    local url = BASE_URL .. fileName
    local success, result = pcall(function() return game:HttpGet(url) end)
    if success then
        return loadstring(result)()
    else
        warn("Failed to load module: " .. fileName)
    end
end

-- Initialize Modules
local ConfigHandler = fetchModule("Config.lua")
local Utils = fetchModule("Utils.lua")
local Core = fetchModule("Core.lua")(ConfigHandler, Utils)
local Config = ConfigHandler.Settings

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInput = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer
local Networking = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))

-- Load WindUI
local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/main.lua"))()

local Window = WindUI:CreateWindow({
    Title = "Auto Utilities Hub",
    Icon = "box",
    Author = "Modular Edition",
    Folder = "AutoDropper",
    Size = UDim2.fromOffset(580, 460),
    Transparent = true,
    Theme = "Dark"
})

local Tabs = {
    Farming   = Window:Tab({ Title = "Farming", Icon = "tractor" }),
    Target    = Window:Tab({ Title = "Target Mail", Icon = "target" }),
    Transfer  = Window:Tab({ Title = "Transfer Drop", Icon = "truck" }),
    Shop      = Window:Tab({ Title = "Shop", Icon = "shopping-cart" }),
    Inventory = Window:Tab({ Title = "Inventory", Icon = "backpack" }),
    Settings  = Window:Tab({ Title = "Settings", Icon = "settings" })
}

-- ─── Compatibility Wrapper for UI Updates ────────────────────────────────────
-- WindUI handles paragraph updates slightly differently, this safely wraps it 
-- so CoreLogic doesn't have to change.
local function createUIProxy(uiElement)
    return {
        SetDesc = function(self, text)
            pcall(function() uiElement:SetDesc(text) end)
            pcall(function() uiElement:Set({ Desc = text }) end)
        end
    }
end

-- ─── 0. FARMING TAB ──────────────────────────────────────────────────────────

Tabs.Farming:Section({ Title = "Auto Collect Configuration" })

Tabs.Farming:Toggle({ 
    Title = "Enable Auto Collect", 
    Value = Config.AutoCollectEnabled, 
    Callback = function(Value) Config.AutoCollectEnabled = Value; ConfigHandler.Save() end 
})

Tabs.Farming:Input({ 
    Title = "Minimum Size", 
    Value = tostring(Config.SizeThresholdMin), 
    Callback = function(Text) local v = tonumber(Text); if v then Config.SizeThresholdMin = v; ConfigHandler.Save() end end 
})

Tabs.Farming:Input({ 
    Title = "Maximum Size", 
    Value = tostring(Config.SizeThresholdMax), 
    Callback = function(Text) local v = tonumber(Text); if v then Config.SizeThresholdMax = v; ConfigHandler.Save() end end 
})

Tabs.Farming:Slider({ 
    Title = "Plot Scan Interval (Seconds)", 
    Value = Config.PollInterval, 
    Min = 1, 
    Max = 15, 
    Step = 1, 
    Callback = function(Value) Config.PollInterval = Value; ConfigHandler.Save() end 
})

Tabs.Farming:Section({ Title = "Auto Seller Configuration" })

Tabs.Farming:Toggle({
    Title = "Enable Auto Seller", 
    Value = Config.AutoSellEnabled,
    Callback = function(Value)
        Config.AutoSellEnabled = Value; ConfigHandler.Save()
        if Value then
            local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
            if bp then for _, item in ipairs(bp:GetChildren()) do task.spawn(Core.handleAutoSell, item) end end
            if LocalPlayer.Character then for _, item in ipairs(LocalPlayer.Character:GetChildren()) do task.spawn(Core.handleAutoSell, item) end end
        end
    end
})

local SellThresholdInput
SellThresholdInput = Tabs.Farming:Input({
    Title = "Sell Threshold (Base Value)", 
    Value = Utils.formatSuffix(Config.SellThreshold), 
    Callback = function(Text)
        local c = Utils.parseInputNumber(Text)
        if c then 
            Config.SellThreshold = c
            ConfigHandler.Save()
            pcall(function() SellThresholdInput:SetValue(Utils.formatSuffix(c)) end)
            WindUI:Notify({ Title = "Updated", Content = "$" .. Utils.formatSuffix(c), Duration = 2 }) 
        end
    end
})

-- ─── 1. TARGET MODE TAB (MAILING) ────────────────────────────────────────────

local TargetProgress = Tabs.Target:Paragraph({ Title = "Status & Progress", Desc = "Status: Idle\nReady to mail." })
local TargetProxy = createUIProxy(TargetProgress)

Tabs.Target:Button({ 
    Title = "▶ Execute Mail Sequence", 
    Callback = function() task.spawn(function() Core.ExecuteTargetMailSequence(TargetProxy) end) end 
})

Tabs.Target:Input({
    Title = "Recipient Username", 
    Value = Config.TargetUsername, 
    Callback = function(Text) Config.TargetUsername = Text; ConfigHandler.Save() end
})

local TargetInput
TargetInput = Tabs.Target:Input({
    Title = "Target Value to Mail (1x)", 
    Value = Utils.formatSuffix(Config.TargetValue), 
    Callback = function(Text)
        local c = Utils.parseInputNumber(Text)
        if c then Config.TargetValue = c; ConfigHandler.Save(); pcall(function() TargetInput:SetValue(Utils.formatSuffix(c)) end) end
    end
})

local MarginInput
MarginInput = Tabs.Target:Input({
    Title = "Margin Value (1x)", 
    Value = Utils.formatSuffix(Config.Margin), 
    Callback = function(Text)
        local c = Utils.parseInputNumber(Text)
        if c then Config.Margin = c; ConfigHandler.Save(); pcall(function() MarginInput:SetValue(Utils.formatSuffix(c)) end) end
    end
})

Tabs.Target:Slider({ Title = "Items Per Mail", Value = Config.MailBatchSize, Min = 1, Max = 20, Step = 1, Callback = function(V) Config.MailBatchSize = V; ConfigHandler.Save() end })
Tabs.Target:Slider({ Title = "Cooldown Between Mails (s)", Value = Config.MailCooldown, Min = 2, Max = 60, Step = 1, Callback = function(V) Config.MailCooldown = V; ConfigHandler.Save() end })

local PlanDisplay 
local PlanProxy 
Tabs.Target:Button({
    Title = "Preview Mail Plan",
    Callback = function()
        task.spawn(function()
            PlanProxy:SetDesc("Calculating mail plan... Please wait.")
            local originalMode = Config.Mode; Config.Mode = "target" 
            local allFruits = Core.getFruitsFromBackpack()
            if #allFruits == 0 then PlanProxy:SetDesc("Backpack empty."); Config.Mode = originalMode; return end
            Core.enrichWithValues(allFruits); local queue = Core.selectQueue(allFruits); Config.Mode = originalMode 
            if #queue == 0 then PlanProxy:SetDesc("No fruits match limits."); return end
            local planTotal = 0; for _, fruit in ipairs(queue) do planTotal = planTotal + fruit.sellValue end
            PlanProxy:SetDesc("Fruits Planned for Mail: " .. #queue .. "\n────────────────────────────────\nTotal Planned Value: $" .. Utils.formatSuffix(planTotal))
        end)
    end
})
PlanDisplay = Tabs.Target:Paragraph({ Title = "Mail Plan Preview", Desc = "Click preview above to calculate the bin-packing queue." })
PlanProxy = createUIProxy(PlanDisplay)

-- ─── 2. TRANSFER MODE TAB (DROPPING) ─────────────────────────────────────────

local TransferProgress = Tabs.Transfer:Paragraph({ Title = "Status & Progress", Desc = "Status: Idle\nDropped: 0/0\nSkipped: 0\nRemaining: 0" })
local TransferProxy = createUIProxy(TransferProgress)

Tabs.Transfer:Button({ Title = "▶ Execute Transfer Sequence", Callback = function() task.spawn(function() Core.ExecuteDropSequence("transfer", TransferProxy) end) end })

local ThresholdInput
ThresholdInput = Tabs.Transfer:Input({
    Title = "Transfer Minimum (Base Value)", 
    Value = Utils.formatSuffix(Config.ValueThreshold), 
    Callback = function(Text)
        local c = Utils.parseInputNumber(Text)
        if c then Config.ValueThreshold = c; ConfigHandler.Save(); pcall(function() ThresholdInput:SetValue(Utils.formatSuffix(c)) end) end
    end
})

-- ─── 3. SHOP TAB ─────────────────────────────────────────────────────────────

Tabs.Shop:Section({ Title = "Seeds" })

Tabs.Shop:Toggle({
    Title = "Enable Auto Buy Seeds", 
    Value = Config.AutoBuySeedEnabled,
    Callback = function(Value) 
        Config.AutoBuySeedEnabled = Value; ConfigHandler.Save()
        if Value then Utils.snipeItems("SeedShop", Config.SelectedSeeds, Networking.SeedShop.PurchaseSeed) end
    end
})

Tabs.Shop:Dropdown({ 
    Title = "Target Seeds", 
    Values = Utils.getShopItems("SeedShop"), 
    Multi = true, 
    Value = Config.SelectedSeeds, 
    Callback = function(Value) Config.SelectedSeeds = Value; ConfigHandler.Save() end 
})

Tabs.Shop:Section({ Title = "Gears" })

Tabs.Shop:Toggle({
    Title = "Enable Auto Buy Gears", 
    Value = Config.AutoBuyGearEnabled,
    Callback = function(Value) 
        Config.AutoBuyGearEnabled = Value; ConfigHandler.Save()
        if Value then Utils.snipeItems("GearShop", Config.SelectedGears, Networking.GearShop.PurchaseGear) end
    end
})

Tabs.Shop:Dropdown({ 
    Title = "Target Gears", 
    Values = Utils.getShopItems("GearShop"), 
    Multi = true, 
    Value = Config.SelectedGears, 
    Callback = function(Value) Config.SelectedGears = Value; ConfigHandler.Save() end 
})

-- ─── 4. INVENTORY TAB ────────────────────────────────────────────────────────

local InvDisplay
local InvProxy
Tabs.Inventory:Button({
    Title = "Refresh Inventory",
    Callback = function()
        task.spawn(function()
            InvProxy:SetDesc("Scanning and updating values... Please wait.")
            local allFruits = Core.getFruitsFromBackpack()
            if #allFruits == 0 then InvProxy:SetDesc("Your backpack is completely empty."); return end
            Core.enrichWithValues(allFruits)
            local totalValue, under10m, mid10m50m, over50m = 0, 0, 0, 0
            for _, fruit in ipairs(allFruits) do 
                local v = fruit.sellValue; totalValue = totalValue + v 
                if v >= 50000000 then over50m = over50m + 1 elseif v >= 10000000 then mid10m50m = mid10m50m + 1 else under10m = under10m + 1 end
            end
            InvProxy:SetDesc("Total Fruits: " .. #allFruits .. "\nTotal Base Worth: $" .. Utils.formatCommas(totalValue) .. "\n────────────────────────────────\nValue Breakdown:\n• Under 10M: " .. under10m .. " fruits\n• 10M - 50M: " .. mid10m50m .. " fruits\n• 50M+: " .. over50m .. " fruits")
        end)
    end
})
InvDisplay = Tabs.Inventory:Paragraph({ Title = "Current Fruits", Desc = "Click refresh above to fetch and categorize your inventory." })
InvProxy = createUIProxy(InvDisplay)

-- ─── 5. SETTINGS TAB ─────────────────────────────────────────────────────────

Tabs.Settings:Toggle({ Title = "Skip Favorited Fruits (Global)", Value = Config.SkipFavorited, Callback = function(V) Config.SkipFavorited = V; ConfigHandler.Save() end })
Tabs.Settings:Slider({ Title = "Batch Size (Transfer)", Value = Config.BatchSize, Min = 1, Max = 10, Step = 1, Callback = function(V) Config.BatchSize = V; ConfigHandler.Save() end })
Tabs.Settings:Slider({ Title = "Max Total Drops (Transfer)", Value = Config.MaxTotalDrops, Min = 1, Max = 200, Step = 1, Callback = function(V) Config.MaxTotalDrops = V; ConfigHandler.Save() end })

-- ─── STARTUP WAIT & LOOPS ────────────────────────────────────────────────────

print("[AutoScript] UI Loaded. Waiting for game to finish loading...")

task.spawn(function()
    while LocalPlayer:GetAttribute("LoadingScreenDone") ~= true do
        VirtualInput:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.1)
        VirtualInput:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        task.wait(0.5)
    end
    print("[AutoScript] Player loaded. Starting automations...")
end)

-- Background Loops
local inventoryFullWarningPrinted = false
task.spawn(function()
    while true do
        task.wait(Config.PollInterval)
        if not Config.AutoCollectEnabled then continue end

        if Core.isInventoryFull() then
            if not inventoryFullWarningPrinted then warn("[AutoCollect] Inventory full! Pausing."); inventoryFullWarningPrinted = true end
            continue
        else inventoryFullWarningPrinted = false end

        local plot = Core.getPlayerPlot()
        if not plot then continue end
        local plantsFolder = plot:FindFirstChild("Plants")
        if not plantsFolder then continue end

        for _, plant in ipairs(plantsFolder:GetChildren()) do
            local fruitsFolder = plant:FindFirstChild("Fruits")
            if fruitsFolder then
                for _, fruit in ipairs(fruitsFolder:GetChildren()) do
                    if Core.shouldCollect(fruit) and not Core.isInventoryFull() then
                        Core.collectFruit(fruit)
                        task.wait(Config.CollectDelay)
                    end
                end
            end
        end
    end
end)

Core.watchContainerForAutoSell(LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:WaitForChild("Backpack"))
if LocalPlayer.Character then Core.watchContainerForAutoSell(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    Core.watchContainerForAutoSell(newCharacter)
end)

task.spawn(function()
    local stockValues = ReplicatedStorage:WaitForChild("StockValues", 10)
    if not stockValues then return end
    
    local seedShopFolder = stockValues:FindFirstChild("SeedShop")
    if seedShopFolder then
        local unixLastRestockSeed = seedShopFolder:FindFirstChild("UnixLastRestock")
        if unixLastRestockSeed then
            unixLastRestockSeed.Changed:Connect(function()
                if Config.AutoBuySeedEnabled then Utils.snipeItems("SeedShop", Config.SelectedSeeds, Networking.SeedShop.PurchaseSeed) end
            end)
        end
    end

    local gearShopFolder = stockValues:FindFirstChild("GearShop")
    if gearShopFolder then
        local unixLastRestockGear = gearShopFolder:FindFirstChild("UnixLastRestock")
        if unixLastRestockGear then
            unixLastRestockGear.Changed:Connect(function()
                if Config.AutoBuyGearEnabled then Utils.snipeItems("GearShop", Config.SelectedGears, Networking.GearShop.PurchaseGear) end
            end)
        end
    end
end)
