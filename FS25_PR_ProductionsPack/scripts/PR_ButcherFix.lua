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

function PR_ButcherSyncEvent:writeStream(streamId, connection)
    local farmCount = 0
    for _ in pairs(self.farmMeat or {}) do farmCount = farmCount + 1 end
    streamWriteUInt8(streamId, farmCount)

    for farmId, meats in pairs(self.farmMeat or {}) do
        streamWriteUInt8(streamId, farmId)
        local meatCount = 0
        for _ in pairs(meats) do meatCount = meatCount + 1 end
        streamWriteUInt8(streamId, meatCount)
        for fillType, amount in pairs(meats) do
            streamWriteString(streamId, fillType)
            streamWriteFloat32(streamId, amount)
        end
    end
end

function PR_ButcherSyncEvent:readStream(streamId, connection)
    local farmCount = streamReadUInt8(streamId)
    local farmMeat = {}

    for i = 1, farmCount do
        local farmId = streamReadUInt8(streamId)
        farmMeat[farmId] = {}
        local meatCount = streamReadUInt8(streamId)
        for j = 1, meatCount do
            local fillType = streamReadString(streamId)
            local amount = streamReadFloat32(streamId)
            farmMeat[farmId][fillType] = amount
        end
    end

    PRBFix.farmMeat = farmMeat
    print("[PR Butcher Fix] Received farmMeat sync (" .. farmCount .. " farms)")
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
    if not action or not g_inputBinding then return "U" end

    if g_inputBinding.getBinding then
        local binding = g_inputBinding:getBinding(action)
        if binding and binding.input then
            return binding.input:gsub("KEY_", ""):upper()
        end
    end

    local bindings = g_inputBinding.bindings
    if type(bindings) == "table" then
        for _, b in pairs(bindings) do
            if b and (b.action == action or b.actionName == action) and b.input then
                return b.input:gsub("KEY_", ""):upper()
            end
        end
    end

    return "U"
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

    self:loadMeatLedger()
    print(string.format("[%s] loadMap called (v%s)", self.modName, PRBFix.VERSION))
end

--------------------------------------------------------------------
-- INPUT CONTEXT
-- Manages the unload key binding while inside the animal trigger
--------------------------------------------------------------------
PRBFix.currentVehicle = nil
PRBFix.actionEventId = nil

function PRBFix:updateInputContext()
    if not PRBFix.playerInTrigger then return end

    local mission = g_currentMission
    if not mission or not mission.playerSystem or not mission.playerSystem.players then return end

    local player = mission.playerSystem.players[1]
    local vehicle = player and player.getCurrentVehicle and player:getCurrentVehicle() or nil

    if vehicle == self.currentVehicle then return end

    if self.actionEventId then
        g_inputBinding:removeActionEvent(self.actionEventId)
        self.actionEventId = nil
    end

    self.currentVehicle = vehicle
    if not vehicle then return end

    if InputAction and InputAction.RLB_UNLOAD_TO_BUTCHER then
        local _, eventId = g_inputBinding:registerActionEvent(
            InputAction.RLB_UNLOAD_TO_BUTCHER, self, self.onDeliverKeyPressed,
            false, true, false, true
        )
        if eventId then
            g_inputBinding:setActionEventText(eventId, g_i18n:getText("input_RLB_UNLOAD_TO_BUTCHER"))
            g_inputBinding:setActionEventTextVisibility(eventId, true)
            self.actionEventId = eventId
        end
    end
end

