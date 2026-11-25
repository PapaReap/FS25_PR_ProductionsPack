-- PR_ButcherFix.lua

PRBFix = {}

-- Abort if RealisticLivestock is NOT loaded
PRBFix.disabled = true
local rlMod = g_modManager:getModByName("FS25_RealisticLivestockRM")
if rlMod == nil then
    print("[PR Butcher Fix] RealisticLivestock not detected — disabling butcher fix and using vanilla behavior")
    PRBFix.disabled = true
end

PRBFix.modName = "PR Butcher Fix"
PRBFix.VERSION = "1.2.0 multiplayer testing"
PRBFix.modNameDialog = "PR Butcher Dialog"
PRBFix.VersionDialog = "1.2.0 multiplayer testing"

PRBFix.placeablesScanned = false
PRBFix.trailersInTrigger = {}
PRBFix.butcherBarnPlaceable = nil
PRBFix.playerInTrigger = false

PRBFix.farmMeat = PRBFix.farmMeat or {}

addModEventListener(PRBFix)

PRBFix.ANIMAL_TO_MEAT_FILLTYPE = {
    COW="COWMEAT", PIG="PIGMEAT", SHEEP="SHEEPMEAT", CHICKEN="POULTRY"
}

-- Animal minimum and maximum ages
PRBFix.AGE_RULES = {
    COW     = {min = 18, max = 40},
    PIG     = {min = 6,  max = 24},
    SHEEP   = {min = 14, max = 28},
    CHICKEN = {min = 6,  max = 30},
}

-- Average baseline weights for 1.0 liter equivalence
PRBFix.AVGWEIGHT = {
    COW     = {600},
    PIG     = {155},
    SHEEP   = {40},
    CHICKEN = {3},
}

-- Per-breed multipliers
PRBFix.BREED_MULTIPLIER = {
    COW = {
        COW_HOLSTEIN      = 1.00,
        BULL_HOLSTEIN     = 1.05,
        COW_SWISS_BROWN   = 1.08,
        BULL_SWISS_BROWN  = 1.13,
        COW_WATERBUFFALO  = 1.10,
        BULL_WATERBUFFALO = 1.15,
        COW_ANGUS         = 1.15,
        BULL_ANGUS        = 1.20,
        COW_HEREFORD      = 1.12,
        BULL_HEREFORD     = 1.17,
        COW_LIMOUSIN      = 1.25,
        BULL_LIMOUSIN     = 1.30,
    },
    PIG = {
        PIG_LANDRACE      = 1.00,
        BOAR_LANDRACE     = 1.05,
        PIG_BLACK_PIED    = 1.08,
        BOAR_BLACK_PIED   = 1.13,
        PIG_BERKSHIRE     = 1.15,
        BOAR_BERKSHIRE    = 1.20,
    },
    SHEEP = {
        SHEEP_LANDRACE        = 1.00,
        RAM_LANDRACE          = 1.05,
        SHEEP_STEINSCHAF      = 1.05,
        RAM_STEINSCHAF        = 1.10,
        SHEEP_SWISS_MOUNTAIN  = 1.10,
        RAM_SWISS_MOUNTAIN    = 1.15,
        SHEEP_BLACK_WELSH     = 1.15,
        RAM_BLACK_WELSH       = 1.20,
        GOAT                  = 0.95,
        RAM_GOAT              = 1.00,
    },
    CHICKEN = {
        CHICKEN         = 1.00,
        CHICKEN_ROOSTER = 1.03,
    }
}

----------------------------------------------------------------
-- Barn Settings (per-save)
----------------------------------------------------------------
function PRBFix:getSettingsPath()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end
    local savePath = g_currentMission.missionInfo.savegameDirectory
    if savePath == nil then
        return nil
    end
    return savePath .. "/PR_ButcherBarnSettings.xml"
end

----------------------------------------------------------------
-- LOAD BARN SETTINGS
-- Loads or creates PR_ButcherBarnSettings.xml in the savegame
-- to populate product processing hours and store open/close hours
----------------------------------------------------------------
function PRBFix:loadBarnSettings()
    self.barnSettings = self.barnSettings or {}
    self.storeOpenHour = 8
    self.storeCloseHour = 19

    local path = self:getSettingsPath()
    if path == nil then
        print("[PR Butcher Fix] No savegame path yet")
        return
    end

    if not fileExists(path) then
        local xml = '<?xml version="1.0" encoding="utf-8" standalone="no"?>\n<settings>\n'
        xml = xml .. '    <product name="Bacon" hours="5"/>\n'
        xml = xml .. '    <product name="Ham" hours="5"/>\n'
        xml = xml .. '    <product name="Pork" hours="5"/>\n'
        xml = xml .. '    <product name="Sausage" hours="5"/>\n'
        xml = xml .. '    <product name="Pepperoni" hours="5"/>\n'
        xml = xml .. '    <product name="Chicken Fillet" hours="5"/>\n'
        xml = xml .. '    <product name="Chevon" hours="5"/>\n'
        xml = xml .. '    <product name="Mutton" hours="5"/>\n'
        xml = xml .. '    <product name="Ground Beef" hours="5"/>\n'
        xml = xml .. '    <product name="Steak" hours="5"/>\n'
        xml = xml .. '    <store openHour="8" closeHour="19"/>\n'
        xml = xml .. '</settings>\n'
        local f = io.open(path, "w")
        if f then
            f:write(xml)
            f:close()
            print("[PR Butcher Fix] Created default settings in save: " .. path)
        end
    end

    local xmlFile = loadXMLFile("BarnSettings", path)
    if xmlFile == nil or xmlFile == 0 then
        print("[PR Butcher Fix] Could not load settings file")
        return
    end

    local i = 0
    while true do
        local key = string.format("settings.product(%d)", i)
        if not hasXMLProperty(xmlFile, key) then break end
        local name = getXMLString(xmlFile, key .. "#name")
        local hours = getXMLInt(xmlFile, key .. "#hours") or 5
        if name then
            self.barnSettings[name] = hours
        end
        i = i + 1
    end

    self.storeOpenHour = getXMLInt(xmlFile, "settings.store#openHour") or 8
    self.storeCloseHour = getXMLInt(xmlFile, "settings.store#closeHour") or 19

    delete(xmlFile)
    print(string.format("[PR Butcher Fix] Loaded barn settings (%d products, store %d-%d)",
        i, self.storeOpenHour, self.storeCloseHour))
end

----------------------------------------------------------------
-- NETWORK SYNC EVENT
-- Sends the farmMeat ledger from server to all clients
----------------------------------------------------------------
PR_ButcherSyncEvent = {}
PR_ButcherSyncEvent_mt = Class(PR_ButcherSyncEvent, Event)
InitEventClass(PR_ButcherSyncEvent, "PR_ButcherSyncEvent")

function PR_ButcherSyncEvent.emptyNew()
    local self = Event.new(PR_ButcherSyncEvent_mt)
    return self
end

function PR_ButcherSyncEvent.new(farmMeat)
    local self = PR_ButcherSyncEvent.emptyNew()
    self.farmMeat = farmMeat
    return self
end

----------------------------------------------------------------
-- WRITE STREAM
-- Serializes per-barn ledger data and store hours to clients
----------------------------------------------------------------
function PR_ButcherSyncEvent:writeStream(streamId, connection)
    local farmMeatRoot = PRBFix.farmMeat or {}
    local barnCount = 0
    for _ in pairs(farmMeatRoot) do barnCount = barnCount + 1 end
    streamWriteUInt8(streamId, barnCount)

    for barnKey, farms in pairs(farmMeatRoot) do
        streamWriteString(streamId, tostring(barnKey))
        local farmCount = 0
        for _ in pairs(farms or {}) do farmCount = farmCount + 1 end
        streamWriteUInt8(streamId, farmCount)

        for farmId, meats in pairs(farms or {}) do
            streamWriteUInt8(streamId, farmId)
            local meatCount = 0
            for _ in pairs(meats or {}) do meatCount = meatCount + 1 end
            streamWriteUInt8(streamId, meatCount)
            for fillType, amount in pairs(meats or {}) do
                streamWriteString(streamId, tostring(fillType))
                streamWriteFloat32(streamId, tonumber(amount) or 0)
            end
        end
    end

    local palletsRoot = PRBFix.farmMeatPallets or {}
    local palletBarnCount = 0
    for _ in pairs(palletsRoot) do palletBarnCount = palletBarnCount + 1 end
    streamWriteUInt8(streamId, palletBarnCount)

    for barnKey, farms in pairs(palletsRoot) do
        streamWriteString(streamId, tostring(barnKey))
        local palletFarmCount = 0
        for _ in pairs(farms or {}) do palletFarmCount = palletFarmCount + 1 end
        streamWriteUInt8(streamId, palletFarmCount)

        for farmId, pallets in pairs(farms or {}) do
            streamWriteUInt8(streamId, farmId)
            local count = 0
            for _ in pairs(pallets or {}) do count = count + 1 end
            streamWriteUInt8(streamId, count)
            for fillType, data in pairs(pallets or {}) do
                streamWriteString(streamId, tostring(fillType))
                streamWriteFloat32(streamId, (type(data) == "table" and data.amount) or 0)
                streamWriteFloat32(streamId, (type(data) == "table" and data.readyAt) or 0)
            end
        end
    end

    streamWriteUInt8(streamId, math.clamp(PRBFix.storeOpenHour or 8, 0, 24))
    streamWriteUInt8(streamId, math.clamp(PRBFix.storeCloseHour or 19, 0, 24))

    local settingsTable = PRBFix.barnSettings or {}
    local settingCount = 0
    for _ in pairs(settingsTable) do settingCount = settingCount + 1 end
    streamWriteUInt8(streamId, math.min(settingCount, 255))
    local written = 0
    for prodName, hrs in pairs(settingsTable) do
        if written >= 255 then break end
        streamWriteString(streamId, tostring(prodName))
        streamWriteUInt8(streamId, math.clamp(tonumber(hrs) or 5, 1, 250))
        written = written + 1
    end
end


----------------------------------------------------------------
-- READ STREAM
-- Receives per-barn ledger data and store hours on clients
----------------------------------------------------------------
function PR_ButcherSyncEvent:readStream(streamId, connection)
    local barnCount = streamReadUInt8(streamId)
    local farmMeat = {}
    for b = 1, barnCount do
        local barnKey = streamReadString(streamId)
        farmMeat[barnKey] = {}
        local farmCount = streamReadUInt8(streamId)
        for i = 1, farmCount do
            local farmId = streamReadUInt8(streamId)
            farmMeat[barnKey][farmId] = {}
            local meatCount = streamReadUInt8(streamId)
            for j = 1, meatCount do
                local fillType = streamReadString(streamId)
                local amount = streamReadFloat32(streamId)
                farmMeat[barnKey][farmId][fillType] = amount
            end
        end
    end
    PRBFix.farmMeat = farmMeat

    local palletBarnCount = streamReadUInt8(streamId)
    local farmMeatPallets = {}
    for b = 1, palletBarnCount do
        local barnKey = streamReadString(streamId)
        farmMeatPallets[barnKey] = {}
        local palletFarmCount = streamReadUInt8(streamId)
        for i = 1, palletFarmCount do
            local farmId = streamReadUInt8(streamId)
            farmMeatPallets[barnKey][farmId] = {}
            local count = streamReadUInt8(streamId)
            for j = 1, count do
                local fillType = streamReadString(streamId)
                local amount = streamReadFloat32(streamId)
                local readyAt = streamReadFloat32(streamId)
                farmMeatPallets[barnKey][farmId][fillType] = {amount = amount, readyAt = readyAt, barnId = barnKey}
            end
        end
    end
    PRBFix.farmMeatPallets = farmMeatPallets

    PRBFix.storeOpenHour = streamReadUInt8(streamId)
    PRBFix.storeCloseHour = streamReadUInt8(streamId)

    local settingCount = streamReadUInt8(streamId)
    local syncedSettings = {}
    for i = 1, settingCount do
        local prodName = streamReadString(streamId)
        local hrs = streamReadUInt8(streamId)
        if prodName and prodName ~= "" then
            syncedSettings[prodName] = hrs
        end
    end
    if settingCount > 0 then
        PRBFix.barnSettings = syncedSettings
    end

    if PRBFix.updateBarnInteriorLights ~= nil then
        PRBFix:updateBarnInteriorLights(true)
    end

    print(string.format("[PR Butcher Fix] Received farmMeat sync (%d barns, %d pallet barns, hours %d-%d, %d product settings)",
        barnCount, palletBarnCount, PRBFix.storeOpenHour or 8, PRBFix.storeCloseHour or 19, settingCount))
end


function PR_ButcherSyncEvent:run(connection)
end


-- Broadcasts current farmMeat table to all clients
function PRBFix:syncFarmMeat()
    if g_server ~= nil then
        g_server:broadcastEvent(PR_ButcherSyncEvent.new(PRBFix.farmMeat or {}))
    end
end

-- Returns breed multiplier for an animal cluster
function PRBFix:getBreedMultiplier(animalType, cluster)
    local default = 1.0
    if cluster == nil then return default end

    local subName = cluster.subTypeName or cluster.subType or nil
    if not subName then return default end

    local byType = self.BREED_MULTIPLIER[animalType]
    if not byType then return default end

    return byType[subName] or default
end

-- Gets the display name of the unload key
function PRBFix:getUnloadKeyName()
    local action = InputAction and InputAction.RLB_UNLOAD_TO_BUTCHER
    if not action or not g_inputBinding then return "K" end

    if g_inputBinding.getActionBindings ~= nil then
        local bindings = g_inputBinding:getActionBindings(action)
        if type(bindings) == "table" and bindings[1] ~= nil then
            local b = bindings[1]
            local key = (b.axisNames and b.axisNames[1]) or b.inputString or b.input
            if key ~= nil and key ~= "" then
                return tostring(key):gsub("KEY_", ""):upper()
            end
        end
    end

    local actionObj = (g_inputBinding.nameActions and g_inputBinding.nameActions["RLB_UNLOAD_TO_BUTCHER"])
        or (g_inputBinding.actions and g_inputBinding.actions[action])
    if actionObj ~= nil and type(actionObj.bindings) == "table" and actionObj.bindings[1] ~= nil then
        local b = actionObj.bindings[1]
        local key = (b.axisNames and b.axisNames[1]) or b.inputString or b.input
        if key ~= nil and key ~= "" then
            return tostring(key):gsub("KEY_", ""):upper()
        end
    end

    return "K"
