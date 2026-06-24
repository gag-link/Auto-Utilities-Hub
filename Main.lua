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

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Auto Utilities Hub",
    SubTitle = "Modular Edition",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Farming   = Window:AddTab({ Title = "Farming", Icon = "tractor" }),
    Target    = Window:AddTab({ Title = "Target Mail", Icon = "target" }),
    Transfer  = Window:AddTab({ Title = "Transfer Drop", Icon = "truck" }),
    Shop      = Window:AddTab({ Title = "Shop", Icon = "shopping-cart" }),
    Inventory = Window:AddTab({ Title = "Inventory", Icon = "backpack" }),
    Settings  = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

-- ─── 0. FARMING TAB ──────────────────────────────────────────────────────────

Tabs.Farming:AddSection("Auto Collect Configuration")
Tabs.Farming:AddToggle("AutoCollectToggle", { Title = "Enable Auto Collect", Default = Config.AutoCollectEnabled, Callback = function(V) Config.AutoCollectEnabled = V; ConfigHandler.Save() end })
Tabs.Farming:AddInput("MinSizeInput", { Title = "Minimum Size", Default = tostring(Config.SizeThresholdMin), Numeric = true, Finished = true, Callback = function(T) local v = tonumber(T); if v then Config.SizeThresholdMin = v; ConfigHandler.Save() end end })
Tabs.Farming:AddInput("MaxSizeInput", { Title = "Maximum Size", Default = tostring(Config.SizeThresholdMax), Numeric = true, Finished = true, Callback = function(T) local v = tonumber(T); if v then Config.SizeThresholdMax = v; ConfigHandler.Save() end end })
Tabs.Farming:AddSlider("PollIntervalSlider", { Title = "Plot Scan Interval (Seconds)", Default = Config.PollInterval, Min = 1, Max = 15, Rounding = 1, Callback = function(V) Config.PollInterval = V; ConfigHandler.Save() end })

Tabs.Farming:AddSection("Auto Seller Configuration")
Tabs.Farming:AddToggle("AutoSellToggle", {
    Title = "Enable Auto Seller", Default = Config.AutoSellEnabled,
    Callback = function(Value)
        Config.AutoSellEnabled = Value; ConfigHandler.Save()
        if Value then
            local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
            if bp then for _, item in ipairs(bp:GetChildren()) do task.spawn(Core.handleAutoSell, item) end end
            if LocalPlayer.Character then for _, item in ipairs(LocalPlayer.Character:GetChildren()) do task.spawn(Core.handleAutoSell, item) end end
        end
    end
})
local SellThresholdInput = Tabs.Farming:AddInput("SellThresholdInput", {
    Title = "Sell Threshold (Base Value)", Default = Utils.formatSuffix(Config.SellThreshold), Numeric = false, Finished = true,
    Callback = function(Text)
        local c = Utils.parseInputNumber(Text)
        if c then Config.SellThreshold = c; ConfigHandler.Save(); pcall(function() SellThresholdInput:SetValue(Utils.formatSuffix(c)) end); Fluent:Notify({ Title = "Updated", Content = "$" .. Utils.formatSuffix(c), Duration = 2 }) end
    end
})

-- ─── 1. TARGET MODE TAB (MAILING) ────────────────────────────────────────────

local TargetProgress = Tabs.Target:AddParagraph({ Title = "Status & Progress", Content = "Status: Idle\nReady to mail." })

Tabs.Target:AddButton({ 
    Title = "▶ Execute Mail Sequence", 
    Callback = function() task.spawn(function() Core.ExecuteTargetMailSequence(TargetProgress) end) end 
})

local TargetUserInput = Tabs.Target:AddInput("TargetUsernameInput", {
    Title = "Recipient Username", Default = Config.TargetUsername, Numeric = false, Finished = true,
    Callback = function(Text) Config.TargetUsername = Text; ConfigHandler.Save() end
})

local TargetInput = Tabs.Target:AddInput("TargetValueInput", {
    Title = "Target Value to Mail", Default = Utils.formatSuffix(Config.TargetValue), Numeric = false, Finished = true,
    Callback = function(Text)
        local c = Utils.parseInputNumber(Text)
        if c then Config.TargetValue = c; ConfigHandler.Save(); pcall(function() TargetInput:SetValue(Utils.formatSuffix(c)) end) end
    end
})

local MarginInput = Tabs.Target:AddInput("MarginValueInput", {
    Title = "Margin Value", Default = Utils.formatSuffix(Config.Margin), Numeric = false, Finished = true,
    Callback = function(Text)
        local c = Utils.parseInputNumber(Text)
        if c then Config.Margin = c; ConfigHandler.Save(); pcall(function() MarginInput:SetValue(Utils.formatSuffix(c)) end) end
    end
})

Tabs.Target:AddSlider("MailBatchSizeSlider", { Title = "Items Per Mail", Default = Config.MailBatchSize, Min = 1, Max = 20, Rounding = 0, Callback = function(V) Config.MailBatchSize = V; ConfigHandler.Save() end })
Tabs.Target:AddSlider("MailCooldownSlider", { Title = "Cooldown Between Mails (s)", Default = Config.MailCooldown, Min = 2, Max = 60, Rounding = 0, Callback = function(V) Config.MailCooldown = V; ConfigHandler.Save() end })