----------------------------------------------------------------
-- UPDATE LOOP
-- Runs every frame. Handles input, output lock, and placeable scan
----------------------------------------------------------------
function PRBFix:update(dt)
    self:updateInputContext()
    self:creditProductionOutput()
    self:processIncomingToOutgoing()

    -- Force output mode to Storing every 30 seconds
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

    -- Extra print text while in animal trigger
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

    -- Retry placeable scan until barn is found
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
-- Finds the barn, hooks triggers, sets owner, locks output mode
----------------------------------------------------------------
function PRBFix:scanButcherPlaceables()
    local found = false
    local placeables = g_currentMission.placeableSystem.placeables

    for _, p in pairs(placeables) do
        if p.configFileName and p.configFileName:match("theButcherBarn.xml") then
            found = true
            print("["..self.modName.."] Found butcher barn: "..p.configFileName)
            self.butcherBarnPlaceable = p

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
                    print("["..self.modName.."] onTriggerCallback attached new animalTrigger!")
                end
            end

            if p.setOwnerFarmId then
                p:setOwnerFarmId(1)
                print("["..self.modName.."] Butcher barn owner set to farm 1")
            end

            if p.i3dMappings and p.i3dMappings["palletTrigger"] then
                local n = p.i3dMappings["palletTrigger"].nodeId
                if n and n ~= 0 then
                    print("["..self.modName.."] Replacing original palletTrigger "..n)
                    removeTrigger(n)
                    addTrigger(n, "onPalletTriggerCallback", self)
                    print("["..self.modName.."] onPalletTriggerCallback attached")
                end
            end

            if p.i3dMappings and p.i3dMappings["loadingZoneTrigger"] then
                local n = p.i3dMappings["loadingZoneTrigger"].nodeId
                if n and n ~= 0 then
                    addTrigger(n, "onSpawnTriggerCallback", self)
                    print("["..self.modName.."] Loading Zone trigger attached")
                end
            end
        end
    end

    if found then
        self.placeablesScanned = true
        print("["..self.modName.."] Placeable scan successful. Barn cached.")
        self:installVisibilityOverride()

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
    else
        self.placeablesScanned = false
    end
end

----------------------------------------------------------------
-- PALLET TRIGGER CALLBACK
-- Credits empty pallets to the delivering farm and adds them to storage
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

    obj.prButcherCredited = true

    PRBFix.farmMeat[farmId] = PRBFix.farmMeat[farmId] or {}
    PRBFix.farmMeat[farmId]["EMPTYPALLET"] = (PRBFix.farmMeat[farmId]["EMPTYPALLET"] or 0) + amount

    print(string.format("[%s] Pallet trigger credited %.2f L EMPTYPALLET to farm %d", self.modName, amount, farmId))

    if g_server ~= nil then
        PRBFix:syncFarmMeat()
    end

    local barn = self.butcherBarnPlaceable
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
-- Registers the spawn action key when player enters the front zone
----------------------------------------------------------------
function PRBFix:onSpawnTriggerCallback(triggerId, otherId, onEnter, onLeave)
    local isPlayer = false

    if g_localPlayer and g_localPlayer.rootNode == otherId then
        isPlayer = true
    end

    if not isPlayer and g_currentMission and g_currentMission.playerSystem then
        for _, player in pairs(g_currentMission.playerSystem.players) do
            if player and player.rootNode == otherId then
                isPlayer = true
                break
            end
        end
    end

    if not isPlayer then return end

    self.playerInSpawnTrigger = onEnter

    local farmId = g_currentMission and g_currentMission:getFarmId() or 1
    local farmName = "Unknown"
    if g_farmManager and g_farmManager.farms then
        for _, farm in pairs(g_farmManager.farms) do
            if farm and (farm.farmId == farmId or farm.id == farmId) and farm.name and farm.name ~= "" then
                farmName = farm.name
                break
            end
        end
    end

    if onEnter then
        print(string.format("[%s] Player entered loading zone | Farm %d (%s)", self.modName, farmId, farmName))

        if self.spawnActionEventId == nil then
            local _, eventId = g_inputBinding:registerActionEvent(
                InputAction.RLB_UNLOAD_TO_BUTCHER, self, PRBFix.onSpawnPalletAction,
                false, true, false, true
            )
            if eventId then
                g_inputBinding:setActionEventText(eventId, "Spawn Pallet")
                g_inputBinding:setActionEventTextVisibility(eventId, true)
                g_inputBinding:setActionEventActive(eventId, true)
                self.spawnActionEventId = eventId
                print("["..self.modName.."] Spawn action registered")
            end
        end
    else
        print(string.format("[%s] Player left loading zone | Farm %d (%s)", self.modName, farmId, farmName))

        if self.spawnActionEventId then
            g_inputBinding:removeActionEvent(self.spawnActionEventId)
            self.spawnActionEventId = nil
            print("["..self.modName.."] Spawn action removed")
        end
    end
end