end

----------------------------------------------------------------
-- CONSOLE COMMAND
----------------------------------------------------------------
addConsoleCommand("deliver", "Manual delivery", "consoleDeliver", PRBFix)

function PRBFix:consoleDeliver(amount)
    print("["..self.modName.."] Console deliver called amount="..tostring(amount))

    for trailer, data in pairs(self.trailersInTrigger) do
        local cap = self:checkBarnCapacity(data.type)
        if not cap then return end

        local max = math.min(cap.avail, data.num)
        local n = tonumber(amount) or max
        n = math.min(n, max)
        self:deliverAnimals(trailer, data, n)
        return
    end
end

----------------------------------------------------------------
-- LOADMAP
-- Loads dialogs, GUI, and saved ledger
----------------------------------------------------------------
function PRBFix:loadMap()
    self.butcherActionEventId = nil

    local modDir = nil
    local env = getfenv(2)
    if env and env.modDirectory then
        modDir = env.modDirectory
        print("["..self.modName.."] ✅ modDir = env.modDirectory")
    end

    if not modDir and g_currentModDirectory then
        modDir = g_currentModDirectory
        print("["..self.modName.."] ✅ modDir = g_currentModDirectory")
    end

    if not modDir and g_modNameToDirectory then
        modDir = g_modNameToDirectory["FS25_PR_ProductionsPack"]
        print("["..self.modName.."] ✅ modDir = g_modNameToDirectory")
    end

    if not modDir then
        print("[PR Butcher Fix] ❌ modDir is nil — cannot load dialog")
        return
    end

    PRBFix.modDirectory = modDir

    local profilesPath = modDir .. "gui/guiProfiles.xml"
    print("[PR Butcher Fix] Loading guiProfiles: " .. profilesPath)
    g_gui:loadProfiles(profilesPath)

    local dlgPath = modDir .. "scripts/PR_ButcherDialog.lua"
    print("[PR Butcher Fix] Loading PR_ButcherDialog.lua from: " .. dlgPath)
    local ok, err = pcall(function() source(dlgPath) end)
    if not ok then
        print("[PR Butcher Fix] ❌ Error loading dialog: " .. tostring(err))
    else
        print("[PR Butcher Fix] ✓ Dialog script loaded OK")
    end

    local spawnDlgPath = modDir .. "scripts/PR_ButcherSpawnDialog.lua"
    print("[PR Butcher Fix] Loading PR_ButcherSpawnDialog.lua from: " .. spawnDlgPath)
    local ok2, err2 = pcall(function() source(spawnDlgPath) end)
    if not ok2 then
        print("[PR Butcher Fix] ❌ Error loading spawn dialog: " .. tostring(err2))
    else
        print("[PR Butcher Fix] ✓ Spawn dialog script loaded OK")
        if PRBSpawnDialog and PRBSpawnDialog.register then
            PRBSpawnDialog.register()
        end
    end

    self:loadBarnSettings()
    self:loadMeatLedger()
    print(string.format("[%s] loadMap called (v%s)", self.modName, PRBFix.VERSION))
end

--------------------------------------------------------------------
-- INPUT CONTEXT
-- Manages the unload key binding while inside the animal trigger
--------------------------------------------------------------------
PRBFix.currentVehicle = nil
PRBFix.actionEventId = nil

----------------------------------------------------------------
-- GET ACTIVE TRIGGER TRAILER
-- Finds the livestock trailer inside the trigger that belongs to
-- the local player's active or controlled vehicle root
----------------------------------------------------------------
function PRBFix:getActiveTriggerTrailer()
    local mission = g_currentMission
    if not mission or not next(self.trailersInTrigger) then return nil, nil end

    local veh = mission.controlledVehicle
    if veh == nil and g_localPlayer ~= nil then
        veh = (g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()) or g_localPlayer.currentVehicle
    end
    if veh == nil and mission.playerSystem and mission.playerSystem.players then
        local player = mission.playerSystem.players[1]
        veh = player and player.getCurrentVehicle and player:getCurrentVehicle() or nil
    end
    if veh == nil then return nil, nil end

    local playerRoot = veh.rootVehicle or veh
    for trailer, data in pairs(self.trailersInTrigger) do
        local trailerRoot = trailer.rootVehicle or trailer
        if trailerRoot == playerRoot then
            return trailer, data
        end
    end
    return nil, nil
end

----------------------------------------------------------------
-- UPDATE INPUT CONTEXT
-- Binds or removes the animal unload action event based on
-- whether the local player is in the trigger with a trailer
----------------------------------------------------------------
function PRBFix:updateInputContext()
    local trailer, data = self:getActiveTriggerTrailer()
    local shouldBind = (trailer ~= nil)

    if not shouldBind then
        if self.butcherActionEventId ~= nil then
            g_inputBinding:removeActionEvent(self.butcherActionEventId)
            self.butcherActionEventId = nil
        end
        self.currentVehicle = nil
        return
    end

    local veh = g_currentMission and g_currentMission.controlledVehicle or nil
    if veh == nil and g_localPlayer ~= nil then
        veh = (g_localPlayer.getCurrentVehicle and g_localPlayer:getCurrentVehicle()) or g_localPlayer.currentVehicle
    end

    if self.butcherActionEventId == nil or veh ~= self.currentVehicle then
        if self.butcherActionEventId ~= nil then
            g_inputBinding:removeActionEvent(self.butcherActionEventId)
            self.butcherActionEventId = nil
        end
        self.currentVehicle = veh

        if InputAction and InputAction.RLB_UNLOAD_TO_BUTCHER then
            local _, eventId = g_inputBinding:registerActionEvent(
                InputAction.RLB_UNLOAD_TO_BUTCHER, self, self.onDeliverKeyPressed,
                false, true, false, true
            )
            self.butcherActionEventId = eventId
            if eventId then
                local keyName = self:getUnloadKeyName()
                g_inputBinding:setActionEventText(eventId, "Unload Animals To Butcher (Press " .. keyName .. ")")
                g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
                g_inputBinding:setActionEventTextVisibility(eventId, true)
            end
        end
    end
end

----------------------------------------------------------------
-- IS BARN OPEN FOR OPERATIONS
-- Returns true when current time is inside storeOpenHour..storeCloseHour
----------------------------------------------------------------
function PRBFix:isBarnOpenForOperations()
    return self:isBarnDoorsOpenAllowed()
end

----------------------------------------------------------------
-- UPDATE SCHEDULED BARN TASKS
-- Runs 60s checks; skips delivery/spawn checks while barn is closed
----------------------------------------------------------------
function PRBFix:updateScheduledBarnTasks(dt)
    if self.butcherBarnPlaceable ~= nil and (self.isButcherBarnValid == nil or not self:isButcherBarnValid()) then
        if self.resetButcherBarn ~= nil then
            self:resetButcherBarn()
        else
            self.butcherBarnPlaceable = nil
            self.placeablesScanned = false
        end
    end

    self.scheduleCheckTimer = (self.scheduleCheckTimer or 0) + (dt or 0)
    if self.scheduleCheckTimer < 60000 then
        return
    end
    self.scheduleCheckTimer = 0

    if self.butcherBarnPlaceable == nil then
        return
    end

    if g_currentMission ~= nil and g_currentMission:getIsClient() then
        self:updateBarnInteriorLights(false)
    end

    if g_server ~= nil then
        self:updateBarnDoorSchedule()
    end

    -- Skip delivery/spawn checks while closed
    if not self:isBarnOpenForOperations() then
        return
    end

    self:processIncomingToOutgoing()
end

----------------------------------------------------------------
-- UPDATE LOOP
-- Runs every frame. Handles input, scheduled tasks, timers, and scan
----------------------------------------------------------------
function PRBFix:update(dt)
    self:updateInputContext()
    --self:creditProductionOutput()
    self:updateScheduledBarnTasks(dt)

    if not self.outputLockTimer then self.outputLockTimer = 0 end
    self.outputLockTimer = self.outputLockTimer + dt
    if self.outputLockTimer > 30000 then
        self.outputLockTimer = 0
        local barn = self.butcherBarnPlaceable
        if barn and barn.spec_extendedProductionPoint then
            local pp = barn.spec_extendedProductionPoint.productionPoint
            if pp then
                local function moveToStorage(srcTable)
                    if srcTable then
                        for ftIdx, palletData in pairs(srcTable) do
                            if type(palletData) == "table" then
                                pp.outputFillTypeIdsToPallets[ftIdx] = palletData
                            end
                        end
                    end
                end
                moveToStorage(pp.outputFillTypeIdsDirectSell)
                moveToStorage(pp.outputFillTypeIdsAutoDeliver)
                pp.outputFillTypeIdsDirectSell = {}
                pp.outputFillTypeIdsAutoDeliver = {}
                pp.isOutputModeChangeAllowed = false
            end
        end
    end

    if self.spawnLockTimer and self.spawnLockTimer > 0 then
        self.spawnLockTimer = self.spawnLockTimer - 1
        if self.spawnLockTimer <= 0 then
            local barn = self.butcherBarnPlaceable
            if barn and barn.spec_extendedProductionPoint and barn.spec_extendedProductionPoint.productionPoint then
                barn.spec_extendedProductionPoint.productionPoint.waitingForPalletToSpawn = true
            end
            self.spawnLockTimer = nil
        end
    end

    if next(self.trailersInTrigger) then
        local mission = g_currentMission
        local player = mission and mission.playerSystem.players and mission.playerSystem.players[1]
        local veh = player and player.getCurrentVehicle and player:getCurrentVehicle()
        if veh then
            for trailer, data in pairs(self.trailersInTrigger) do
                local root = trailer.rootVehicle or trailer
                if root == veh then
                    local num = trailer:getNumOfAnimals() or 0
                    local speed = root:getLastSpeed() or 0
                    if num > 0 and speed < 0.05 then
                        local keyName = self:getUnloadKeyName()
                        mission:addExtraPrintText("Unload Animals To Butcher (Press " .. keyName .. ")")
                    end
                end
            end
        end
    end

    if g_server ~= nil then
        if PRBFix.pushTimer == nil then PRBFix.pushTimer = 0 end
        PRBFix.pushTimer = PRBFix.pushTimer + dt
        if PRBFix.pushTimer > 300000 then
            PRBFix.pushTimer = 0
            self:syncFarmMeat()
        end
    end

    if not self.placeablesScanned and g_currentMission and g_currentMission.placeableSystem then
        local now = g_time or 0
        if self.nextPlaceableScanTime == nil then
            self.nextPlaceableScanTime = now
        end
        if now >= self.nextPlaceableScanTime then
            self.nextPlaceableScanTime = now + 4000
            self:scanButcherPlaceables()
        end
    end
end


