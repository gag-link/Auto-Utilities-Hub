local HttpService = game:GetService("HttpService")

local ConfigHandler = {}
local BASE_FOLDER = "Fluent"
local FOLDER_NAME = BASE_FOLDER .. "/AutoDropper"
local FILE_NAME = FOLDER_NAME .. "/config.json"

ConfigHandler.Settings = {
    Mode = "target",
    ValueThreshold = 100000000,
    Margin = 10000000,
    MaxTotalDrops = 50,
    BatchSize = 10,
    WaitTimeout = 60,
    PromoteTimeout = 8,
    SkipFavorited = false,
    
    TargetUsername = "",
    TargetValue = 150000000,
    MailBatchSize = 20,
    MailCooldown = 10,

    AutoSellEnabled = false,
    SellThreshold = 9000000,
    AttributeWait = 0.3,

    AutoCollectEnabled = false,
    SizeThresholdMin = 5.3,
    SizeThresholdMax = 33.0,
    PollInterval = 5.0,
    CollectDelay = 0.15,

    AutoBuySeedEnabled = false,
    SelectedSeeds = {},
    AutoBuyGearEnabled = false,
    SelectedGears = {}
}

function ConfigHandler.Save()
    if not isfolder(BASE_FOLDER) then makefolder(BASE_FOLDER) end
    if not isfolder(FOLDER_NAME) then makefolder(FOLDER_NAME) end
    pcall(function() writefile(FILE_NAME, HttpService:JSONEncode(ConfigHandler.Settings)) end)
end

function ConfigHandler.Load()
    if isfile(FILE_NAME) then
        local success, decoded = pcall(function() return HttpService:JSONDecode(readfile(FILE_NAME)) end)
        if success and type(decoded) == "table" then
            for k, v in pairs(decoded) do 
                if ConfigHandler.Settings[k] ~= nil then ConfigHandler.Settings[k] = v end 
            end
        end
    end
end

ConfigHandler.Load()
return ConfigHandler