----------------------------------------------------------------
-- SPAWN ACTION
-- Opens the spawn dialog with only products that are ready for pickup
----------------------------------------------------------------
function PRBFix:onSpawnPalletAction()
    if not self.playerInSpawnTrigger then return end

    local farmId = g_currentMission and g_currentMission:getFarmId() or 1
    local pallets = (PRBFix.farmMeatPallets and PRBFix.farmMeatPallets[farmId]) or {}

    local now = 0
    if g_currentMission and g_currentMission.environment then
        now = g_currentMission.environment.currentMonotonicDay * 86400 + g_currentMission.environment.dayTime / 1000
    end

    local readyProducts = {}
    for fillType, entry in pairs(pallets) do
        if type(entry) == "table" and entry.amount and entry.amount > 0.01 and entry.readyAt and now >= entry.readyAt then
            table.insert(readyProducts, {
                fillType = fillType,
                amount = entry.amount
            })
        end
    end

    table.sort(readyProducts, function(a, b) return a.fillType < b.fillType end)

    -- Always open the dialog, even when the list is empty
    if PRBSpawnDialog and PRBSpawnDialog.show then
        PRBSpawnDialog.show(readyProducts, farmId)
    else
        print("["..self.modName.."] Spawn dialog not available")
    end
end

----------------------------------------------------------------
-- DO SPAWN PALLET
-- Server-only. Caps at 10, respects empty pallet ledger, spawns whatever amount is ready
----------------------------------------------------------------
function PRBFix:doSpawnPallet(fillTypeName, farmId)
    if g_server == nil then
        print("["..self.modName.."] Spawn skipped (not server)")
        return
    end

    local barn = self.butcherBarnPlaceable
    if barn == nil or barn.i3dMappings == nil then
        print("["..self.modName.."] No barn or mappings")
        return
    end

    local startNode = barn.i3dMappings["spawnSpace1start"] and barn.i3dMappings["spawnSpace1start"].nodeId
    local endNode   = barn.i3dMappings["spawnSpace1end"]   and barn.i3dMappings["spawnSpace1end"].nodeId

    if startNode == nil or startNode == 0 then
        print("["..self.modName.."] No spawn start node")
        return
    end

    local pallets = PRBFix.farmMeatPallets and PRBFix.farmMeatPallets[farmId]
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

    -- Check empty pallet balance
    local emptyPallets = (PRBFix.farmMeat and PRBFix.farmMeat[farmId] and PRBFix.farmMeat[farmId]["EMPTYPALLET"]) or 0
    if emptyPallets < 0.01 then
        print(string.format("[%s] Farm %d is out of empty pallets", self.modName, farmId))
        return
    end

    -- Cap this spawn to available empty pallets
    if spawnAmount > emptyPallets then
        spawnAmount = emptyPallets
        print(string.format("[%s] Limited %s spawn to %.1f L (out of empty pallets)", self.modName, fillTypeName, spawnAmount))
    end

    local x, y, z = getWorldTranslation(startNode)
    local rx, ry, rz = getWorldRotation(startNode)

    -- Tighter side-by-side spacing (fixed offset along local X)
    if PRBFix._spawnBatch and #PRBFix._spawnBatch > 1 then
        local index = PRBFix._spawnIndex or 0
        PRBFix._spawnIndex = index + 1

        local gap = 1.6
        -- Simple offset using the node's rotation (safer than getWorldDirection)
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

            if PRBFix.farmMeat and PRBFix.farmMeat[farmId] then
                local empty = PRBFix.farmMeat[farmId]["EMPTYPALLET"] or 0
                local emptyCost = 1000
                PRBFix.farmMeat[farmId]["EMPTYPALLET"] = math.max(0, empty - emptyCost)
                print(string.format("[%s] Deducted %d L EMPTYPALLET from farm %d ledger", self.modName, emptyCost, farmId))
            end

            entry.amount = entry.amount - spawnAmount
            if entry.amount < 0.01 then
                PRBFix.farmMeatPallets[farmId][fillTypeName] = nil
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
-- CREDIT PRODUCTION OUTPUT
-- Credits finished products that appear in storage to the current farm
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
-- Converts raw meat to finished products after the wait time
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
-- Detects livestock trailers and registers the unload action
----------------------------------------------------------------
function PRBFix:onTriggerCallback(triggerId, otherId, onEnter, onLeave)
    local obj = g_currentMission.nodeToObject[otherId]
    if obj and obj.typeName == "livestockTrailer" then
        if onEnter then
            local num = obj:getNumOfAnimals()
            local t = obj:getCurrentAnimalType()
            local typeName = (t and t.name) or "COW"

            print(string.format("[%s] Animal trailer entered trigger! XML=%s | Total=%d | Type=%s",
                self.modName, tostring(obj.configFileName), num, typeName))

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

            local cap = self:checkBarnCapacity(typeName)
            if cap then
                print(string.format("[%s] Barn ready for %d (%s)", self.modName, cap.avail, cap.fillType))
            end

            self.trailersInTrigger[obj] = {type = typeName, num = num}

            if self.butcherActionEventId == nil then
                local _, id = g_inputBinding:registerActionEvent(
                    InputAction.RLB_UNLOAD_TO_BUTCHER, self, self.onDeliverKeyPressed,
                    false, true, false, true
                )
                self.butcherActionEventId = id
                if id then
                    local keyName = self:getUnloadKeyName()
                    g_inputBinding:setActionEventText(id, "Unload Animals To Butcher (Press " .. keyName .. ")")
                    g_inputBinding:setActionEventTextVisibility(id, true)
                    print("["..self.modName.."] Registered R for butcher trigger")
                end
            end
        elseif onLeave then
            print("["..self.modName.."] Trailer left trigger")
            self.trailersInTrigger[obj] = nil
            if next(self.trailersInTrigger) == nil then
                if self.butcherActionEventId ~= nil then
                    g_inputBinding:removeActionEvent(self.butcherActionEventId)
                    print("["..self.modName.."] Unregistered R for butcher trigger")
                    self.butcherActionEventId = nil
                end
            end
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
-- Returns available space for a given animal type
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
-- Filters clusters by age rules and returns count + valid indices
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
-- Opens the animal delivery dialog with fresh data
----------------------------------------------------------------
function PRBFix:onDeliverKeyPressed(actionName, value, state, isAnalog)
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
-- Called by the dialog OK button. Sends event or runs locally
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
-- Core delivery logic. Credits meat, removes animals, updates storage
----------------------------------------------------------------
function PRBFix:deliverAnimals(trailer, data, amount, farmId)
    if trailer == nil or data == nil then return end

    local typeName = data.type or "UNKNOWN"
    local validClusters = data.validClusters or {}

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    if #validClusters == 0 then return end
    if amount > #validClusters then amount = #validClusters end

    local cap = self:checkBarnCapacity(typeName)
    if cap == nil then return end

    local barn = self.butcherBarnPlaceable
    if barn == nil then return end

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

    local weights = {}
    local prefix = {0.0}

    for i, idx in ipairs(validClusters) do
        local cluster = cs.animals[idx]
        local w = 0.0
        if cluster ~= nil then
            local rawW = tonumber(cluster.weight or 0) or 0.0
            local q = 1.0
            if cluster.genetics ~= nil and cluster.genetics.quality ~= nil then
                q = tonumber(cluster.genetics.quality) or 1.0
            end
            local breedMul = PRBFix:getBreedMultiplier(typeName, cluster)
            w = rawW * q * breedMul
        end
        weights[i] = w
        prefix[i + 1] = prefix[i] + w
    end

    local function totalWeightFor(n)
        if n <= 0 then return 0.0 end
        if n > #weights then n = #weights end
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

    local totalWeight = totalWeightFor(used)
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
            PRBFix.farmMeat[farmId] = PRBFix.farmMeat[farmId] or {}

            local WAIT_SECONDS = 3600
            local readyAt = g_currentMission.environment.currentMonotonicDay * 86400 + g_currentMission.environment.dayTime / 1000 + WAIT_SECONDS

            PRBFix.farmMeatPallets = PRBFix.farmMeatPallets or {}
            PRBFix.farmMeatPallets[farmId] = PRBFix.farmMeatPallets[farmId] or {}

            local function addFinished(fillType, amount)
                if amount > 0.01 then
                    local entry = PRBFix.farmMeatPallets[farmId][fillType] or {amount = 0, readyAt = readyAt}
                    entry.amount = entry.amount + amount
                    entry.readyAt = readyAt
                    PRBFix.farmMeatPallets[farmId][fillType] = entry
                    print(string.format("[%s] Credited %.1f L %s (ready in 1h) to farm %d", self.modName, amount, fillType, farmId))
                end
            end

            local meatName = self.ANIMAL_TO_MEAT_FILLTYPE[typeName] or typeName
            if meatName == "POULTRY" then
                addFinished("CHICKENFILLET", liters * 35)
            elseif meatName == "COWMEAT" then
                addFinished("GROUNDBEEF", liters * 220)
                addFinished("STEAK", liters * 220)
                addFinished("SAUSAGE", liters * 105)
                addFinished("PEPPERONI", liters * 105)
            elseif meatName == "PIGMEAT" then
                addFinished("HAM", liters * 105)
                addFinished("PORK", liters * 75)
                addFinished("BACON", liters * 45)
                addFinished("SAUSAGE", liters * 30)
                addFinished("PEPPERONI", liters * 30)
            elseif meatName == "SHEEPMEAT" then
                addFinished("MUTTON", liters * 150)
                addFinished("CHEVON", liters * 150)
            end

            PRBFix.pendingConversions = PRBFix.pendingConversions or {}
            local CONVERT_SECONDS = 300
            local convertAt = g_currentMission.environment.currentMonotonicDay * 86400 + g_currentMission.environment.dayTime / 1000 + CONVERT_SECONDS

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
                convertAt = convertAt
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

    PR_DeliverAnimalsEvent.send(self.barn, trailer, used, true, newFill, typeName)

    print(string.format("[%s] ➕ Added %.2f L %s from %d animals", self.modName, liters, typeName, used))

    local clustersToRemove = {}
    for i = 1, used do
        local idx = validClusters[i]
        if idx ~= nil and cs.animals[idx] ~= nil then
            table.insert(clustersToRemove, cs.animals[idx])
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
-- Mirrors server animal removal on the client
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
-- SAVE / LOAD LEDGER
----------------------------------------------------------------
function PRBFix:saveMeatLedger()
    if g_server == nil then return end
    if g_currentMission == nil or g_currentMission.missionInfo == nil then return end

    local saveDir = g_currentMission.missionInfo.savegameDirectory
    if saveDir == nil then return end

    local xmlPath = saveDir .. "/PR_ButcherBarn.xml"
    local xmlFile = XMLFile.create("PR_ButcherBarn", xmlPath, "butcherBarn")
    if xmlFile == nil then return end

    local farmIndex = 0
    for farmId, meats in pairs(PRBFix.farmMeat or {}) do
        local farmKey = string.format("butcherBarn.farm(%d)", farmIndex)
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

        local empty = meats["EMPTYPALLET"] or 0
        if empty > 0.01 then
            xmlFile:setFloat(farmKey .. ".emptyPallet", empty)
        end

        local pallets = (PRBFix.farmMeatPallets and PRBFix.farmMeatPallets[farmId]) or {}
        local procIndex = 0
        local availIndex = 0
        local now = 0
        if g_currentMission and g_currentMission.environment then
            now = g_currentMission.environment.currentMonotonicDay * 86400 + g_currentMission.environment.dayTime / 1000
        end

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
    end

    xmlFile:save()
    xmlFile:delete()
    print(string.format("[%s] Saved butcher barn ledger (%d farms) to %s", self.modName, farmIndex, xmlPath))