----------------------------------------------------------------
-- SCAN BUTCHER PLACEABLES
-- Finds butcher barn(s), hooks triggers per barn, preserves/sets
-- owner, locks output mode, and registers lifecycle hooks
----------------------------------------------------------------
function PRBFix:scanButcherPlaceables()
    if not self.placeableDeleteHooked and Placeable ~= nil and Placeable.delete ~= nil then
        self.placeableDeleteHooked = true
        Placeable.delete = Utils.prependedFunction(Placeable.delete, function(placeable)
            if PRBFix ~= nil and placeable ~= nil and placeable.configFileName and placeable.configFileName:match("theButcherBarn.xml") then
                if PRBFix.hookedBarns then
                    PRBFix.hookedBarns[placeable] = nil
                end
                if PRBFix.resetButcherBarn ~= nil then
                    PRBFix:resetButcherBarn(placeable)
                end
            end
        end)
    end

    if not self.placeableCreateHooked and Placeable ~= nil and Placeable.finalizePlacement ~= nil then
        self.placeableCreateHooked = true
        Placeable.finalizePlacement = Utils.appendedFunction(Placeable.finalizePlacement, function(placeable)
            if PRBFix ~= nil and placeable ~= nil and placeable.configFileName and placeable.configFileName:match("theButcherBarn.xml") then
                if PRBFix.hookedBarns == nil or not PRBFix.hookedBarns[placeable] then
                    PRBFix.placeablesScanned = false
                    if PRBFix.scanButcherPlaceables ~= nil then
                        PRBFix:scanButcherPlaceables()
                    end
                end
            end
        end)
    end

    if self.butcherBarnPlaceable ~= nil and (self.isButcherBarnValid == nil or not self:isButcherBarnValid()) then
        if self.resetButcherBarn ~= nil then
            self:resetButcherBarn(self.butcherBarnPlaceable)
        else
            self.butcherBarnPlaceable = nil
            self.placeablesScanned = false
            self.visibilityOverrideInstalled = false
        end
    end

    self.hookedBarns = self.hookedBarns or {}
    self.barnTriggers = self.barnTriggers or {}
    self.triggerToBarn = self.triggerToBarn or {}
    self.barnKeyToPlaceable = {}
    self.barnIds = {}
    self.barnMeta = self.barnMeta or {}

    local found = false
    local placeables = g_currentMission and g_currentMission.placeableSystem and g_currentMission.placeableSystem.placeables

    if placeables then
        for _, p in pairs(placeables) do
            if p.configFileName and p.configFileName:match("theButcherBarn.xml") then
                found = true

                local barnKey, posStr, ownerId = self:getBarnIdentity(p)
                local posKey = self:getBarnKey(p)
                if p.ownerFarmId == nil or p.ownerFarmId == 0 then
                    if p.setOwnerFarmId then
                        p:setOwnerFarmId(1)
                    else
                        p.ownerFarmId = 1
                    end
                    ownerId = 1
                    print(string.format("[%s] Butcher barn (%s) had no owner; defaulted to farm 1", self.modName, barnKey))
                else
                    print(string.format("[%s] Butcher barn (%s) kept owner farm %d", self.modName, barnKey, ownerId))
                end

                self.barnIds[barnKey] = p
                self.barnKeyToPlaceable[posKey] = p
                self.barnMeta[barnKey] = {
                    id = barnKey,
                    posKey = posKey,
                    ownerFarmId = ownerId,
                    position = posStr
                }

                if self.butcherBarnPlaceable == nil or (self.isButcherBarnValid and not self:isButcherBarnValid()) then
                    self.butcherBarnPlaceable = p
                end

                if not self.hookedBarns[p] then
                    self.hookedBarns[p] = true
                    self.barnTriggers[p] = {}
                    print(string.format("[%s] Found butcher barn: %s (id=%s, owner=%d, pos=%s)",
                        self.modName, p.configFileName, barnKey, ownerId, posStr))

                    local spec = p.spec_extendedProductionPoint
                    if spec and spec.productionPoint then
                        local pp = spec.productionPoint
                        if pp.palletSpawner then
                            self.manualPalletSpawner = pp.palletSpawner
                            pp.waitingForPalletToSpawn = true
                            print("["..self.modName.."] Auto pallet spawner paused (manual reference kept)")
                        end
                    end

                    if p.i3dMappings and p.i3dMappings["animalTrigger"] then
                        local n = p.i3dMappings["animalTrigger"].nodeId
                        if n and n ~= 0 then
                            print("["..self.modName.."] Disabling original animalTrigger "..n)
                            removeTrigger(n)
                            addTrigger(n, "onTriggerCallback", self)
                            table.insert(self.barnTriggers[p], n)
                            self.triggerToBarn[n] = p
                            print("["..self.modName.."] onTriggerCallback attached new animalTrigger!")
                        end
                    end

                    if p.i3dMappings and p.i3dMappings["palletTrigger"] then
                        local n = p.i3dMappings["palletTrigger"].nodeId
                        if n and n ~= 0 then
                            print("["..self.modName.."] Replacing original palletTrigger "..n)
                            removeTrigger(n)
                            addTrigger(n, "onPalletTriggerCallback", self)
                            table.insert(self.barnTriggers[p], n)
                            self.triggerToBarn[n] = p
                            print("["..self.modName.."] onPalletTriggerCallback attached")
                        end
                    end

                    if p.i3dMappings and p.i3dMappings["loadingZoneTrigger"] then
                        local n = p.i3dMappings["loadingZoneTrigger"].nodeId
                        if n and n ~= 0 then
                            addTrigger(n, "onSpawnTriggerCallback", self)
                            table.insert(self.barnTriggers[p], n)
                            self.triggerToBarn[n] = p
                            print("["..self.modName.."] Loading Zone trigger attached")
                        end
                    end

                    self:installVisibilityOverrideForBarn(p)
                end
            end
        end
    end

    if found then
        self.placeablesScanned = true
        self:updateBarnInteriorLights(true)
        self:installBarnDoorLockHook()
        self:updateBarnDoorSchedule()
    else
        self.placeablesScanned = false
    end
end

----------------------------------------------------------------
-- PALLET TRIGGER CALLBACK
-- Credits empty pallets to the delivering farm for that barn
----------------------------------------------------------------
function PRBFix:onPalletTriggerCallback(triggerId, otherId, onEnter, onLeave)
    if not onEnter then return end

    local obj = g_currentMission.nodeToObject[otherId]
    if obj == nil then return end
    if obj.prButcherCredited then return end

    local fillTypeIndex = nil
    local amount = 0
    if obj.getFillUnitFillType then
        fillTypeIndex = obj:getFillUnitFillType(1)
        amount = obj:getFillUnitFillLevel(1) or 0
    end

    local fillTypeName = fillTypeIndex and g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)
    if fillTypeName ~= "EMPTYPALLET" or amount <= 0 then return end

    local farmId = obj.ownerFarmId or obj.farmId
    if g_server == nil or farmId == nil or farmId <= 0 then return end

    local barn = (self.triggerToBarn and self.triggerToBarn[triggerId]) or self.butcherBarnPlaceable
    local barnKey = self:getBarnKey(barn)

    obj.prButcherCredited = true

    PRBFix.farmMeat[barnKey] = PRBFix.farmMeat[barnKey] or {}
    PRBFix.farmMeat[barnKey][farmId] = PRBFix.farmMeat[barnKey][farmId] or {}
    PRBFix.farmMeat[barnKey][farmId]["EMPTYPALLET"] = (PRBFix.farmMeat[barnKey][farmId]["EMPTYPALLET"] or 0) + amount

    print(string.format("[%s] Pallet trigger credited %.2f L EMPTYPALLET to farm %d at barn %s",
        self.modName, amount, farmId, barnKey))

    if g_server ~= nil then
        PRBFix:syncFarmMeat()
    end

    if barn and barn.spec_extendedProductionPoint and barn.spec_extendedProductionPoint.productionPoint then
        local storage = barn.spec_extendedProductionPoint.productionPoint.storage
        if storage and storage.setFillLevel then
            local current = storage:getFillLevel(fillTypeIndex) or 0
            storage:setFillLevel(current + amount, fillTypeIndex)
            print(string.format("[%s] Added %.2f L EMPTYPALLET to production storage", self.modName, amount))
        end
    end

    if obj.delete then
        obj:delete()
    end
end


----------------------------------------------------------------
-- SPAWN / LOADING ZONE TRIGGER
-- Tracks which barn's loading zone the local player entered
----------------------------------------------------------------
function PRBFix:onSpawnTriggerCallback(triggerId, otherId, onEnter, onLeave)
    if otherId == nil then return end

    local isPlayer = false

    if g_localPlayer and (g_localPlayer.rootNode == otherId or g_localPlayer.capsuleRootNode == otherId) then
        isPlayer = true
    end

    if not isPlayer and g_currentMission and g_currentMission.playerSystem and g_currentMission.playerSystem.players then
        for _, player in pairs(g_currentMission.playerSystem.players) do
            if player and (player.rootNode == otherId or player.capsuleRootNode == otherId) then
                isPlayer = true
                break
            end
        end
    end

    if not isPlayer then return end

    local isClient = (g_currentMission ~= nil and g_currentMission:getIsClient())
    local barn = (self.triggerToBarn and self.triggerToBarn[triggerId]) or self.butcherBarnPlaceable
    local barnKey = self:getBarnKey(barn)

    if isClient then
        self.playerInSpawnTrigger = (onEnter == true)
        if onEnter then
            self.activeSpawnBarn = barn
            self.activeSpawnBarnKey = barnKey
        elseif onLeave and self.activeSpawnBarn == barn then
            self.activeSpawnBarn = nil
            self.activeSpawnBarnKey = nil
        end
    end

    local farmId = 1
    local farmName = "Unknown"
    if g_currentMission and g_currentMission.getFarmId then
        farmId = g_currentMission:getFarmId() or 1
    end

    if g_farmManager and g_farmManager.farms then
        for _, farm in pairs(g_farmManager.farms) do
            if farm and (farm.farmId == farmId or farm.id == farmId) then
                if farm.name and farm.name ~= "" then
                    farmName = farm.name
                end
                break
            end
        end
    end

    if onEnter then
        print(string.format("[%s] Player entered loading zone (%s) | Farm %d (%s)",
            self.modName, barnKey, farmId, farmName))

        if isClient then
            local isOpen = true
            if g_currentMission and g_currentMission.environment then
                local dayTime = (g_currentMission.environment.dayTime or 0) / 1000
                local hour = math.floor(dayTime / 3600)
                local openH = self.storeOpenHour or 8
                local closeH = self.storeCloseHour or 19
                isOpen = (hour >= openH and hour < closeH)
            end

            if isOpen then
                if self.spawnActionEventId == nil and g_inputBinding then
                    local _, eventId = g_inputBinding:registerActionEvent(
                        InputAction.ACTIVATE_OBJECT, self, PRBFix.onSpawnPalletAction, false, true, false, true
                    )
                    self.spawnActionEventId = eventId
                    if self.spawnActionEventId then
                        g_inputBinding:setActionEventText(self.spawnActionEventId, "Spawn Pallet")
                        g_inputBinding:setActionEventTextVisibility(self.spawnActionEventId, true)
                    end
                end
            else
                if g_currentMission and g_currentMission.showBlinkingWarning then
                    g_currentMission:showBlinkingWarning("Store Closed", 4000)
                end
                print(string.format("[%s] Store is closed (hours %d-%d)",
                    self.modName, self.storeOpenHour or 8, self.storeCloseHour or 19))
            end
        end
    elseif onLeave then
        print(string.format("[%s] Player left loading zone (%s) | Farm %d (%s)",
            self.modName, barnKey, farmId, farmName))

        if isClient and self.spawnActionEventId ~= nil and g_inputBinding then
            g_inputBinding:removeActionEvent(self.spawnActionEventId)
            self.spawnActionEventId = nil
        end
    end
end


----------------------------------------------------------------
-- SPAWN ACTION
-- Opens the spawn dialog using only the active barn's ready products
----------------------------------------------------------------
function PRBFix:onSpawnPalletAction()
    if not self.playerInSpawnTrigger then return end

    if g_currentMission and g_currentMission.environment then
        local dayTime = g_currentMission.environment.dayTime / 1000
        local hour = math.floor(dayTime / 3600)
        local openH = self.storeOpenHour or 8
        local closeH = self.storeCloseHour or 19
        if hour < openH or hour >= closeH then
            if g_currentMission.showBlinkingWarning then
                g_currentMission:showBlinkingWarning("Store Closed", 4000)
            end
            return
        end
    end

    local barn = self.activeSpawnBarn or self.butcherBarnPlaceable
    local barnKey = self.activeSpawnBarnKey or self:getBarnKey(barn)
    local farmId = g_currentMission and g_currentMission:getFarmId() or 1
    local pallets = (PRBFix.farmMeatPallets and PRBFix.farmMeatPallets[barnKey] and PRBFix.farmMeatPallets[barnKey][farmId]) or {}

    local now = 0
    if g_currentMission and g_currentMission.environment then
        now = g_currentMission.environment.currentMonotonicDay * 86400 + g_currentMission.environment.dayTime / 1000
    end

    local readyProducts = {}
    for fillType, entry in pairs(pallets) do
        if type(entry) == "table" and entry.amount and entry.amount > 0.01 and entry.readyAt and now >= entry.readyAt then
            table.insert(readyProducts, {
                fillType = fillType,
                amount = entry.amount,
                barnKey = barnKey
            })
        end
    end

    table.sort(readyProducts, function(a, b) return a.fillType < b.fillType end)

    self.dialogBarn = barn
    self.dialogBarnKey = barnKey

    if PRBSpawnDialog and PRBSpawnDialog.show then
        PRBSpawnDialog.show(readyProducts, farmId, barnKey)
    else
        print("["..self.modName.."] Spawn dialog not available")
    end
end