local PlanDisplay 
Tabs.Target:AddButton({
    Title = "Preview Mail Plan",
    Callback = function()
        task.spawn(function()
            PlanDisplay:SetDesc("Calculating mail plan... Please wait.")
            local originalMode = Config.Mode; Config.Mode = "target" 
            local allFruits = Core.getFruitsFromBackpack()
            if #allFruits == 0 then PlanDisplay:SetDesc("Backpack empty."); Config.Mode = originalMode; return end
            Core.enrichWithValues(allFruits); local queue = Core.selectQueue(allFruits); Config.Mode = originalMode 
            if #queue == 0 then PlanDisplay:SetDesc("No fruits match limits."); return end
            local planTotal = 0; for _, fruit in ipairs(queue) do planTotal = planTotal + fruit.sellValue end
            PlanDisplay:SetDesc("Fruits Planned for Mail: " .. #queue .. "\n────────────────────────────────\nTotal Planned Value: $" .. Utils.formatSuffix(planTotal))
        end)
    end
})
PlanDisplay = Tabs.Target:AddParagraph({ Title = "Mail Plan Preview", Content = "Click preview above to calculate the bin-packing queue." })

-- ─── 2. TRANSFER MODE TAB (DROPPING) ─────────────────────────────────────────

local TransferProgress = Tabs.Transfer:AddParagraph({ Title = "Status & Progress", Content = "Status: Idle\nDropped: 0/0\nSkipped: 0\nRemaining: 0" })
Tabs.Transfer:AddButton({ Title = "▶ Execute Transfer Sequence", Callback = function() task.spawn(function() Core.ExecuteDropSequence("transfer", TransferProgress) end) end })

local ThresholdInput = Tabs.Transfer:AddInput("ThresholdValueInput", {
    Title = "Transfer Minimum (Base Value)", Default = Utils.formatSuffix(Config.ValueThreshold), Numeric = false, Finished = true,
    Callback = function(Text)
        local c = Utils.parseInputNumber(Text)
        if c then Config.ValueThreshold = c; ConfigHandler.Save(); pcall(function() ThresholdInput:SetValue(Utils.formatSuffix(c)) end) end
    end
})

-- ─── 3. SHOP TAB ─────────────────────────────────────────────────────────────

Tabs.Shop:AddSection("Seeds")
Tabs.Shop:AddToggle("AutoBuySeedToggle", {
    Title = "Enable Auto Buy Seeds", Default = Config.AutoBuySeedEnabled,
    Callback = function(Value) Config.AutoBuySeedEnabled = Value; ConfigHandler.Save()
        if Value then Utils.snipeItems("SeedShop", Config.SelectedSeeds, Networking.SeedShop.PurchaseSeed) end
    end
})
Tabs.Shop:AddDropdown("SeedDropdown", { Title = "Target Seeds", Values = Utils.getShopItems("SeedShop"), Multi = true, Default = Config.SelectedSeeds, Callback = function(Value) Config.SelectedSeeds = Value; ConfigHandler.Save() end })

Tabs.Shop:AddSection("Gears")
Tabs.Shop:AddToggle("AutoBuyGearToggle", {
    Title = "Enable Auto Buy Gears", Default = Config.AutoBuyGearEnabled,
    Callback = function(Value) Config.AutoBuyGearEnabled = Value; ConfigHandler.Save()
        if Value then Utils.snipeItems("GearShop", Config.SelectedGears, Networking.GearShop.PurchaseGear) end
    end
})
Tabs.Shop:AddDropdown("GearDropdown", { Title = "Target Gears", Values = Utils.getShopItems("GearShop"), Multi = true, Default = Config.SelectedGears, Callback = function(Value) Config.SelectedGears = Value; ConfigHandler.Save() end })

-- ─── 4. INVENTORY TAB ────────────────────────────────────────────────────────

local InvDisplay
Tabs.Inventory:AddButton({
    Title = "Refresh Inventory",
    Callback = function()
        task.spawn(function()
            InvDisplay:SetDesc("Scanning and updating values... Please wait.")
            local allFruits = Core.getFruitsFromBackpack()
            if #allFruits == 0 then InvDisplay:SetDesc("Your backpack is completely empty."); return end
            Core.enrichWithValues(allFruits)
            local totalValue, under10m, mid10m50m, over50m = 0, 0, 0, 0
            for _, fruit in ipairs(allFruits) do 
                local v = fruit.sellValue; totalValue = totalValue + v 
                if v >= 50000000 then over50m = over50m + 1 elseif v >= 10000000 then mid10m50m = mid10m50m + 1 else under10m = under10m + 1 end
            end
            InvDisplay:SetDesc("Total Fruits: " .. #allFruits .. "\nTotal Base Worth: $" .. Utils.formatCommas(totalValue) .. "\n────────────────────────────────\nValue Breakdown:\n• Under 10M: " .. under10m .. " fruits\n• 10M - 50M: " .. mid10m50m .. " fruits\n• 50M+: " .. over50m .. " fruits")
        end)
    end
})
InvDisplay = Tabs.Inventory:AddParagraph({ Title = "Current Fruits", Content = "Click refresh above to fetch and categorize your inventory." })

-- ─── 5. SETTINGS TAB ─────────────────────────────────────────────────────────

Tabs.Settings:AddToggle("SkipFavToggle", { Title = "Skip Favorited Fruits (Global)", Default = Config.SkipFavorited, Callback = function(V) Config.SkipFavorited = V; ConfigHandler.Save() end })
Tabs.Settings:AddSlider("BatchSizeSlider", { Title = "Batch Size (Transfer)", Default = Config.BatchSize, Min = 1, Max = 10, Rounding = 0, Callback = function(V) Config.BatchSize = V; ConfigHandler.Save() end })
Tabs.Settings:AddSlider("MaxDropsSlider", { Title = "Max Total Drops (Transfer)", Default = Config.MaxTotalDrops, Min = 1, Max = 200, Rounding = 0, Callback = function(V) Config.MaxTotalDrops = V; ConfigHandler.Save() end })

-- ─── STARTUP WAIT & LOOPS ────────────────────────────────────────────────────

Window:SelectTab(1)
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