end

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

    local farmIndex = 0
    while true do
        local farmKey = string.format("butcherBarn.farm(%d)", farmIndex)
        if not xmlFile:hasProperty(farmKey) then break end

        local farmId = xmlFile:getInt(farmKey .. "#id")
        if farmId ~= nil then
            PRBFix.farmMeat[farmId] = {}
            PRBFix.farmMeatPallets[farmId] = {}

            local empty = xmlFile:getFloat(farmKey .. ".emptyPallet") or 0
            if empty > 0.01 then
                PRBFix.farmMeat[farmId]["EMPTYPALLET"] = empty
            end

            local procIndex = 0
            while true do
                local key = string.format("%s.processing(%d)", farmKey, procIndex)
                if not xmlFile:hasProperty(key) then break end
                local fillType = xmlFile:getString(key .. "#type")
                local amount = xmlFile:getFloat(key .. "#amount") or 0
                local readyAt = xmlFile:getFloat(key .. "#readyAt") or 0
                if fillType ~= nil then
                    PRBFix.farmMeatPallets[farmId][fillType] = {amount = amount, readyAt = readyAt}
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
                    local existing = PRBFix.farmMeatPallets[farmId][fillType]
                    if existing then
                        existing.amount = existing.amount + amount
                        existing.readyAt = math.min(existing.readyAt or readyAt, readyAt)
                    else
                        PRBFix.farmMeatPallets[farmId][fillType] = {amount = amount, readyAt = readyAt}
                    end
                end
                availIndex = availIndex + 1
            end
        end
        farmIndex = farmIndex + 1
    end

    xmlFile:delete()
    self:syncFarmMeat()
    print(string.format("[%s] Loaded butcher barn ledger (%d farms)", self.modName, farmIndex))