----------------------------------------------------------------
-- DO SPAWN PALLET
-- Server-only. Spawns ready pallets from the target barn's ledger
----------------------------------------------------------------
function PRBFix:doSpawnPallet(fillTypeName, farmId, barnKey)
    if g_server == nil then
        print("["..self.modName.."] Spawn skipped (not server)")
        return
    end

    local resolvedKey = barnKey or self.dialogBarnKey or self:getBarnKey(self.butcherBarnPlaceable)
    local barn = self:getBarnByKey(resolvedKey)
    if barn == nil or barn.i3dMappings == nil then
        print("["..self.modName.."] No barn or mappings")
        return
    end

    local startNode = barn.i3dMappings["spawnSpace1start"] and barn.i3dMappings["spawnSpace1start"].nodeId
    if startNode == nil or startNode == 0 then
        print("["..self.modName.."] No spawn start node")
        return
    end

    local pallets = PRBFix.farmMeatPallets and PRBFix.farmMeatPallets[resolvedKey] and PRBFix.farmMeatPallets[resolvedKey][farmId]
    if pallets == nil or pallets[fillTypeName] == nil then
        print("["..self.modName.."] No ledger entry for " .. fillTypeName)
        return
    end

    local entry = pallets[fillTypeName]
    local spawnAmount = entry.amount or 0
    if spawnAmount < 0.01 then
        print("["..self.modName.."] Nothing left to spawn for " .. fillTypeName)
        return
    end

    local emptyPallets = (PRBFix.farmMeat and PRBFix.farmMeat[resolvedKey] and PRBFix.farmMeat[resolvedKey][farmId] and PRBFix.farmMeat[resolvedKey][farmId]["EMPTYPALLET"]) or 0
    if emptyPallets < 0.01 then
        print(string.format("[%s] Farm %d is out of empty pallets", self.modName, farmId))
        return
    end

    if spawnAmount > emptyPallets then
        spawnAmount = emptyPallets
        print(string.format("[%s] Limited %s spawn to %.1f L (out of empty pallets)", self.modName, fillTypeName, spawnAmount))
    end

    local x, y, z = getWorldTranslation(startNode)
    local rx, ry, rz = getWorldRotation(startNode)

    if PRBFix._spawnBatch and #PRBFix._spawnBatch > 1 then
        local index = PRBFix._spawnIndex or 0
        PRBFix._spawnIndex = index + 1

        local gap = 1.6
        local offsetX = gap * index
        local cosRy = math.cos(ry)
        local sinRy = math.sin(ry)
        x = x + offsetX * cosRy
        z = z - offsetX * sinRy
    end

    local palletXml = {
        CHICKENFILLET = "xml/pallets/chickenfilletPallet.xml",
        HAM           = "xml/pallets/hamPallet.xml",
        PORK          = "xml/pallets/porkPallet.xml",
        BACON         = "xml/pallets/baconPallet.xml",
        SAUSAGE       = "xml/pallets/sausagePallet.xml",
        PEPPERONI     = "xml/pallets/pepperoniPallet.xml",
        GROUNDBEEF    = "xml/pallets/groundbeefPallet.xml",
        STEAK         = "xml/pallets/steakPallet.xml",
        MUTTON        = "xml/pallets/muttonPallet.xml",
        CHEVON        = "xml/pallets/chevonPallet.xml",
    }

    local relPath = palletXml[fillTypeName]
    if relPath == nil then
        print("["..self.modName.."] No XML for " .. fillTypeName)
        return
    end

    local xmlFilename = (PRBFix.modDirectory or g_currentModDirectory or "") .. relPath
    print(string.format("[%s] Spawning %.1f L of %s at %.1f %.1f %.1f", self.modName, spawnAmount, fillTypeName, x, y, z))

    local data = VehicleLoadingData.new()
    data:setFilename(xmlFilename)
    data:setPosition(x, y + 0.2, z)
    data:setRotation(rx, ry, rz)
    data:setPropertyState(VehiclePropertyState.OWNED)
    data:setOwnerFarmId(farmId)

    data:load(function(_, vehicles, vehicleLoadState, _)
        if vehicleLoadState == VehicleLoadingState.OK and vehicles and vehicles[1] then
            local vehicle = vehicles[1]
            vehicle:emptyAllFillUnits(true)
            local ftIdx = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
            if ftIdx then
                vehicle:addFillUnitFillLevel(farmId, 1, spawnAmount, ftIdx, ToolType.UNDEFINED, nil)
            end
            print(string.format("[%s] Successfully spawned %.1f L %s pallet for farm %d", self.modName, spawnAmount, fillTypeName, farmId))

            local spec = barn.spec_extendedProductionPoint
            if spec and spec.productionPoint and spec.productionPoint.storage then
                local st = spec.productionPoint.storage
                if ftIdx then
                    local current = st:getFillLevel(ftIdx) or 0
                    st:setFillLevel(math.max(0, current - spawnAmount), ftIdx)
                    print(string.format("[%s] Deducted %.1f L %s from production storage", self.modName, spawnAmount, fillTypeName))
                end

                local emptyIdx = g_fillTypeManager:getFillTypeIndexByName("EMPTYPALLET")
                if emptyIdx then
                    local currentEmpty = st:getFillLevel(emptyIdx) or 0
                    local emptyCost = 1000
                    st:setFillLevel(math.max(0, currentEmpty - emptyCost), emptyIdx)
                    print(string.format("[%s] Deducted %d L EMPTYPALLET from production storage", self.modName, emptyCost))
                end
            end

            if PRBFix.farmMeat and PRBFix.farmMeat[resolvedKey] and PRBFix.farmMeat[resolvedKey][farmId] then
                local empty = PRBFix.farmMeat[resolvedKey][farmId]["EMPTYPALLET"] or 0
                local emptyCost = 1000
                PRBFix.farmMeat[resolvedKey][farmId]["EMPTYPALLET"] = math.max(0, empty - emptyCost)
                print(string.format("[%s] Deducted %d L EMPTYPALLET from farm %d ledger (%s)",
                    self.modName, emptyCost, farmId, resolvedKey))
            end

            entry.amount = entry.amount - spawnAmount
            if entry.amount < 0.01 then
                PRBFix.farmMeatPallets[resolvedKey][farmId][fillTypeName] = nil
            end
            print(string.format("[%s] Deducted %.1f L %s from farmMeatPallets", self.modName, spawnAmount, fillTypeName))

            if self.syncFarmMeat then
                self:syncFarmMeat()
            end
        else
            print("["..self.modName.."] Vehicle load failed")
        end
    end)
end

----------------------------------------------------------------
-- SERVER HANDLE PALLET SPAWN
-- Server-only. Caps at 10 and spawns from the target barn's ledger
----------------------------------------------------------------
function PRBFix:handleSpawnRequest(fillTypes, farmId, barnKey)
    if not g_server then return end

    local resolvedKey = barnKey or self.dialogBarnKey or self:getBarnKey(self.butcherBarnPlaceable)
    local emptyPallets = (self.farmMeat and self.farmMeat[resolvedKey] and self.farmMeat[resolvedKey][farmId] and self.farmMeat[resolvedKey][farmId]["EMPTYPALLET"]) or 0
    local spawned = 0

    for _, fillType in ipairs(fillTypes) do
        if emptyPallets < 1000 then
            print(string.format("[%s] Out of empty pallets for farm %d at barn %s", self.modName, farmId, resolvedKey))
            break
        end

        if self.doSpawnPallet then
            self:doSpawnPallet(fillType, farmId, resolvedKey)
            emptyPallets = emptyPallets - 1000
            spawned = spawned + 1
        end
    end

    print(string.format("[%s] Spawned %d pallets for farm %d at barn %s", self.modName, spawned, farmId, resolvedKey))
    self:syncFarmMeat()
end

----------------------------------------------------------------
-- CREDIT PRODUCTION OUTPUT
----------------------------------------------------------------
function PRBFix:creditProductionOutput()
    local barn = self.butcherBarnPlaceable
    if barn == nil then return end

    local spec = barn.spec_extendedProductionPoint
    if spec == nil or spec.productionPoint == nil or spec.productionPoint.storage == nil then return end

    local storage = spec.productionPoint.storage
    local farmId = g_currentMission and g_currentMission:getFarmId() or 1

    local productOrder = {
        "CHICKENFILLET", "HAM", "BACON", "SAUSAGE", "PEPPERONI",
        "STEAK", "GROUNDBEEF", "PORK", "MUTTON", "CHEVON"
    }

    if PRBFix.lastOutputLevels == nil then
        PRBFix.lastOutputLevels = {}
    end

    for _, fillTypeName in ipairs(productOrder) do
        local ftIdx = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
        if ftIdx then
            local current = storage:getFillLevel(ftIdx) or 0
            local last = PRBFix.lastOutputLevels[fillTypeName] or 0
            if current > last + 0.01 then
                local added = current - last
                PRBFix.farmMeat[farmId] = PRBFix.farmMeat[farmId] or {}
                PRBFix.farmMeat[farmId][fillTypeName] = (PRBFix.farmMeat[farmId][fillTypeName] or 0) + added
                print(string.format("[%s] Credited %.2f L %s to farm %d", self.modName, added, fillTypeName, farmId))
            end
            PRBFix.lastOutputLevels[fillTypeName] = current
        end
    end
end

----------------------------------------------------------------
-- PROCESS INCOMING TO OUTGOING
----------------------------------------------------------------
function PRBFix:processIncomingToOutgoing()
    if g_server == nil then return end

    local barn = self.butcherBarnPlaceable
    if barn == nil or barn.spec_extendedProductionPoint == nil then return end

    local pp = barn.spec_extendedProductionPoint.productionPoint
    if pp == nil or pp.storage == nil then return end

    local storage = pp.storage
    local now = 0
    if g_currentMission and g_currentMission.environment then
        now = g_currentMission.environment.currentMonotonicDay * 86400 + g_currentMission.environment.dayTime / 1000
    end

    PRBFix.pendingConversions = PRBFix.pendingConversions or {}

    for i = #PRBFix.pendingConversions, 1, -1 do
        local pending = PRBFix.pendingConversions[i]
        if now >= pending.convertAt then
            local rawIdx = g_fillTypeManager:getFillTypeIndexByName(pending.rawFillType)
            if rawIdx then
                local currentRaw = storage:getFillLevel(rawIdx) or 0
                storage:setFillLevel(math.max(0, currentRaw - pending.rawAmount), rawIdx)
            end

            for fillType, amount in pairs(pending.outputs) do
                local ftIdx = g_fillTypeManager:getFillTypeIndexByName(fillType)
                if ftIdx then
                    local current = storage:getFillLevel(ftIdx) or 0
                    storage:setFillLevel(current + amount, ftIdx)
                end
            end

            print(string.format("[%s] Converted %.1f L %s into outgoing products", self.modName, pending.rawAmount, pending.rawFillType))
            table.remove(PRBFix.pendingConversions, i)
        end
    end
end

