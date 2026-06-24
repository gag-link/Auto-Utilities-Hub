return function(ConfigHandler, Utils)
    local Core = {}
    local Config = ConfigHandler.Settings
    
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local LocalPlayer = Players.LocalPlayer

    local Networking = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))
    local FruitProxyUtil = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("FruitProxyUtil"))
    local FruitValueCalc = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("FruitValueCalc"))

    local CACHE_FILE = "Fluent/AutoDropper/fruit_value_cache.json"

    function Core.getPlayerPlot()
        local plotId = LocalPlayer:GetAttribute("PlotId")
        if not plotId then return nil end
        local gardens = workspace:FindFirstChild("Gardens")
        if not gardens then return nil end
        return gardens:FindFirstChild("Plot" .. tostring(plotId))
    end

    function Core.isInventoryFull()
        local count = LocalPlayer:GetAttribute("FruitCount") or 0
        local capacity = LocalPlayer:GetAttribute("MaxFruitCapacity") or 100
        return count >= capacity
    end

    function Core.shouldCollect(fruit)
        local age = fruit:GetAttribute("Age")
        local maxAge = fruit:GetAttribute("MaxAge")
        local sizeMulti = fruit:GetAttribute("SizeMulti")
        local mutation = fruit:GetAttribute("Mutation")
        
        if not age or not maxAge or not sizeMulti then return false end
        if age < maxAge then return false end
        if sizeMulti >= Config.SizeThresholdMax then return false end
        if sizeMulti < Config.SizeThresholdMin then return true end
        if mutation and mutation ~= "" and mutation ~= "None" then return true end
        
        return false
    end

    function Core.collectFruit(fruit)
        local fruitName = fruit:GetAttribute("CorePartName") or fruit.Name
        local mutation = fruit:GetAttribute("Mutation") or "None"
        local sizeMulti = fruit:GetAttribute("SizeMulti") or 0
        local plantId = fruit:GetAttribute("PlantId")
        local fruitId = fruit:GetAttribute("FruitId")

        if not plantId and fruit.Parent and fruit.Parent.Parent then
            plantId = fruit.Parent.Parent:GetAttribute("PlantId") or fruit.Parent.Parent.Name
        end
        if not fruitId then fruitId = fruit.Name end
        if not plantId or not fruitId then return end

        Networking.Garden.CollectFruit:Fire(tostring(plantId), tostring(fruitId))
        print(string.format("[AutoCollect] %s [%s] SizeMulti=%.3f", fruitName, mutation, sizeMulti))
    end

    local autoSellSeen = {} 
    local autoSellProcessing = {} 

    local function isFruitItem(item)
        return item:GetAttribute("FruitName") and item:GetAttribute("Id") and item:GetAttribute("HarvestedFruit")
    end

    local function autoSellFruitItem(fruitId)
        local response = Networking.NPCS.SellFruit:Fire(fruitId)
        return response and response.Success == true
    end

    function Core.handleAutoSell(item)
        if not Config.AutoSellEnabled then return end
        task.wait(Config.AttributeWait)
        if not item or not item.Parent then return end
        if not isFruitItem(item) then return end

        local fruitId = item:GetAttribute("Id")
        local fruitName = item:GetAttribute("FruitName")
        local mutation = item:GetAttribute("Mutation") or "None"

        if autoSellSeen[fruitId] or autoSellProcessing[fruitId] then return end

        if Config.SkipFavorited and item:GetAttribute("IsFavorite") == true then
            autoSellSeen[fruitId] = true
            return
        end

        autoSellProcessing[fruitId] = true
        
        local sizeMulti = item:GetAttribute("SizeMultiplier") or 1
        local decayAlpha = item:GetAttribute("DecayAlpha") or 0
        local baseValue = math.floor(FruitValueCalc(fruitName, sizeMulti, mutation, LocalPlayer, decayAlpha))

        if baseValue < Config.SellThreshold then
            if not (Config.SkipFavorited and item:GetAttribute("IsFavorite") == true) and item.Parent then
                if autoSellFruitItem(fruitId) then
                    print(string.format("[AutoSeller] Sold %s [%s] — Base Value %d < Threshold %d", fruitName, mutation, baseValue, Config.SellThreshold))
                end
            end
        end

        autoSellSeen[fruitId] = true
        autoSellProcessing[fruitId] = nil
    end

    function Core.watchContainerForAutoSell(container)
        if not container then return end
        container.ChildAdded:Connect(function(item) task.spawn(Core.handleAutoSell, item) end)
        for _, item in ipairs(container:GetChildren()) do task.spawn(Core.handleAutoSell, item) end
    end

    function Core.getFruitsFromBackpack()
        local fruits, containers = {}, {}
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then table.insert(containers, backpack) end
        if LocalPlayer.Character then table.insert(containers, LocalPlayer.Character) end

        for _, container in ipairs(containers) do
            for _, item in ipairs(container:GetChildren()) do
                if isFruitItem(item) then
                    table.insert(fruits, {
                        proxy = item,
                        name = item:GetAttribute("FruitName"),
                        id = item:GetAttribute("Id"),
                        mutation = item:GetAttribute("Mutation") or "None",
                        weight = item:GetAttribute("Weight") or 0,
                        sellValue = 0,
                        isFavorite = item:GetAttribute("IsFavorite") == true,
                    })
                end
            end
        end
        return fruits
    end

    local function loadCache()
        if not isfile(CACHE_FILE) then return {} end
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CACHE_FILE)) end)
        return (ok and type(data) == "table") and data or {}
    end

    local function saveCache(cache)
        pcall(function() writefile(CACHE_FILE, HttpService:JSONEncode(cache)) end)
    end

    function Core.enrichWithValues(fruits)
        local cache = loadCache()
        local currentIds = {}
        for _, fruit in ipairs(fruits) do currentIds[fruit.id] = true end
        for id in pairs(cache) do if not currentIds[id] then cache[id] = nil end end

        for _, fruit in ipairs(fruits) do
            if cache[fruit.id] then
                fruit.sellValue = type(cache[fruit.id]) == "table" and (cache[fruit.id].v or 0) or tonumber(cache[fruit.id]) or 0
            else
                local sizeMulti = fruit.proxy:GetAttribute("SizeMultiplier") or 1
                local decayAlpha = fruit.proxy:GetAttribute("DecayAlpha") or 0
                local baseValue = FruitValueCalc(fruit.name, sizeMulti, fruit.mutation, LocalPlayer, decayAlpha)
                
                fruit.sellValue = math.floor(baseValue)
                cache[fruit.id] = fruit.sellValue
            end
        end
        saveCache(cache)
    end

    function Core.selectQueue(fruits)
        local queue, processableFruits = {}, {}
        for _, fruit in ipairs(fruits) do
            if Config.SkipFavorited and fruit.isFavorite then continue end
            table.insert(processableFruits, fruit)
        end

        if Config.Mode == "transfer" then
            for _, fruit in ipairs(processableFruits) do
                if fruit.sellValue >= Config.ValueThreshold then table.insert(queue, fruit) end
            end
        elseif Config.Mode == "target" then
            table.sort(processableFruits, function(a, b) return a.sellValue > b.sellValue end)
            local total = 0
            for _, fruit in ipairs(processableFruits) do
                if total >= Config.TargetValue then break end
                if total + fruit.sellValue <= (Config.TargetValue + Config.Margin) then
                    table.insert(queue, fruit)
                    total = total + fruit.sellValue
                end
            end
        end

        if Config.Mode == "transfer" and #queue > Config.MaxTotalDrops then
            local capped = {}
            for i = 1, Config.MaxTotalDrops do capped[i] = queue[i] end
            queue = capped
        end
        return queue
    end

    local function promoteFruit(fruit)
        if FruitProxyUtil.Pending then
            FruitProxyUtil.Pending.Equip = fruit.id
            FruitProxyUtil.Pending.Slots[fruit.id] = 1
        end
        pcall(function() FruitProxyUtil.RequestPromote(fruit.id) end)

        local deadline = os.clock() + Config.PromoteTimeout
        while os.clock() < deadline do
            if LocalPlayer.Character then
                for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
                    if child:IsA("Tool") and child:GetAttribute("Id") == fruit.id then return child end
                end
            end
            local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
            if bp then
                for _, child in ipairs(bp:GetChildren()) do
                    if child:IsA("Tool") and child:GetAttribute("Id") == fruit.id then return child end
                end
            end
            task.wait(0.1)
        end
        return nil
    end

    local function dropFruit(fruit)
        local droppedItems = workspace:FindFirstChild("DroppedItems") or workspace:WaitForChild("DroppedItems", 10)
        if not droppedItems then return false end

        for attempt = 1, 3 do
            Networking.DroppedItem.RequestDrop:Fire("HarvestedFruits", fruit.id)
            local deadline = os.clock() + 3
            while os.clock() < deadline do
                for _, child in ipairs(droppedItems:GetChildren()) do
                    if child:GetAttribute("ItemName") == fruit.id then return true end
                end
                task.wait(0.05)
            end
        end
        return false
    end

    local function waitForPickup(droppedIds, timeout)
        local droppedItems = workspace:FindFirstChild("DroppedItems") or workspace:WaitForChild("DroppedItems", 10)
        if not droppedItems then return false end

        local deadline = os.clock() + timeout
        while os.clock() < deadline do
            local count = 0
            for _, child in ipairs(droppedItems:GetChildren()) do
                if droppedIds[child:GetAttribute("ItemName")] then count = count + 1 end
            end
            if count == 0 then return true end
            task.wait(0.5)
        end
        return false
    end

    function Core.ExecuteDropSequence(mode, progressLabel)
        Config.Mode = mode
        ConfigHandler.Save()
        
        local function updateUI(text)
            pcall(function() progressLabel:SetDesc(text) end)
            print("[AutoDropper] " .. string.gsub(text, "\n", " | "))
        end

        updateUI("Status: Scanning backpack & evaluating cache...")
        local allFruits = Core.getFruitsFromBackpack()
        if #allFruits == 0 then return updateUI("Status: Idle.\nResult: No fruits found in backpack.") end

        Core.enrichWithValues(allFruits)
        local queue = Core.selectQueue(allFruits)
        if #queue == 0 then return updateUI("Status: Idle.\nResult: No fruits match your current Config limits.") end

        local totalDropped, totalSkipped, batchNum, totalQueued, i = 0, 0, 0, #queue, 1

        while i <= totalQueued do
            batchNum = batchNum + 1
            local batchEnd = math.min(i + Config.BatchSize - 1, totalQueued)
            updateUI(string.format("Status: Dropping Batch %d...\nDropped: %d/%d\nSkipped: %d\nRemaining: %d", batchNum, totalDropped, totalQueued, totalSkipped, totalQueued - (i - 1)))
                
            local droppedIds, batchDropped = {}, 0

            for b = i, batchEnd do
                local fruit = queue[b]
                if not fruit.proxy or not fruit.proxy.Parent then 
                    totalSkipped = totalSkipped + 1; continue 
                end

                if fruit.isFavorite then
                    fruit.proxy:SetAttribute("IsFavorite", nil)
                    Networking.Backpack.SetFruitFavorite:Fire(fruit.id, false)
                    task.wait(0.3)
                end

                local tool = promoteFruit(fruit)
                if not tool then totalSkipped = totalSkipped + 1; continue end

                local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if humanoid then humanoid:EquipTool(tool) end
                task.wait(0.1)

                if dropFruit(fruit) then
                    droppedIds[fruit.id] = true
                    batchDropped = batchDropped + 1
                    totalDropped = totalDropped + 1
                else
                    totalSkipped = totalSkipped + 1
                    if humanoid then humanoid:UnequipTools() end
                    task.wait(0.1)
                end
            end

            if batchDropped > 0 then
                updateUI(string.format("Status: Waiting for pickup (Batch %d)...\nDropped: %d/%d\nSkipped: %d", batchNum, totalDropped, totalQueued, totalSkipped))
                waitForPickup(droppedIds, Config.WaitTimeout)
                task.wait(0.3)
            end
            i = batchEnd + 1
        end
        updateUI(string.format("Status: Finished Sequence!\nSuccessfully Dropped: %d\nFailed/Skipped: %d", totalDropped, totalSkipped))
    end

    function Core.ExecuteTargetMailSequence(progressLabel)
        local function updateUI(text)
            pcall(function() progressLabel:SetDesc(text) end)
            print("[AutoMailer] " .. string.gsub(text, "\n", " | "))
        end

        if not Config.TargetUsername or Config.TargetUsername == "" then
            return updateUI("Status: Idle.\nResult: Please enter a Target Username.")
        end

        updateUI(string.format("Status: Fetching User ID for '%s'...", Config.TargetUsername))
        local success, recipientId = pcall(function()
            return Players:GetUserIdFromNameAsync(Config.TargetUsername)
        end)

        if not success or not recipientId then
            return updateUI("Status: Error.\nResult: Invalid username or Roblox API is down.")
        end

        updateUI("Status: Scanning backpack & evaluating cache...")
        local allFruits = Core.getFruitsFromBackpack()
        if #allFruits == 0 then 
            return updateUI("Status: Idle.\nResult: No fruits found in backpack.") 
        end

        Core.enrichWithValues(allFruits)
        
        local originalMode = Config.Mode
        Config.Mode = "target"
        local queue = Core.selectQueue(allFruits)
        Config.Mode = originalMode

        if #queue == 0 then 
            return updateUI("Status: Idle.\nResult: No fruits match your current Target limits.") 
        end

        local batches = {}
        local maxPerBatch = math.min(Config.MailBatchSize, 20)
        
        for i = 1, #queue, maxPerBatch do
            local batch = {}
            for j = i, math.min(i + maxPerBatch - 1, #queue) do
                table.insert(batch, queue[j])
            end
            table.insert(batches, batch)
        end

        updateUI(string.format("Status: Preparing %d mails...", #batches))
        local totalValueMailed = 0
        local totalFruitsMailed = 0

        for batchIndex, currentBatch in ipairs(batches) do
            local itemsTable = {}
            local batchValue = 0

            for i, fruit in ipairs(currentBatch) do
                if fruit.isFavorite then
                    fruit.proxy:SetAttribute("IsFavorite", nil)
                    Networking.Backpack.SetFruitFavorite:Fire(fruit.id, false)
                    task.wait(0.1)
                end

                itemsTable[i] = {
                    Category = "HarvestedFruits",
                    ItemKey = fruit.id,
                    Count = 1
                }
                batchValue = batchValue + fruit.sellValue
            end

            updateUI(string.format("Status: Sending Mail %d/%d...\nItems: %d\nBase Value: $%s", batchIndex, #batches, #itemsTable, Utils.formatSuffix(batchValue)))
            
            local batchNote = "Value: $" .. Utils.formatSuffix(batchValue)
            local mailSuccess, mailError = pcall(function()
                return Networking.Mailbox.SendBatch:Fire(recipientId, itemsTable, batchNote)
            end)

            if mailSuccess then
                totalValueMailed = totalValueMailed + batchValue
                totalFruitsMailed = totalFruitsMailed + #itemsTable
            else
                updateUI("Status: Error.\nResult: Failed to fire remote.\n" .. tostring(mailError))
                break
            end

            if batchIndex < #batches then
                updateUI(string.format("Status: Cooldown active.\nWaiting %d seconds before next mail...", Config.MailCooldown))
                task.wait(Config.MailCooldown)
            end
        end

        updateUI(string.format("Status: Finished Sequence!\nSuccessfully Mailed: %d fruits\nTo: %s (ID: %d)\nTotal Base Value: $%s", totalFruitsMailed, Config.TargetUsername, recipientId, Utils.formatSuffix(totalValueMailed)))
    end

    return Core
end