end

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, function()
    if PRBFix ~= nil and PRBFix.saveMeatLedger ~= nil then
        PRBFix:saveMeatLedger()
    end
end)

----------------------------------------------------------------
-- VISIBILITY OVERRIDE
-- Makes the barn appear for all farms and locks output mode
----------------------------------------------------------------
function PRBFix:installVisibilityOverride()
    print("[PR Butcher Fix] installVisibilityOverride called")
    if self.visibilityOverrideInstalled then return end
    if self.butcherBarnPlaceable == nil then return end

    local barn = self.butcherBarnPlaceable
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
        print("[PR Butcher Fix] Output mode locked to Storing")
    end

    if pp.setOutputMode then
        local originalSetOutputMode = pp.setOutputMode
        pp.setOutputMode = function(self, mode)
            originalSetOutputMode(self, ProductionPoint.OUTPUT_MODE_STORE)
        end
    end

    pp.isOutputModeChangeAllowed = false
    if pp.setIsOutputModeChangeAllowed then
        pp:setIsOutputModeChangeAllowed(false)
    end

    local mgr = g_currentMission.productionChainManager
    if mgr == nil then
        print("[PR Butcher Fix] productionChainManager is nil")
        return
    end

    local ok, err = pcall(function()
        mgr:addProductionPoint(pp)
    end)
    print(string.format("[PR Butcher Fix] addProductionPoint ok=%s err=%s", tostring(ok), tostring(err)))

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
            else
                if farmId == ownerId then
                    print(string.format("[PR Butcher Fix] Skipping owner farm %d (already owns it)", ownerId))
                end
            end
        end
    end

    self.visibilityOverrideInstalled = true
    self:installFarmBalanceOverlay()
    self:syncFarmMeat()
    print("[PR Butcher Fix] Done")