----------------------------------------------------------------
-- ANIMAL TRIGGER CALLBACK
-- Tracks trailers per barn trigger and updates player/vehicle state
----------------------------------------------------------------
function PRBFix:onTriggerCallback(triggerId, otherId, onEnter, onLeave)
    local barn = (self.triggerToBarn and self.triggerToBarn[triggerId]) or self.butcherBarnPlaceable
    local barnKey = self:getBarnKey(barn)

    local obj = g_currentMission.nodeToObject[otherId]
    if obj and obj.typeName == "livestockTrailer" then
        if onEnter then
            local isOpen = true
            if g_currentMission and g_currentMission.environment then
                local dayTime = g_currentMission.environment.dayTime / 1000
                local hour = math.floor(dayTime / 3600)
                local openH = self.storeOpenHour or 8
                local closeH = self.storeCloseHour or 19
                isOpen = (hour >= openH and hour < closeH)
            end

            if not isOpen then
                if g_currentMission and g_currentMission.showBlinkingWarning then
                    g_currentMission:showBlinkingWarning("Store Closed", 4000)
                end
                print(string.format("[%s] Store is closed — delivery blocked", self.modName))
                return
            end

            local num = obj:getNumOfAnimals()
            local t = obj:getCurrentAnimalType()
            local typeName = (t and t.name) or "COW"

            print(string.format("[%s] Animal trailer entered trigger (%s)! XML=%s | Total=%d | Type=%s",
                self.modName, barnKey, tostring(obj.configFileName), num, typeName))

            local cs = obj.spec_livestockTrailer and obj.spec_livestockTrailer.clusterSystem
            if cs and cs.animals then
                print(string.format("[%s] ---- TRAILER CLUSTER REPORT ----", self.modName))
                print(string.format("[%s] Total clusters: %d", self.modName, #cs.animals))
                for idx, cluster in ipairs(cs.animals) do
                    local age  = cluster.age or -1
                    local numA = cluster.numAnimals or 0
                    local wt   = cluster.weight or 0
                    local sub  = cluster.subTypeIndex or -1
                    local gen  = cluster.gender or "unknown"
                    print(string.format("[%s] Cluster %d | num=%d | age=%d months | weight=%.1f kg | gender=%s | subType=%d",
                        self.modName, idx, numA, age, wt, gen, sub))
                end
                print(string.format("[%s] ---- END CLUSTER REPORT ----", self.modName))
            end

            local cap = self:checkBarnCapacity(typeName, barn)
            if cap then
                print(string.format("[%s] Barn ready for %d (%s)", self.modName, cap.avail, cap.fillType))
            end

            self.trailersInTrigger[obj] = {type = typeName, num = num, barn = barn, barnKey = barnKey}
        elseif onLeave then
            print("["..self.modName.."] Trailer left trigger")
            self.trailersInTrigger[obj] = nil
        end
    end

    if g_currentMission.player and g_currentMission.player.rootNode == otherId then
        PRBFix.playerInTrigger = onEnter
    end

    local controlled = g_currentMission.controlledVehicle
    if controlled and controlled.rootNode == otherId then
        PRBFix.playerInTrigger = onEnter
    end
end

----------------------------------------------------------------
-- CHECK BARN CAPACITY
----------------------------------------------------------------
function PRBFix:checkBarnCapacity(animalType)
    local barn = self.butcherBarnPlaceable
    if not barn then return nil end

    local spec = barn.spec_extendedProductionPoint
    if not spec or not spec.productionPoint or not spec.productionPoint.storage then return nil end

    local fill = self.ANIMAL_TO_MEAT_FILLTYPE[animalType]
    if not fill then return nil end

    local ftIdx = g_fillTypeManager:getFillTypeIndexByName(fill)
    local st = spec.productionPoint.storage
    local old = st:getFillLevel(ftIdx)
    local cap = st:getCapacity(ftIdx)
    local avail = cap - old

    print(string.format("[%s] DEBUG Barn capacity check: %s old=%d | cap=%d | avail=%d",
        self.modName, fill, old, cap, avail))

    local minAge, maxAge = nil, nil
    local xml = barn.xmlFile
    if xml then
        xml:iterate(barn.configFileName .. ".animalInput.animal", function(_, key)
            local t = xml:getString(key .. "#type")
            if t == animalType then
                minAge = xml:getInt(key .. "#minimumAge") or 0
                maxAge = xml:getInt(key .. "#maximumAge") or 999
            end
        end)
    end

    return {
        fillType = fill,
        old = old,
        cap = cap,
        avail = avail,
        minAge = minAge,
        maxAge = maxAge
    }
end

----------------------------------------------------------------
-- COUNT VALID ANIMALS
----------------------------------------------------------------
function PRBFix:countValidAnimals(trailer, animalType)
    local rule = PRBFix.AGE_RULES[animalType]
    if not rule then
        print(string.format("[%s] ❌ No AGE_RULES entry for %s", self.modName, tostring(animalType)))
        return 0, {}
    end

    local minAge = rule.min
    local maxAge = rule.max
    print(string.format("[%s] 🔍 Age filter for %s = %d–%d months", self.modName, animalType, minAge, maxAge))

    local cs = trailer.spec_livestockTrailer and trailer.spec_livestockTrailer.clusterSystem
    if not cs or not cs.animals then
        print(string.format("[%s] ❌ Trailer clusterSystem empty", self.modName))
        return 0, {}
    end

    local valid = {}
    local count = 0

    print(string.format("[%s] ---- AGE FILTER CHECK BEGIN ----", self.modName))
    for idx, cluster in ipairs(cs.animals) do
        local age = cluster.age or 0
        local num = cluster.numAnimals or 0
        local ok = (age >= minAge and age <= maxAge)
        print(string.format("[%s] Cluster %d | age=%d | num=%d | VALID=%s", self.modName, idx, age, num, tostring(ok)))
        if ok then
            count = count + num
            table.insert(valid, idx)
        end
    end
    print(string.format("[%s] ---- AGE FILTER CHECK END ----", self.modName))
    print(string.format("[%s] RESULT: %d valid animals | valid clusters = %s", self.modName, count, table.concat(valid, ", ")))

    return count, valid
end

----------------------------------------------------------------
-- ON DELIVER KEY PRESSED
----------------------------------------------------------------
function PRBFix:onDeliverKeyPressed(actionName, value, state, isAnalog)
    if g_currentMission and g_currentMission.environment then
        local dayTime = g_currentMission.environment.dayTime / 1000
        local hour = math.floor(dayTime / 3600)
        local openH = self.storeOpenHour or 8
        local closeH = self.storeCloseHour or 19
        if hour < openH or hour >= closeH then
            if g_currentMission.showBlinkingWarning then
                g_currentMission:showBlinkingWarning("Store Closed", 4000)
            end
            return
        end
    end

    if not next(self.trailersInTrigger) then return end

    print(string.format("[%s] 🔔 onDeliverKeyPressed fired", self.modName))

    for trailer, data in pairs(self.trailersInTrigger) do
        local numNow = trailer:getNumOfAnimals() or 0
        data.num = numNow
        print(string.format("[%s] 🔄 Fresh trailer count = %d animals", self.modName, numNow))

        local cap = self:checkBarnCapacity(data.type)
        if not cap then
            print("["..self.modName.."] ⚠ No production storage found")
            return
        end

        local validCount, validClusters = self:countValidAnimals(trailer, data.type)
        local invalidCount = math.max(0, numNow - validCount)
        print(string.format("[%s] 🔄 Fresh valid=%d | invalid=%d", self.modName, validCount, invalidCount))

        local cs = trailer.spec_livestockTrailer and trailer.spec_livestockTrailer.clusterSystem
        local clusterStats = {}
        local totalValidWeight = 0
        local totalRawWeight = 0

        if cs and cs.animals then
            local breedMulSum = 0
            local breedCount = 0
            for _, idx in ipairs(validClusters) do
                local c = cs.animals[idx]
                if c then
                    local num = c.numAnimals or 0
                    local w = tonumber(c.weight or 0) or 0.0
                    local q = 1.0
                    if c.genetics ~= nil and c.genetics.quality ~= nil then
                        q = tonumber(c.genetics.quality) or 1.0
                    end
                    local breedMul = PRBFix:getBreedMultiplier(data.type, c)
                    local adjW = w * q * breedMul
                    local totalW = num * adjW

                    totalValidWeight = totalValidWeight + totalW
                    totalRawWeight = totalRawWeight + w
                    breedMulSum = breedMulSum + (breedMul * num)
                    breedCount = breedCount + num

                    table.insert(clusterStats, {
                        index = idx, num = num, rawWeight = w, quality = q,
                        breedMul = breedMul, weight = adjW, totalWeight = totalW
                    })
                end
            end
            data.breedBonus = breedCount > 0 and (breedMulSum / breedCount) or 1.0
        end

        local avgQuality = totalRawWeight > 0 and (totalValidWeight / totalRawWeight) or 1.0
        data.avgQuality = avgQuality

        local maxDeliverable = math.max(0, math.min(cap.avail, validCount))

        data.validCount = validCount
        data.invalidCount = invalidCount
        data.validClusters = validClusters
        data.validClusterStats = clusterStats
        data.totalValidWeight = totalValidWeight

        local farmId = 1
        if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
            farmId = g_currentMission:getFarmId()
        end

        local barnName = "THE BUTCHER BARN"
        if self.butcherBarnPlaceable ~= nil then
            if self.butcherBarnPlaceable.getName ~= nil then
                barnName = self.butcherBarnPlaceable:getName()
            elseif self.butcherBarnPlaceable.name ~= nil then
                barnName = self.butcherBarnPlaceable.name
            end
        end

        self.dialogData = {
            trailer = trailer, data = data, cap = cap, max = maxDeliverable,
            farmId = farmId, barnName = barnName, callbackObject = self
        }

        if g_gui and PRBDialog and PRBDialog.register then
            PRBDialog.register()
            if PRBDialog.INSTANCE then
                PRBDialog.INSTANCE:setDialogData(self.dialogData)
                print(string.format("[%s] 🧭 Opened Butcher Barn dialog | max=%d", self.modName, maxDeliverable))
                g_gui:showDialog("PRBDialog")
            else
                print("["..self.modName.."] ❌ Dialog instance missing")
                self:deliverAnimals(trailer, data, maxDeliverable)
            end
        else
            print("["..self.modName.."] ❌ Dialog class not loaded")
            self:deliverAnimals(trailer, data, maxDeliverable)
        end
        return
    end
end

----------------------------------------------------------------
-- DELIVER ANIMALS FROM DIALOG
----------------------------------------------------------------
function PRBFix:deliverAnimalsFromDialog(trailer, data, amount, farmId)
    print(string.format("[%s] deliverAnimalsFromDialog called, amount=%d, farmId=%s",
        self.modName, amount or -1, tostring(farmId)))

    if amount == nil or amount <= 0 then return end
    if trailer == nil then return end
    if self.butcherBarnPlaceable == nil then return end

    farmId = farmId or 1
    if farmId == 1 and g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        farmId = g_currentMission:getFarmId()
    end

    if PR_DeliverAnimalsEvent ~= nil then
        print(string.format("[%s] ▶ Sending PR_DeliverAnimalsEvent (amount=%d, farmId=%d)", self.modName, amount, farmId))
        PR_DeliverAnimalsEvent.send(farmId, self.butcherBarnPlaceable, trailer, amount, false)
    else
        if self.deliverAnimals ~= nil then
            self:deliverAnimals(trailer, data, amount, farmId)
        end
    end
end

----------------------------------------------------------------
-- DELIVER ANIMALS
-- Credits delivered animals to the target barn and farm ledger
----------------------------------------------------------------
function PRBFix:deliverAnimals(trailer, data, amount, farmId)
    if trailer == nil or data == nil then return end

    local typeName = data.type or "UNKNOWN"
    local validClusters = data.validClusters or {}

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or #validClusters == 0 then return end

    local barn = data.barn or self.butcherBarnPlaceable
    if barn == nil then return end
    local barnKey = data.barnKey or self:getBarnKey(barn)

    local cap = self:checkBarnCapacity(typeName, barn)
    if cap == nil then return end

    local spec = barn.spec_extendedProductionPoint
    if spec == nil or spec.productionPoint == nil or spec.productionPoint.storage == nil then return end

    local st = spec.productionPoint.storage
    local ftIdx = g_fillTypeManager:getFillTypeIndexByName(cap.fillType)
    if ftIdx == nil then return end

    local specTrailer = trailer.spec_livestockTrailer
    if specTrailer == nil then return end

    local cs = specTrailer.clusterSystem
    if cs == nil or cs.animals == nil then return end

    local baseline = 600.0
    if PRBFix.AVGWEIGHT ~= nil then
        local entry = PRBFix.AVGWEIGHT[typeName]
        if type(entry) == "table" then
            baseline = entry[1] or baseline
        elseif type(entry) == "number" then
            baseline = entry
        end
    end

    local animalUnits = {}
    for _, idx in ipairs(validClusters) do
        local cluster = cs.animals[idx]
        if cluster ~= nil then
            local cNum = math.max(0, math.floor(tonumber(cluster.numAnimals or 0) or 0))
            local rawW = tonumber(cluster.weight or 0) or 0.0
            local q = 1.0
            if cluster.genetics ~= nil and cluster.genetics.quality ~= nil then
                q = tonumber(cluster.genetics.quality) or 1.0
            end
            local breedMul = PRBFix:getBreedMultiplier(typeName, cluster)
            local adjW = rawW * q * breedMul

            for _ = 1, cNum do
                table.insert(animalUnits, {
                    cluster = cluster,
                    weight = adjW
                })
            end
        end
    end

    if #animalUnits == 0 then return end
    if amount > #animalUnits then amount = #animalUnits end

    local prefix = {0.0}
    for i, unit in ipairs(animalUnits) do
        prefix[i + 1] = prefix[i] + (unit.weight or 0.0)
    end

    local function totalWeightFor(n)
        if n <= 0 then return 0.0 end
        if n > #animalUnits then n = #animalUnits end
        return prefix[n + 1] - prefix[1]
    end

    local function litersFor(n)
        local w = totalWeightFor(n)
        if baseline <= 0 then return 0.0 end
        return w / baseline
    end

    local requested = amount
    local used = requested
    local availLiters = cap.avail or (cap.cap - cap.old)

    if litersFor(used) > availLiters + 0.0001 then
        while used > 0 and litersFor(used) > availLiters + 0.0001 do
            used = used - 1
        end
        print(string.format("[%s] ⚖ Smart-Fit trimmed delivery from %d to %d animals", self.modName, requested, used))
    end

    if used <= 0 then return end

    local liters = litersFor(used)

    local oldFill = cap.old
    local newFill = oldFill + liters
    if newFill > cap.cap then
        newFill = cap.cap
        liters = cap.cap - oldFill
    end

    st:setFillLevel(newFill, ftIdx)

    if g_server ~= nil and liters > 0 then
        if farmId and farmId > 0 then
            PRBFix.farmMeat[barnKey] = PRBFix.farmMeat[barnKey] or {}
            PRBFix.farmMeat[barnKey][farmId] = PRBFix.farmMeat[barnKey][farmId] or {}

            local function getHoursFor(productName)
                if self.barnSettings and self.barnSettings[productName] then
                    return self.barnSettings[productName]
                end
                return 5
            end

            local now = g_currentMission.environment.currentMonotonicDay * 86400 + g_currentMission.environment.dayTime / 1000

            PRBFix.farmMeatPallets = PRBFix.farmMeatPallets or {}
            PRBFix.farmMeatPallets[barnKey] = PRBFix.farmMeatPallets[barnKey] or {}
            PRBFix.farmMeatPallets[barnKey][farmId] = PRBFix.farmMeatPallets[barnKey][farmId] or {}

            local function addFinished(fillType, amount, productName)
                if amount > 0.01 then
                    local hours = getHoursFor(productName or fillType)
                    local neededSeconds = hours * 3600

                    local openH = self.storeOpenHour or 8
                    local closeH = self.storeCloseHour or 19
                    local openSec = openH * 3600
                    local closeSec = closeH * 3600
                    local dayLen = 86400

                    local t = now
                    local remaining = neededSeconds

                    while remaining > 0 do
                        local dayStart = math.floor(t / dayLen) * dayLen
                        local openAt = dayStart + openSec
                        local closeAt = dayStart + closeSec

                        if t < openAt then
                            t = openAt
                        end

                        if t < closeAt then
                            local available = closeAt - t
                            if available >= remaining then
                                t = t + remaining
                                remaining = 0
                            else
                                remaining = remaining - available
                                t = dayStart + dayLen
                            end
                        else
                            t = dayStart + dayLen
                        end
                    end

                    local newReadyAt = t

                    local entry = PRBFix.farmMeatPallets[barnKey][farmId][fillType]
                    if entry == nil or type(entry) ~= "table" then
                        entry = {amount = 0, readyAt = newReadyAt, barnId = barnKey}
                    end

                    local oldAmount = entry.amount or 0
                    local oldReadyAt = entry.readyAt or newReadyAt

                    local function remainingOpenSeconds(readyTime)
                        local tt = now
                        local left = 0

                        while tt < readyTime do
                            local dayStart = math.floor(tt / dayLen) * dayLen
                            local openAt = dayStart + openSec
                            local closeAt = dayStart + closeSec

                            if tt < openAt then
                                tt = openAt
                            end

                            if tt < closeAt and tt < readyTime then
                                local endTime = math.min(closeAt, readyTime)
                                left = left + (endTime - tt)
                                tt = endTime
                            else
                                tt = dayStart + dayLen
                            end
                        end
                        return left
                    end

                    local oldOpenLeft = remainingOpenSeconds(oldReadyAt)
                    local newOpenLeft = remainingOpenSeconds(newReadyAt)
                    local avgOpenLeft = (oldAmount * oldOpenLeft + amount * newOpenLeft) / (oldAmount + amount)

                    t = now
                    remaining = avgOpenLeft

                    while remaining > 0 do
                        local dayStart = math.floor(t / dayLen) * dayLen
                        local openAt = dayStart + openSec
                        local closeAt = dayStart + closeSec

                        if t < openAt then
                            t = openAt
                        end

                        if t < closeAt then
                            local available = closeAt - t
                            if available >= remaining then
                                t = t + remaining
                                remaining = 0
                            else
                                remaining = remaining - available
                                t = dayStart + dayLen
                            end
                        else
                            t = dayStart + dayLen
                        end
                    end

                    entry.amount = oldAmount + amount
                    entry.readyAt = t
                    entry.barnId = barnKey
                    PRBFix.farmMeatPallets[barnKey][farmId][fillType] = entry

                    print(string.format("[%s] Credited %.1f L %s (ready ~%.0f min) to farm %d at barn %s",
                        self.modName, amount, fillType, (entry.readyAt - now) / 60, farmId, barnKey))
                end
            end

            local meatName = self.ANIMAL_TO_MEAT_FILLTYPE[typeName] or typeName
            if meatName == "POULTRY" then
                addFinished("CHICKENFILLET", liters * 35, "Chicken Fillet")
            elseif meatName == "COWMEAT" then
                addFinished("GROUNDBEEF", liters * 220, "Ground Beef")
                addFinished("STEAK", liters * 220, "Steak")
                addFinished("SAUSAGE", liters * 105, "Sausage")
                addFinished("PEPPERONI", liters * 105, "Pepperoni")
            elseif meatName == "PIGMEAT" then
                addFinished("HAM", liters * 105, "Ham")
                addFinished("PORK", liters * 75, "Pork")
                addFinished("BACON", liters * 45, "Bacon")
                addFinished("SAUSAGE", liters * 30, "Sausage")
                addFinished("PEPPERONI", liters * 30, "Pepperoni")
            elseif meatName == "SHEEPMEAT" then
                addFinished("MUTTON", liters * 150, "Mutton")
                addFinished("CHEVON", liters * 150, "Chevon")
            end

            PRBFix.pendingConversions = PRBFix.pendingConversions or {}
            local CONVERT_SECONDS = 300
            local convertAt = now + CONVERT_SECONDS

            local outputs = {}
            if meatName == "POULTRY" then
                outputs["CHICKENFILLET"] = liters * 35
            elseif meatName == "COWMEAT" then
                outputs["GROUNDBEEF"] = liters * 220
                outputs["STEAK"] = liters * 220
                outputs["SAUSAGE"] = liters * 105
                outputs["PEPPERONI"] = liters * 105
            elseif meatName == "PIGMEAT" then
                outputs["HAM"] = liters * 105
                outputs["PORK"] = liters * 75
                outputs["BACON"] = liters * 45
                outputs["SAUSAGE"] = liters * 30
                outputs["PEPPERONI"] = liters * 30
            elseif meatName == "SHEEPMEAT" then
                outputs["MUTTON"] = liters * 150
                outputs["CHEVON"] = liters * 150
            end

            table.insert(PRBFix.pendingConversions, {
                rawFillType = cap.fillType,
                rawAmount = liters,
                outputs = outputs,
                convertAt = convertAt,
                barnKey = barnKey
            })

            print(string.format("[%s] Queued 5-min conversion for %.1f L %s", self.modName, liters, meatName))
            PRBFix:syncFarmMeat()
        end
    end

    local pp = spec.productionPoint
    if pp ~= nil then
        if pp.raiseDirtyFlags ~= nil then pp:raiseDirtyFlags(pp.dirtyFlag or 1) end
        if pp.setIsDirty ~= nil then pp:setIsDirty() end
        if pp.raiseActive ~= nil then pp:raiseActive() end
    end

    PR_DeliverAnimalsEvent.send(barn, trailer, used, true, newFill, typeName)

    print(string.format("[%s] ➕ Added %.2f L %s from %d animals", self.modName, liters, typeName, used))

    local clustersToRemove = {}
    for i = 1, used do
        local unit = animalUnits[i]
        if unit and unit.cluster ~= nil then
            table.insert(clustersToRemove, unit.cluster)
        end
    end

    for _, animal in ipairs(clustersToRemove) do
        if animal ~= nil then
            cs:addPendingRemoveCluster(animal)
        end
    end

    if cs.updateNow ~= nil then
        cs:updateNow()
    elseif cs.updateClusters ~= nil then
        cs:updateClusters()
    end

    if trailer.spec_livestockTrailer and trailer.spec_livestockTrailer.updateAnimals ~= nil then
        trailer.spec_livestockTrailer:updateAnimals()
    end

    if trailer.raiseActive ~= nil then trailer:raiseActive() end
    if barn ~= nil and barn.raiseDirtyFlags ~= nil then
        barn:raiseDirtyFlags(barn.placeableDirtyFlag or 1)
    end

    print(string.format("[%s] ✅ Removed %d animals via filtered clusters", self.modName, used))
end

----------------------------------------------------------------
-- APPLY DELIVERY RESULT (CLIENT)
----------------------------------------------------------------
function PRBFix:applyDeliveryResult(trailer, animalType, count)
    if trailer == nil then return end

    local spec = trailer.spec_livestockTrailer
    if spec == nil or spec.clusterSystem == nil or spec.clusterSystem.animals == nil then return end

    local cs = spec.clusterSystem
    local removed = 0

    for i = #cs.animals, 1, -1 do
        if removed < count then
            cs:removeCluster(i)
            removed = removed + 1
        end
    end

    if cs.updateClusters ~= nil then cs:updateClusters() end
    if spec.updateVisuals ~= nil then spec:updateVisuals() end
    if spec.updateAnimalVisuals ~= nil then spec:updateAnimalVisuals() end
    if spec.refreshVisuals ~= nil then spec:refreshVisuals() end
    if spec.updateFillUnit ~= nil then spec:updateFillUnit() end

    if spec.visualAnimals ~= nil then
        for i = #spec.visualAnimals, 1, -1 do
            local va = spec.visualAnimals[i]
            if va ~= nil and va.delete ~= nil then va:delete() end
            table.remove(spec.visualAnimals, i)
        end
    end

    if trailer.setIsDirty ~= nil then trailer:setIsDirty() end
    if trailer.raiseDirtyFlags ~= nil then
        trailer:raiseDirtyFlags(trailer.vehicleDirtyFlag or 1)
    end

    print(string.format("[%s] ✅ Client applied delivery result: removed %d animals from trailer", self.modName, removed))
end


----------------------------------------------------------------
-- SAVE MEAT LEDGER
-- Writes PR_ButcherBarn.xml grouped by active <barn> tags;
-- omits ledger rows when no butcher barn exists on the map
----------------------------------------------------------------
function PRBFix:saveMeatLedger()
    if g_server == nil then return end
    if g_currentMission == nil or g_currentMission.missionInfo == nil then return end

    local saveDir = g_currentMission.missionInfo.savegameDirectory
    if saveDir == nil then return end

    self:loadBarnSettings()
    self:scanButcherPlaceables()

    local activeBarns = {}
    local placeables = g_currentMission and g_currentMission.placeableSystem and g_currentMission.placeableSystem.placeables
    if placeables then
        for _, p in pairs(placeables) do
            if p.configFileName and p.configFileName:match("theButcherBarn.xml") then
                local barnKey, posStr, ownerId = self:getBarnIdentity(p)
                table.insert(activeBarns, {
                    barnKey = barnKey,
                    posKey = self:getBarnKey(p),
                    posStr = posStr,
                    ownerId = ownerId
                })
            end
        end
    end

    local xmlPath = saveDir .. "/PR_ButcherBarn.xml"
    local xmlFile = XMLFile.create("PR_ButcherBarn", xmlPath, "butcherBarn")
    if xmlFile == nil then return end

    local now = 0
    if g_currentMission and g_currentMission.environment then
        now = g_currentMission.environment.currentMonotonicDay * 86400 + g_currentMission.environment.dayTime / 1000
    end

    local writtenBarns = 0
    local writtenFarms = 0

    if #activeBarns > 0 then
        for barnIdx, barnInfo in ipairs(activeBarns) do
            local barnPath = string.format("butcherBarn.barn(%d)", barnIdx - 1)
            xmlFile:setString(barnPath .. "#id", barnInfo.barnKey)
            xmlFile:setInt(barnPath .. "#ownerFarmId", barnInfo.ownerId)
            xmlFile:setString(barnPath .. "#position", barnInfo.posStr)
            writtenBarns = writtenBarns + 1

            local barnMeatByFarm = (PRBFix.farmMeat and PRBFix.farmMeat[barnInfo.posKey]) or {}
            local barnPalletsByFarm = (PRBFix.farmMeatPallets and PRBFix.farmMeatPallets[barnInfo.posKey]) or {}

            local farmIds = {}
            for farmId in pairs(barnMeatByFarm) do farmIds[farmId] = true end
            for farmId in pairs(barnPalletsByFarm) do farmIds[farmId] = true end

            local farmIndex = 0
            for farmId in pairs(farmIds) do
                local meats = barnMeatByFarm[farmId] or {}
                local pallets = barnPalletsByFarm[farmId] or {}
                local empty = meats["EMPTYPALLET"] or 0

                local hasAnyPallet = false
                for _, entry in pairs(pallets) do
                    if type(entry) == "table" and entry.amount and entry.amount > 0.01 then
                        hasAnyPallet = true
                        break
                    end
                end

                if empty > 0.01 or hasAnyPallet then
                    local farmKey = string.format("%s.farm(%d)", barnPath, farmIndex)
                    xmlFile:setInt(farmKey .. "#id", farmId)

                    local farmName = "Farm " .. tostring(farmId)
                    if g_farmManager and g_farmManager.farms then
                        for _, farm in pairs(g_farmManager.farms) do
                            if farm and (farm.farmId == farmId or farm.id == farmId) then
                                if farm.name and farm.name ~= "" then farmName = farm.name end
                                break
                            end
                        end
                    end
                    xmlFile:setString(farmKey .. ".name", farmName)

                    if empty > 0.01 then
                        xmlFile:setFloat(farmKey .. ".emptyPallet", empty)
                    end

                    local procIndex = 0
                    local availIndex = 0
                    for fillType, entry in pairs(pallets) do
                        if type(entry) == "table" and entry.amount and entry.amount > 0.01 then
                            if entry.readyAt and now >= entry.readyAt then
                                local key = string.format("%s.available(%d)", farmKey, availIndex)
                                xmlFile:setString(key .. "#type", fillType)
                                xmlFile:setFloat(key .. "#amount", entry.amount)
                                xmlFile:setFloat(key .. "#readyAt", entry.readyAt or 0)
                                availIndex = availIndex + 1
                            else
                                local key = string.format("%s.processing(%d)", farmKey, procIndex)
                                xmlFile:setString(key .. "#type", fillType)
                                xmlFile:setFloat(key .. "#amount", entry.amount)
                                xmlFile:setFloat(key .. "#readyAt", entry.readyAt or 0)
                                procIndex = procIndex + 1
                            end
                        end
                    end

                    farmIndex = farmIndex + 1
                    writtenFarms = writtenFarms + 1
                end
            end
        end
    else
        PRBFix.farmMeat = {}
        PRBFix.farmMeatPallets = {}
    end

    xmlFile:save()
    xmlFile:delete()
    print(string.format("[%s] Saved butcher barn ledger (%d barns, %d farm entries) to %s",
        self.modName, writtenBarns, writtenFarms, xmlPath))
end


----------------------------------------------------------------
-- LOAD MEAT LEDGER
-- Reads saved farm pallet and empty-pallet balances from
-- PR_ButcherBarn.xml into per-barn [barnKey][farmId] tables
----------------------------------------------------------------
function PRBFix:loadMeatLedger()
    if g_server == nil then return end
    if g_currentMission == nil or g_currentMission.missionInfo == nil then return end

    local saveDir = g_currentMission.missionInfo.savegameDirectory
    if saveDir == nil then return end

    local xmlPath = saveDir .. "/PR_ButcherBarn.xml"
    if not fileExists(xmlPath) then
        print("["..self.modName.."] No butcher barn ledger file found (new save)")
        return
    end

    local xmlFile = XMLFile.load("PR_ButcherBarn", xmlPath)
    if xmlFile == nil then return end

    PRBFix.farmMeat = {}
    PRBFix.farmMeatPallets = {}
    self.barnMeta = self.barnMeta or {}

    local function readFarmEntriesFromPath(basePath, barnKey)
        PRBFix.farmMeat[barnKey] = PRBFix.farmMeat[barnKey] or {}
        PRBFix.farmMeatPallets[barnKey] = PRBFix.farmMeatPallets[barnKey] or {}

        local farmIndex = 0
        while true do
            local farmKey = string.format("%s.farm(%d)", basePath, farmIndex)
            if not xmlFile:hasProperty(farmKey) then break end

            local farmId = xmlFile:getInt(farmKey .. "#id")
            if farmId ~= nil then
                PRBFix.farmMeat[barnKey][farmId] = PRBFix.farmMeat[barnKey][farmId] or {}
                PRBFix.farmMeatPallets[barnKey][farmId] = PRBFix.farmMeatPallets[barnKey][farmId] or {}

                local empty = xmlFile:getFloat(farmKey .. ".emptyPallet") or 0
                if empty > 0.01 then
                    PRBFix.farmMeat[barnKey][farmId]["EMPTYPALLET"] = (PRBFix.farmMeat[barnKey][farmId]["EMPTYPALLET"] or 0) + empty
                end

                local procIndex = 0
                while true do
                    local key = string.format("%s.processing(%d)", farmKey, procIndex)
                    if not xmlFile:hasProperty(key) then break end
                    local fillType = xmlFile:getString(key .. "#type")
                    local amount = xmlFile:getFloat(key .. "#amount") or 0
                    local readyAt = xmlFile:getFloat(key .. "#readyAt") or 0
                    if fillType ~= nil then
                        local existing = PRBFix.farmMeatPallets[barnKey][farmId][fillType]
                        if existing then
                            existing.amount = existing.amount + amount
                            existing.readyAt = math.min(existing.readyAt or readyAt, readyAt)
                        else
                            PRBFix.farmMeatPallets[barnKey][farmId][fillType] = {amount = amount, readyAt = readyAt, barnId = barnKey}
                        end
                    end
                    procIndex = procIndex + 1
                end

                local availIndex = 0
                while true do
                    local key = string.format("%s.available(%d)", farmKey, availIndex)
                    if not xmlFile:hasProperty(key) then break end
                    local fillType = xmlFile:getString(key .. "#type")
                    local amount = xmlFile:getFloat(key .. "#amount") or 0
                    local readyAt = xmlFile:getFloat(key .. "#readyAt") or 0
                    if fillType ~= nil then
                        local existing = PRBFix.farmMeatPallets[barnKey][farmId][fillType]
                        if existing then
                            existing.amount = existing.amount + amount
                            existing.readyAt = math.min(existing.readyAt or readyAt, readyAt)
                        else
                            PRBFix.farmMeatPallets[barnKey][farmId][fillType] = {amount = amount, readyAt = readyAt, barnId = barnKey}
                        end
                    end
                    availIndex = availIndex + 1
                end
            end
            farmIndex = farmIndex + 1
        end
        return farmIndex
    end

    local totalFarms = 0
    local barnIndex = 0
    while true do
        local barnPath = string.format("butcherBarn.barn(%d)", barnIndex)
        if not xmlFile:hasProperty(barnPath) then break end

        local barnId = xmlFile:getString(barnPath .. "#id") or ("barn_" .. tostring(barnIndex + 1))
        local ownerFarmId = xmlFile:getInt(barnPath .. "#ownerFarmId") or 1
        local posStr = xmlFile:getString(barnPath .. "#position") or "0.00 0.00 0.00"
        local posKey = "pos_" .. posStr:gsub("%s+", "_")

        self.barnMeta[barnId] = {
            id = barnId,
            posKey = posKey,
            ownerFarmId = ownerFarmId,
            position = posStr
        }

        totalFarms = totalFarms + readFarmEntriesFromPath(barnPath, posKey)
        barnIndex = barnIndex + 1
    end

    if barnIndex == 0 then
        totalFarms = totalFarms + readFarmEntriesFromPath("butcherBarn", "pos_0.00_0.00_0.00")
    end

    xmlFile:delete()
    self:syncFarmMeat()
    print(string.format("[%s] Loaded butcher barn ledger (%d barns, %d farm entries)", self.modName, barnIndex, totalFarms))
end


FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, function()
    if PRBFix ~= nil and PRBFix.saveMeatLedger ~= nil then
        PRBFix:saveMeatLedger()
    end
end)


----------------------------------------------------------------
-- VISIBILITY OVERRIDE
----------------------------------------------------------------
function PRBFix:installVisibilityOverride()
    print("[PR Butcher Fix] installVisibilityOverride called")
    if self.butcherBarnPlaceable == nil then return end
    self:installVisibilityOverrideForBarn(self.butcherBarnPlaceable)
    print("[PR Butcher Fix] Done")
end

----------------------------------------------------------------
-- FARM BALANCE OVERLAY
----------------------------------------------------------------
function PRBFix:installFarmBalanceOverlay()
    if PRBFix.overlayInstalled then return end
    PRBFix.overlayInstalled = true
    PRBFix.overlayFarmIndex = 1

    if InGameMenuProductionFrame == nil or InGameMenuProductionFrame.draw == nil then
        print("[PR Butcher Fix] InGameMenuProductionFrame.draw not ready")
        return
    end

    local oldDraw = InGameMenuProductionFrame.draw
    InGameMenuProductionFrame.draw = function(frame)
        if oldDraw then oldDraw(frame) end
        PRBFix:drawFarmBalanceOverlay(frame)
    end

    print("[PR Butcher Fix] Farm balance overlay installed")
end

----------------------------------------------------------------
-- DRAW FARM BALANCE OVERLAY
-- Renders store hours, processing times, and the selected barn's
-- processing queue, empty pallets, and ready pickups in the menu
----------------------------------------------------------------
function PRBFix:drawFarmBalanceOverlay(frame)
    if frame == nil or frame.getSelectedProduction == nil then return end

    local production, productionPoint = frame:getSelectedProduction()
    if productionPoint == nil then return end

    local placeable = productionPoint.owningPlaceable
    if placeable == nil or placeable.configFileName == nil then return end
    if not placeable.configFileName:find("theButcherBarn") then return end

    local barnKey = self:getBarnKey(placeable)

    -- Helper box: store hours + processing times
    local hx = 0.24
    local hy = 0.90
    local hLine = 0.016
    local hWidth = 0.13
    local hLines = {}

    local openH = self.storeOpenHour or 8
    local closeH = self.storeCloseHour or 19
    local openStr = string.format("%d am", openH)
    local closeStr = (closeH > 12) and string.format("%d pm", closeH - 12) or string.format("%d", closeH)

    table.insert(hLines, {text = "", isHeader = true})
    table.insert(hLines, {text = string.format("Store Hours:  %s - %s", openStr, closeStr), isHeader = true})
    table.insert(hLines, {text = "", isHeader = true})
    table.insert(hLines, {text = "Processing Times", isHeader = true})
    table.insert(hLines, {text = "--------------------", isHeader = true})

    local order = {
        "Chicken Fillet", "Bacon", "Ham", "Pork", "Sausage",
        "Pepperoni", "Chevon", "Mutton", "Ground Beef", "Steak"
    }
    local settings = self.barnSettings or {}
    for _, name in ipairs(order) do
        local hrs = settings[name] or 5
        table.insert(hLines, {name = name, hours = hrs, isHeader = false})
    end

    local hHeight = (#hLines * hLine) + 0.03
    drawFilledRect(hx - 0.008, hy - hHeight + 0.01, hWidth, hHeight, 0, 0, 0, 0.75)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)

    local ty = hy
    local hoursX = hx + 0.035

    for _, line in ipairs(hLines) do
        if line.isHeader then
            renderText(hx, ty, 0.013, line.text)
        else
            renderText(hx, ty, 0.013, line.name)
            setTextAlignment(RenderText.ALIGN_RIGHT)
            renderText(hoursX + 0.04, ty, 0.013, tostring(line.hours) .. " hrs")
            setTextAlignment(RenderText.ALIGN_LEFT)
        end
        ty = ty - hLine
    end
    setTextBold(false)

    local currentFarmId = g_currentMission:getFarmId()
    if currentFarmId == nil or currentFarmId <= 0 then return end

    local farm = g_farmManager:getFarmById(currentFarmId)
    local farmName = (farm and farm.name) or ("Farm " .. currentFarmId)

    local lines = {}
    table.insert(lines, {text = "", isHeader = false})
    table.insert(lines, {text = "FARM: " .. farmName, isHeader = false})
    table.insert(lines, {text = "--------------------", isHeader = false})
    table.insert(lines, {text = "Processing", isHeader = true})

    local pallets = (PRBFix.farmMeatPallets and PRBFix.farmMeatPallets[barnKey] and PRBFix.farmMeatPallets[barnKey][currentFarmId]) or {}
    local groups = {
        { title = "  Chicken Meat", items = {"CHICKENFILLET"} },
        { title = "  Cow Meat",     items = {"GROUNDBEEF", "STEAK"} },
        { title = "  Pig Meat",     items = {"BACON", "HAM", "PORK"} },
        { title = "  Sheep Meat",   items = {"CHEVON", "MUTTON"} },
        { title = "  Shared",       items = {"SAUSAGE", "PEPPERONI"} }
    }
    local productNames = {
        CHICKENFILLET = "    Chicken Fillet",
        GROUNDBEEF    = "    Ground Beef",
        STEAK         = "    Steak",
        SAUSAGE       = "    Sausage",
        PEPPERONI     = "    Pepperoni",
        HAM           = "    Ham",
        PORK          = "    Pork",
        BACON         = "    Bacon",
        MUTTON        = "    Mutton",
        CHEVON        = "    Chevon"
    }

    local now = 0
    if g_currentMission and g_currentMission.environment then
        now = g_currentMission.environment.currentMonotonicDay * 86400 + g_currentMission.environment.dayTime / 1000
    end

    local hasProcessing = false
    local hasAvailable = false
    local availableLines = {}

    for _, group in ipairs(groups) do
        local groupLines = {}
        for _, fillType in ipairs(group.items) do
            local entry = pallets[fillType]
            if type(entry) == "table" and entry.amount and entry.amount > 0.01 then
                local displayName = productNames[fillType] or ("    " .. fillType)
                if entry.readyAt and now >= entry.readyAt then
                    table.insert(availableLines, {text = displayName, amount = string.format("%.0f L", entry.amount)})
                    hasAvailable = true
                else
                    local remaining = math.max(0, (entry.readyAt or 0) - now)
                    local hours = math.floor(remaining / 3600)
                    local mins  = math.floor((remaining % 3600) / 60)
                    local readyStr = string.format("%dh %02dm", hours, mins)
                    table.insert(groupLines, {text = displayName, amount = string.format("%.0f L", entry.amount), ready = readyStr})
                end
            end
        end
        if #groupLines > 0 then
            hasProcessing = true
            table.insert(lines, {text = group.title, isHeader = false})
            for _, line in ipairs(groupLines) do
                table.insert(lines, line)
            end
        end
    end
    if not hasProcessing then
        table.insert(lines, {text = "  (none)", isHeader = false})
    end

    table.insert(lines, {text = "--------------------", isHeader = false})
    table.insert(lines, {text = "Empty Pallets", isHeader = false})
    local barnMeats = (PRBFix.farmMeat and PRBFix.farmMeat[barnKey] and PRBFix.farmMeat[barnKey][currentFarmId]) or {}
    local emptyPallets = barnMeats["EMPTYPALLET"] or 0
    if emptyPallets > 0.01 then
        table.insert(lines, {text = string.format("  %.0f L", emptyPallets), isHeader = false})
    else
        table.insert(lines, {text = "  (none)", isHeader = false})
    end

    table.insert(lines, {text = "--------------------", isHeader = false})
    table.insert(lines, {text = "Available for pickup", isHeader = false})
    if hasAvailable then
        for _, line in ipairs(availableLines) do
            table.insert(lines, line)
        end
    else
        table.insert(lines, {text = "  (none)", isHeader = false})
    end

    local x = 0.24
    local y = 0.60
    local lineHeight = 0.016
    local width = 0.13
    local height = (#lines * lineHeight) + 0.05
    if height > 0.55 then height = 0.55 end

    drawFilledRect(x - 0.008, y - height + 0.01, width, height, 0, 0, 0, 0.75)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)

    local textY = y
    local nameX   = x
    local amountX = x + 0.060
    local readyX  = x + 0.090

    for _, line in ipairs(lines) do
        if line.isHeader then
            setTextColor(1, 1, 1, 1)
            renderText(nameX, textY, 0.014, line.text)
            renderText(amountX, textY, 0.014, "Amount")
            renderText(readyX, textY, 0.014, "Ready In")
        elseif line.amount then
            setTextColor(0.6, 0.9, 0.7, 1)
            renderText(nameX, textY, 0.014, line.text)
            renderText(amountX, textY, 0.014, line.amount)
            if line.ready then
                renderText(readyX, textY, 0.014, line.ready)
            end
        else
            setTextColor(1, 1, 1, 1)
            renderText(nameX, textY, 0.014, line.text)
        end
        textY = textY - lineHeight
    end

    setTextColor(1, 1, 1, 1)
    setTextBold(false)
end

----------------------------------------------------------------
-- IS BARN LIGHTS WINDOW OPEN
----------------------------------------------------------------
function PRBFix:isBarnLightsWindowOpen()
    if g_currentMission == nil or g_currentMission.environment == nil then
        return true
    end

    local dayLen = 86400
    local nowSec = ((g_currentMission.environment.dayTime or 0) / 1000) % dayLen

    local openH = self.storeOpenHour or 8
    local closeH = self.storeCloseHour or 19

    local onSec = ((openH * 3600) - 1800) % dayLen
    local offSec = ((closeH * 3600) + 1800) % dayLen

    if onSec == offSec then
        return true
    elseif onSec < offSec then
        return nowSec >= onSec and nowSec < offSec
    else
        return nowSec >= onSec or nowSec < offSec
    end
end

----------------------------------------------------------------
-- SET FIXTURE LIGHTS ENABLED
----------------------------------------------------------------
local function setFixtureLightsEnabled(node, enabled)
    if node == nil or node == 0 then return end

    if getNumOfChildren then
        local count = getNumOfChildren(node)
        for i = 0, count - 1 do
            local child = getChildAt(node, i)
            if child ~= nil and child ~= 0 then
                setFixtureLightsEnabled(child, enabled)
            end
        end
    end

    if enabled then
        if setWeatherRequiredMask ~= nil then
            pcall(setWeatherRequiredMask, node, 0)
        end
        setVisibility(node, true)
    else
        if setWeatherRequiredMask ~= nil then
            pcall(setWeatherRequiredMask, node, 0x40)
        end
        setVisibility(node, false)
    end
end

----------------------------------------------------------------
-- UPDATE BARN INTERIOR LIGHTS
----------------------------------------------------------------
function PRBFix:updateBarnInteriorLights(force)
    if not self:isButcherBarnValid() then
        if self.butcherBarnPlaceable ~= nil then
            self:resetButcherBarn()
        end
        return
    end

    local barn = self.butcherBarnPlaceable
    if barn == nil or barn.i3dMappings == nil then return end

    local lightsMapping = barn.i3dMappings["lights"]
    local lightsNode = lightsMapping and lightsMapping.nodeId
    if lightsNode == nil or lightsNode == 0 then return end
    if entityExists ~= nil and not entityExists(lightsNode) then
        self:resetButcherBarn()
        return
    end

    local shouldBeOn = self:isBarnLightsWindowOpen()
    if not force and self.lastBarnLightsState == shouldBeOn then
        return
    end
    self.lastBarnLightsState = shouldBeOn

    local numChildren = (getNumOfChildren and getNumOfChildren(lightsNode)) or 0
    if numChildren <= 0 then return end

    for i = 0, numChildren - 1 do
        local child = getChildAt(lightsNode, i)
        if child ~= nil and child ~= 0 and (entityExists == nil or entityExists(child)) then
            local nodeName = (getName and getName(child)) or ""
            if not string.find(nodeName, "streetLightPoleLarge", 1, true) then
                local childCount = (getNumOfChildren and getNumOfChildren(child)) or 0
                if childCount >= 4 then
                    local blubLit = getChildAt(child, 3)
                    setFixtureLightsEnabled(blubLit, shouldBeOn)
                else
                    setFixtureLightsEnabled(child, shouldBeOn)
                end
            end
        end
    end
end

----------------------------------------------------------------
-- IS BARN DOORS OPEN ALLOWED
----------------------------------------------------------------
function PRBFix:isBarnDoorsOpenAllowed()
    if g_currentMission == nil or g_currentMission.environment == nil then
        return true
    end

    local dayTimeSec = ((g_currentMission.environment.dayTime or 0) / 1000) % 86400
    local hour = math.floor(dayTimeSec / 3600)
    local openH = self.storeOpenHour or 8
    local closeH = self.storeCloseHour or 19

    if openH == closeH then
        return true
    elseif openH < closeH then
        return hour >= openH and hour < closeH
    else
        return hour >= openH or hour < closeH
    end
end

----------------------------------------------------------------
-- HELPER: CLEAR ANIMATED OBJECT ACTION PROMPT
----------------------------------------------------------------
local function clearBarnDoorPrompt(animObj)
    if animObj == nil then return end
    if g_currentMission ~= nil and g_currentMission.activatableObjectsSystem ~= nil then
        pcall(function()
            g_currentMission.activatableObjectsSystem:removeActivatable(animObj)
        end)
    end
    if animObj.removeActionEvents ~= nil then
        pcall(function()
            animObj:removeActionEvents()
        end)
    end
end

----------------------------------------------------------------
-- CLOSE AND LOCK BARN DOORS
----------------------------------------------------------------
function PRBFix:closeAllBarnDoors()
    if g_server == nil then return end

    local barn = self.butcherBarnPlaceable
    local spec = barn and barn.spec_animatedObjects
    if spec == nil or spec.animatedObjects == nil then return end

    for _, animObj in ipairs(spec.animatedObjects) do
        if animObj ~= nil then
            clearBarnDoorPrompt(animObj)

            if animObj.setDirection ~= nil then
                animObj:setDirection(-1)
            end
            if animObj.setAnimTime ~= nil then
                animObj:setAnimTime(0, false)
            end
            animObj.animTime = 0

            if animObj.raiseDirtyFlags ~= nil and animObj.dirtyFlag ~= nil then
                animObj:raiseDirtyFlags(animObj.dirtyFlag)
            end
        end
    end

    if barn.raiseDirtyFlags ~= nil and barn.placeableDirtyFlag ~= nil then
        barn:raiseDirtyFlags(barn.placeableDirtyFlag)
    end
end

----------------------------------------------------------------
-- INSTALL BARN DOOR LOCK HOOK
----------------------------------------------------------------
function PRBFix:installBarnDoorLockHook()
    if self.doorLockHookInstalled or AnimatedObject == nil then return end
    self.doorLockHookInstalled = true

    local function isBarnAnimatedObject(target)
        local barn = PRBFix.butcherBarnPlaceable
        local spec = barn and barn.spec_animatedObjects
        if spec and spec.animatedObjects then
            for _, item in ipairs(spec.animatedObjects) do
                if item == target then
                    return true
                end
            end
        end
        return false
    end

    local origTriggerCallback = AnimatedObject.triggerCallback
    if origTriggerCallback ~= nil then
        AnimatedObject.triggerCallback = function(animObj, triggerId, otherId, onEnter, onLeave, raycastHit)
            if isBarnAnimatedObject(animObj) and not PRBFix:isBarnDoorsOpenAllowed() then
                clearBarnDoorPrompt(animObj)
                if onEnter and g_currentMission and g_currentMission.showBlinkingWarning then
                    g_currentMission:showBlinkingWarning("Store Closed", 4000)
                end
                return
            end

            return origTriggerCallback(animObj, triggerId, otherId, onEnter, onLeave, raycastHit)
        end
    end

    local origRegisterActionEvents = AnimatedObject.registerActionEvents
    if origRegisterActionEvents ~= nil then
        AnimatedObject.registerActionEvents = function(animObj, ...)
            if isBarnAnimatedObject(animObj) and not PRBFix:isBarnDoorsOpenAllowed() then
                clearBarnDoorPrompt(animObj)
                return
            end

            return origRegisterActionEvents(animObj, ...)
        end
    end

    local origSetDirection = AnimatedObject.setDirection
    if origSetDirection ~= nil then
        AnimatedObject.setDirection = function(animObj, direction, ...)
            if isBarnAnimatedObject(animObj) and (direction or 0) > 0 and not PRBFix:isBarnDoorsOpenAllowed() then
                clearBarnDoorPrompt(animObj)
                return
            end

            return origSetDirection(animObj, direction, ...)
        end
    end
end

----------------------------------------------------------------
-- UPDATE BARN DOOR SCHEDULE
----------------------------------------------------------------
function PRBFix:updateBarnDoorSchedule()
    if g_server == nil or self.butcherBarnPlaceable == nil then return end

    local isOpenAllowed = self:isBarnDoorsOpenAllowed()
    if self.lastBarnDoorsOpenAllowed == nil then
        print(string.format("[%s] updateBarnDoorSchedule init: isOpenAllowed=%s (hours %d-%d)",
            self.modName, tostring(isOpenAllowed), self.storeOpenHour or 8, self.storeCloseHour or 19))
        self.lastBarnDoorsOpenAllowed = isOpenAllowed
        if not isOpenAllowed then
            self:closeAllBarnDoors()
        end
        return
    end

    if self.lastBarnDoorsOpenAllowed ~= isOpenAllowed then
        print(string.format("[%s] updateBarnDoorSchedule state change: %s -> %s",
            self.modName, tostring(self.lastBarnDoorsOpenAllowed), tostring(isOpenAllowed)))
    end

    if self.lastBarnDoorsOpenAllowed and not isOpenAllowed then
        self:closeAllBarnDoors()
    end

    self.lastBarnDoorsOpenAllowed = isOpenAllowed
end


function PRBFix:isButcherBarnValid()
    local barn = self.butcherBarnPlaceable
    if barn == nil then return false end
    if barn.isDeleted or barn.removed then return false end
    if g_currentMission == nil or g_currentMission.placeableSystem == nil then return false end

    local placeables = g_currentMission.placeableSystem.placeables
    if placeables == nil then return false end

    for _, p in pairs(placeables) do
        if p == barn then
            return true
        end
    end

    return false
end

----------------------------------------------------------------
-- RESET BUTCHER BARN STATE
-- Removes custom triggers for the target barn (or all if nil)
-- and resets barn/session flags safely for multi-barn setups
----------------------------------------------------------------
function PRBFix:resetButcherBarn(targetBarn)
    self.barnTriggers = self.barnTriggers or {}

    local function removeBarnTriggers(barnObj)
        local nodes = barnObj and self.barnTriggers[barnObj]
        if nodes then
            for _, nodeId in ipairs(nodes) do
                if nodeId and nodeId ~= 0 and removeTrigger then
                    pcall(removeTrigger, nodeId)
                end
            end
            self.barnTriggers[barnObj] = nil
        end
    end

    local removedAny = false

    if targetBarn ~= nil then
        if self.barnTriggers[targetBarn] then
            removeBarnTriggers(targetBarn)
            removedAny = true
        end
        if self.hookedBarns then
            self.hookedBarns[targetBarn] = nil
        end
        if self.barnIds then
            for k, v in pairs(self.barnIds) do
                if v == targetBarn then
                    self.barnIds[k] = nil
                end
            end
        end
        if self.butcherBarnPlaceable == targetBarn then
            self.butcherBarnPlaceable = nil
            removedAny = true
        end
    else
        for barnObj in pairs(self.barnTriggers) do
            removeBarnTriggers(barnObj)
            removedAny = true
        end
        if self.registeredTriggerNodes then
            for _, nodeId in ipairs(self.registeredTriggerNodes) do
                if nodeId and nodeId ~= 0 and removeTrigger then
                    pcall(removeTrigger, nodeId)
                end
            end
            self.registeredTriggerNodes = nil
        end
        self.hookedBarns = {}
        self.barnIds = {}
        if self.butcherBarnPlaceable ~= nil then
            self.butcherBarnPlaceable = nil
            removedAny = true
        end
    end

    -- Pick another valid barn if one still exists in placeableSystem
    if self.butcherBarnPlaceable == nil and g_currentMission and g_currentMission.placeableSystem and g_currentMission.placeableSystem.placeables then
        for _, p in pairs(g_currentMission.placeableSystem.placeables) do
            if p.configFileName and p.configFileName:match("theButcherBarn.xml") and (self.isButcherBarnValid == nil or self:isButcherBarnValid()) then
                self.butcherBarnPlaceable = p
                break
            end
        end
    end

    if self.butcherBarnPlaceable == nil then
        if self.spawnActionEventId ~= nil and g_inputBinding then
            pcall(function() g_inputBinding:removeActionEvent(self.spawnActionEventId) end)
            self.spawnActionEventId = nil
        end

        if self.butcherActionEventId ~= nil and g_inputBinding then
            pcall(function() g_inputBinding:removeActionEvent(self.butcherActionEventId) end)
            self.butcherActionEventId = nil
        end

        self.placeablesScanned = false
        self.visibilityOverrideInstalled = false
        self.trailersInTrigger = {}
        self.playerInSpawnTrigger = false
        self.playerInTrigger = false
        self.currentVehicle = nil
        self.lastBarnLightsState = nil
        self.lastBarnDoorsOpenAllowed = nil
    end

    if removedAny then
        print("[" .. self.modName .. "] Reset butcher barn state and removed custom triggers")
    end
end


----------------------------------------------------------------
-- VISIBILITY OVERRIDE (PER BARN + LEGACY WRAPPER)
----------------------------------------------------------------
function PRBFix:installVisibilityOverrideForBarn(barn)
    if barn == nil then return end

    barn.prRegisteredProductions = barn.prRegisteredProductions or {}
    local spec = barn.spec_extendedProductionPoint
    local pp = spec and spec.productionPoint
    if pp == nil then
        print("[PR Butcher Fix] productionPoint is nil")
        return
    end

    pp.hiddenOnUI = false
    pp.isOwned = true

    local ownerId = barn.ownerFarmId or pp.ownerFarmId or 1
    if ownerId == 0 then ownerId = 1 end
    pp.ownerFarmId = ownerId

    if barn.setOwnerFarmId then
        barn:setOwnerFarmId(ownerId)
        print(string.format("[PR Butcher Fix] Butcher barn real owner = farm %d", ownerId))
    end

    if ProductionPoint and ProductionPoint.OUTPUT_MODE_STORE then
        pp.outputMode = ProductionPoint.OUTPUT_MODE_STORE
        if pp.setOutputMode then
            pp:setOutputMode(ProductionPoint.OUTPUT_MODE_STORE)
        end
    end

    if pp.setOutputMode and not pp.prOutputModeHooked then
        pp.prOutputModeHooked = true
        local originalSetOutputMode = pp.setOutputMode
        pp.setOutputMode = function(self, mode)
            originalSetOutputMode(self, ProductionPoint.OUTPUT_MODE_STORE)
        end
    end

    pp.isOutputModeChangeAllowed = false
    if pp.setIsOutputModeChangeAllowed then
        pp:setIsOutputModeChangeAllowed(false)
    end

    local mgr = g_currentMission and g_currentMission.productionChainManager
    if mgr == nil then
        print("[PR Butcher Fix] productionChainManager is nil")
        return
    end

    if not barn.prRegisteredProductions[pp] then
        barn.prRegisteredProductions[pp] = true
        local alreadyInMgr = false
        if mgr.productionPoints then
            for _, existingPp in pairs(mgr.productionPoints) do
                if existingPp == pp then
                    alreadyInMgr = true
                    break
                end
            end
        end

        if not alreadyInMgr then
            local ok, err = pcall(function()
                mgr:addProductionPoint(pp)
            end)
            print(string.format("[PR Butcher Fix] addProductionPoint ok=%s err=%s", tostring(ok), tostring(err)))
        end

        if mgr.farmIds and mgr.addProductionPointToFarm then
            for farmId = 1, 4 do
                if farmId ~= ownerId and g_farmManager:getFarmById(farmId) then
                    if mgr.farmIds[farmId] == nil then
                        mgr.farmIds[farmId] = {}
                    end
                    local farmTable = mgr.farmIds[farmId]
                    local ok2, err2 = pcall(function()
                        mgr:addProductionPointToFarm(pp, farmTable)
                    end)
                    if ok2 then
                        print(string.format("[PR Butcher Fix] addProductionPointToFarm(farm %d) SUCCESS", farmId))
                    else
                        print(string.format("[PR Butcher Fix] addProductionPointToFarm(farm %d) FAILED: %s", farmId, tostring(err2)))
                    end
                end
            end
        end
    end

    self.visibilityOverrideInstalled = true
    self:installFarmBalanceOverlay()
    self:syncFarmMeat()
end


----------------------------------------------------------------
-- GET BARN IDENTITY
-- Returns stable barn key (uniqueId or position fallback),
-- formatted world position string, and ownerFarmId
----------------------------------------------------------------
function PRBFix:getBarnIdentity(placeable)
    if placeable == nil then
        return "unknown_barn", "0.00 0.00 0.00", 1
    end

    local posStr = "0.00 0.00 0.00"
    if placeable.rootNode and placeable.rootNode ~= 0 and getWorldTranslation then
        local ok, x, y, z = pcall(getWorldTranslation, placeable.rootNode)
        if ok and x ~= nil and y ~= nil and z ~= nil then
            posStr = string.format("%.2f %.2f %.2f", x, y, z)
        end
    end

    local rawUniqueId = placeable.uniqueId
    if (rawUniqueId == nil or rawUniqueId == "") and placeable.getUniqueId then
        local okUid, uid = pcall(function() return placeable:getUniqueId() end)
        if okUid and uid ~= nil and uid ~= "" then
            rawUniqueId = uid
        end
    end

    local barnKey
    if rawUniqueId ~= nil and tostring(rawUniqueId) ~= "" then
        barnKey = tostring(rawUniqueId)
    else
        barnKey = "pos_" .. posStr:gsub("%s+", "_")
    end

    local ownerId = placeable.ownerFarmId
    if ownerId == nil or ownerId == 0 then
        ownerId = 1
    end

    return barnKey, posStr, ownerId
end


----------------------------------------------------------------
-- GET BARN KEY
-- Returns a position-based key (e.g. pos_121.92_79.76_178.08)
-- that matches across server, client, triggers, overlay, and XML
----------------------------------------------------------------
function PRBFix:getBarnKey(placeable)
    if placeable == nil then
        return "pos_0.00_0.00_0.00"
    end
    local _, posStr = self:getBarnIdentity(placeable)
    return "pos_" .. tostring(posStr):gsub("%s+", "_")
end

----------------------------------------------------------------
-- GET BARN BY KEY
-- Returns the butcher barn placeable matching barnKey
----------------------------------------------------------------
function PRBFix:getBarnByKey(barnKey)
    if barnKey == nil then return self.butcherBarnPlaceable end
    if self.barnKeyToPlaceable and self.barnKeyToPlaceable[barnKey] then
        return self.barnKeyToPlaceable[barnKey]
    end
    local placeables = g_currentMission and g_currentMission.placeableSystem and g_currentMission.placeableSystem.placeables
    if placeables then
        for _, p in pairs(placeables) do
            if p.configFileName and p.configFileName:match("theButcherBarn.xml") then
                if self:getBarnKey(p) == barnKey then
                    return p
                end
            end
        end
    end
    return self.butcherBarnPlaceable
end