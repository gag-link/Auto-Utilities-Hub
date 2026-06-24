local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = {}

function Utils.formatCommas(n)
    local left, num, right = string.match(tostring(n), '^([^%d]*%d)(%d*)(.-)$')
    if left and num and right then
        return left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
    end
    return tostring(n)
end

function Utils.formatSuffix(n)
    n = tonumber(n)
    if not n then return "0" end
    if n >= 1e9 then
        return string.format("%.1f", n / 1e9):gsub("%.0$", "") .. "B"
    elseif n >= 1e6 then
        return string.format("%.1f", n / 1e6):gsub("%.0$", "") .. "M"
    elseif n >= 1e3 then
        return string.format("%.1f", n / 1e3):gsub("%.0$", "") .. "K"
    else
        return tostring(n)
    end
end

function Utils.parseInputNumber(str)
    local s = tostring(str):lower():gsub(" ", "")
    local multiplier = 1
    if s:match("k$") then multiplier = 1000; s = s:gsub("k$", "")
    elseif s:match("m$") then multiplier = 1000000; s = s:gsub("m$", "")
    elseif s:match("b$") then multiplier = 1000000000; s = s:gsub("b$", "") end
    s = s:gsub(",", "")
    local val = tonumber(s)
    if val then return math.floor(val * multiplier) end
    return nil
end

function Utils.getShopItems(shopName)
    local items = {}
    local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
    if stockValues then
        local shopFolder = stockValues:FindFirstChild(shopName)
        if shopFolder then
            local itemsFolder = shopFolder:FindFirstChild("Items")
            if itemsFolder then
                for _, item in ipairs(itemsFolder:GetChildren()) do
                    table.insert(items, item.Name)
                end
            end
        end
    end
    table.sort(items)
    return items
end

function Utils.snipeItems(shopName, selectedItems, purchaseRemote)
    local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
    local itemsFolder = stockValues and stockValues:FindFirstChild(shopName) and stockValues[shopName]:FindFirstChild("Items")

    for targetItem, isSelected in pairs(selectedItems) do
        if isSelected then
            local amountToBuy = 1 
            if itemsFolder then
                local itemValue = itemsFolder:FindFirstChild(targetItem)
                if itemValue and itemValue:IsA("NumberValue") and itemValue.Value > 0 then
                    amountToBuy = math.min(itemValue.Value, 50)
                end
            end
            print(string.format("[ShopSniper] %s: Attempting to buy %s (x%d)", shopName, targetItem, amountToBuy))
            task.spawn(function()
                for i = 1, amountToBuy do
                    purchaseRemote:Fire(targetItem)
                    task.wait(0.1) 
                end
            end)
        end
    end
end

return Utils