end

----------------------------------------------------------------
-- FARM BALANCE OVERLAY
-- Draws the current farm's inventory on the production menu
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

function PRBFix:drawFarmBalanceOverlay(frame)
    if frame == nil or frame.getSelectedProduction == nil then return end

    local production, productionPoint = frame:getSelectedProduction()
    if productionPoint == nil then return end

    local placeable = productionPoint.owningPlaceable
    if placeable == nil or placeable.configFileName == nil then return end
    if not placeable.configFileName:find("theButcherBarn") then return end

    local currentFarmId = g_currentMission:getFarmId()
    if currentFarmId == nil or currentFarmId <= 0 then return end

    local farm = g_farmManager:getFarmById(currentFarmId)
    local farmName = (farm and farm.name) or ("Farm " .. currentFarmId)

    local lines = {}
    table.insert(lines, {text = "", isHeader = false})
    table.insert(lines, {text = "FARM: " .. farmName, isHeader = false})
    table.insert(lines, {text = "--------------------", isHeader = false})
    table.insert(lines, {text = "Processing", isHeader = true})

    local pallets = (PRBFix.farmMeatPallets and PRBFix.farmMeatPallets[currentFarmId]) or {}
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
    local meats = PRBFix.farmMeat[currentFarmId] or {}
    local emptyPallets = meats["EMPTYPALLET"] or 0
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
    local y = 0.72
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