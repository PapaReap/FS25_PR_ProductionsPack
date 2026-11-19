-- PR_ButcherFix.lua

PRBFix = {}

-- Abort if RealisticLivestock is NOT loaded
PRBFix.disabled = true
-- local rlMod = g_modManager:getModByName("FS25_EnhancedLivestock")
local rlMod = g_modManager:getModByName("FS25_RealisticLivestockRM")
if rlMod == nil then
    print("[PR Butcher Fix] RealisticLivestock not detected — disabling butcher fix and using vanilla behavior")
    PRBFix.disabled = true
end

--if PRBFix.disabled then return end


PRBFix.modName = "PR Butcher Fix"
PRBFix.VERSION = "1.2.0 multiplayer testing"
PRBFix.modNameDialog = "PR Butcher Dialog"
PRBFix.VersionDialog = "1.2.0 multiplayer testing"

PRBFix.placeablesScanned = false
PRBFix.trailersInTrigger = {}
PRBFix.butcherBarnPlaceable = nil
PRBFix.playerInTrigger = false

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

-- Average "baseline" weights for 1.0 liter equivalence
PRBFix.AVGWEIGHT = {
    COW     = {600},
    PIG     = {155},
    SHEEP   = {40},
    CHICKEN = {3},
}

-- Per-breed multipliers (tune to taste)
PRBFix.BREED_MULTIPLIER = {
    COW = {
        -- MILK COWS
        COW_HOLSTEIN      = 1.00,  -- (baseline) (dairy/dual-purpose, lower yield)
        BULL_HOLSTEIN     = 1.05,

        COW_SWISS_BROWN   = 1.08,  -- moderate yield (dual-use / dairy-beef mix)
        BULL_SWISS_BROWN  = 1.13,

        COW_WATERBUFFALO  = 1.10,  -- assume slightly better than dairy
        BULL_WATERBUFFALO = 1.15,

        -- BEEF COWS
        COW_ANGUS         = 1.15,  -- moderate beef breed, decent yield
        BULL_ANGUS        = 1.20,

        COW_HEREFORD      = 1.12,  -- similar to Angus-ish yield
        BULL_HEREFORD     = 1.17,

        COW_LIMOUSIN      = 1.25,  -- highly efficient meat yield
        BULL_LIMOUSIN     = 1.30,
    },
    -- Pigs: use generic ranges — needs real data per breed
        PIG = {
        PIG_LANDRACE      = 1.00,  -- (baseline) large, lean, high-growth but lower marbling
        BOAR_LANDRACE     = 1.05,
        PIG_BLACK_PIED    = 1.08,  -- slightly fatter, better flavor, moderate yield
        BOAR_BLACK_PIED   = 1.13,
        PIG_BERKSHIRE     = 1.15,  -- world-famous marbling, premium pork, highest carcass value
        BOAR_BERKSHIRE    = 1.20,
    },
    -- Sheep: use generic ranges — needs real data per breed
    SHEEP = {
        SHEEP_LANDRACE        = 1.00,  -- (baseline) standard lamb
        RAM_LANDRACE          = 1.05,
        SHEEP_STEINSCHAF      = 1.05,  -- heritage breed, decent muscling
        RAM_STEINSCHAF        = 1.10,
        SHEEP_SWISS_MOUNTAIN  = 1.10,  -- larger framed, better meat yield than most wool breeds
        RAM_SWISS_MOUNTAIN    = 1.15,
        SHEEP_BLACK_WELSH     = 1.15,  -- prized for dark, flavorful, high-value lamb
        RAM_BLACK_WELSH       = 1.20,
        GOAT                  = 0.95,  -- leaner, less carcass yield
        RAM_GOAT              = 1.00,
    },
    -- Chicken: use generic ranges — needs real data per breed
    CHICKEN = {
        CHICKEN         = 1.00,  -- (baseline)
        CHICKEN_ROOSTER = 1.03,  -- slightly larger frames
    }
}

function PRBFix:getBreedMultiplier(animalType, cluster)
    local default = 1.0
    if cluster == nil then
        return default
    end

    -- try to get a name from the cluster (RealisticLivestock specific)
    local subName = cluster.subTypeName or cluster.subType or nil
    if not subName then
        return default
    end

    local byType = self.BREED_MULTIPLIER[animalType]
    if not byType then
        return default
    end

    return byType[subName] or default
end


function PRBFix:getUnloadKeyName()
    local action = InputAction and InputAction.RLB_UNLOAD_TO_BUTCHER
    if not action or not g_inputBinding then
        return "U"
    end

    -- Try the direct binding lookup first
    if g_inputBinding.getBinding then
        local binding = g_inputBinding:getBinding(action)
        if binding and binding.input then
            -- strip the KEY_ prefix and uppercase
            return binding.input:gsub("KEY_", ""):upper()
        end
    end

    -- Fallback: scan the bindings table
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
-- Register console command
----------------------------------------------------------------
addConsoleCommand("deliver", "Manual delivery", "consoleDeliver", PRBFix)

function PRBFix:consoleDeliver(amount)
    print("["..self.modName.."] Console deliver called amount="..tostring(amount))

    for trailer, data in pairs(self.trailersInTrigger) do
        local cap = self:checkBarnCapacity(data.type)
        if not cap then return end

        local max = math.min(cap.avail, data.num)

        local n = tonumber(amount)
        if not n then
            print("["..self.modName.."] ⚠ No amount specified, defaulting to "..max)
            n = max
        end

        n = math.min(n, max)
        self:deliverAnimals(trailer, data, n)
        return
    end
end

----------------------------------------------------------------
-- loadMap: Register action key
----------------------------------------------------------------
function PRBFix:loadMap()
    self.butcherActionEventId = nil

    local modDir = nil

    -- Try environment modDirectory first (as in FS25 scripts)
    local env = getfenv(2)
    if env and env.modDirectory then
        modDir = env.modDirectory
        print("["..self.modName.."] ✅ modDir = env.modDirectory")
    end

    -- Fallback to current mod dir
    if not modDir and g_currentModDirectory then
        modDir = g_currentModDirectory
        print("["..self.modName.."] ✅ modDir = g_currentModDirectory")
    end

    -- Fallback to lookup by name
    if not modDir and g_modNameToDirectory then
        modDir = g_modNameToDirectory["FS25_PR_ProductionsPack"]
        print("["..self.modName.."] ✅ modDir = g_modNameToDirectory")
    end

    if not modDir then
        print("[PR Butcher Fix] ❌ modDir is nil — cannot load dialog")
        return
    end

    -- Export it so PR_ButcherDialog.lua can use it
    PRBFix.modDirectory = modDir

    -- Load profiles
    local profilesPath = modDir .. "gui/guiProfiles.xml"
    print("[PR Butcher Fix] Loading guiProfiles: " .. profilesPath)
    g_gui:loadProfiles(profilesPath)

    -- Load dialog script
    local dlgPath = modDir .. "scripts/PR_ButcherDialog.lua"
    print("[PR Butcher Fix] Loading PR_ButcherDialog.lua from: " .. dlgPath)

    local ok, err = pcall(function()
        source(dlgPath)
    end)

    if not ok then
        print("[PR Butcher Fix] ❌ Error loading dialog: " .. tostring(err))
    else
        print("[PR Butcher Fix] ✓ Dialog script loaded OK")
    end

    print(string.format("[%s] loadMap called (v%s)", self.modName, PRBFix.VERSION))
end

--------------------------------------------------------------------
-- Input hint / action event manager
--------------------------------------------------------------------
PRBFix.currentVehicle = nil
PRBFix.actionEventId = nil

function PRBFix:updateInputContext()
    -- Do NOT override R unless inside the butcher trigger
    if not PRBFix.playerInTrigger then
        return
    end

    local mission = g_currentMission
    if not mission or not mission.playerSystem or not mission.playerSystem.players then
        return
    end

    local player = mission.playerSystem.players[1]
    local vehicle = player and player.getCurrentVehicle and player:getCurrentVehicle() or nil

    -- Only update if the controlled vehicle changed
    if vehicle == self.currentVehicle then
        return
    end

    -- Clear old event if necessary
    if self.actionEventId then
        g_inputBinding:removeActionEvent(self.actionEventId)
        self.actionEventId = nil
    end

    self.currentVehicle = vehicle
    if not vehicle then return end

    -- Register R key event (VEHICLE context)
    if InputAction and InputAction.RLB_UNLOAD_TO_BUTCHER then
        local _, eventId = g_inputBinding:registerActionEvent(
            InputAction.RLB_UNLOAD_TO_BUTCHER,
            self,
            self.onDeliverKeyPressed,
            false,  -- triggerUp
            true,   -- triggerDown
            false,  -- triggerAlways
            true    -- startActive
        )

        if eventId then
            g_inputBinding:setActionEventText(eventId, g_i18n:getText("input_RLB_UNLOAD_TO_BUTCHER"))
            g_inputBinding:setActionEventTextVisibility(eventId, true)
            self.actionEventId = eventId
            print(string.format("[%s] ✅ Bound R to unload action", self.modName))
        else
            print(string.format("[%s] ⚠️ Failed to bind unload key", self.modName))
        end
    end
end

----------------------------------------------------------------
-- Update loop (MERGED with retry scan, nothing removed)
----------------------------------------------------------------
function PRBFix:update(dt)
    -- Always keep input context refreshed
    self:updateInputContext()

    --------------------------------------------------------
    -- F1 context hint (your original logic 100% untouched)
    --------------------------------------------------------
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
                        -- mission:addExtraPrintText("Unload Animals To Butcher (Press R)")
						local keyName = self:getUnloadKeyName()
						mission:addExtraPrintText("Unload Animals To Butcher (Press " .. keyName .. ")")
                    end
                end
            end
        end
    end

    --------------------------------------------------------
    -- Placeable scan (REPLACED with throttled retry system)
    -- Still only runs when placeablesScanned == false
    --------------------------------------------------------
    if not self.placeablesScanned and g_currentMission and g_currentMission.placeableSystem then
        local now = g_time or 0

        -- first time ever?
        if self.nextPlaceableScanTime == nil then
            self.nextPlaceableScanTime = now
        end

        -- retry every 2000 ms (2 seconds)
        if now >= self.nextPlaceableScanTime then
            self.nextPlaceableScanTime = now + 4000
            self:scanButcherPlaceables()
        end
    end
end

----------------------------------------------------------------
-- Scan butcher placeables (MERGED: your logic + retry behavior)
----------------------------------------------------------------
function PRBFix:scanButcherPlaceables()
    local found = false
    local placeables = g_currentMission.placeableSystem.placeables

    for _, p in pairs(placeables) do
        if p.configFileName and p.configFileName:match("theButcherBarn.xml") then
            found = true

            print("["..self.modName.."] Found butcher barn: "..p.configFileName)
            self.butcherBarnPlaceable = p

            -- Animal trigger
            if p.i3dMappings and p.i3dMappings["animalTrigger"] then
                local n = p.i3dMappings["animalTrigger"].nodeId
                if n and n ~= 0 then
                    print("["..self.modName.."] Disabling original animalTrigger "..n)
                    removeTrigger(n)
                    addTrigger(n, "onTriggerCallback", self)
                    print("["..self.modName.."] onTriggerCallback attached new animalTrigger!")
                end
            end

            -- Spawn / loading zone trigger
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
    else
        self.placeablesScanned = false
    end
end

----------------------------------------------------------------
-- SPAWN / LOADING ZONE TRIGGER
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

    if isPlayer then
        self.playerInSpawnTrigger = onEnter

        local farmId = 1
        local farmName = "Unknown"
        if g_currentMission and g_currentMission.getFarmId then
            farmId = g_currentMission:getFarmId()
        end

        -- Try to get farm name
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
            print(string.format("[%s] Player entered loading zone | Farm %d (%s)", 
                self.modName, farmId, farmName))
            -- TODO: register spawn action event
        else
            print(string.format("[%s] Player left loading zone | Farm %d (%s)", 
                self.modName, farmId, farmName))
            -- TODO: unregister spawn action event
        end
    end
end

----------------------------------------------------------------
-- TRIGGER CALLBACK
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

            ----------------------------------------------------------------
            -- 🟦 DIAGNOSTIC: LIST ALL CLUSTERS WITH AGE + WEIGHT
            ----------------------------------------------------------------
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

                    print(string.format(
                        "[%s] Cluster %d | num=%d | age=%d months | weight=%.1f kg | gender=%s | subType=%d",
                        self.modName, idx, numA, age, wt, gen, sub
                    ))
                end

                print(string.format("[%s] ---- END CLUSTER REPORT ----", self.modName))
            else
                print(string.format("[%s] ⚠ No clusterSystem found on trailer!", self.modName))
            end
            ----------------------------------------------------------------

            local cap = self:checkBarnCapacity(typeName)
            if cap then
                print(string.format("[%s] Barn ready for %d (%s)", self.modName, cap.avail, cap.fillType))
            end

            self.trailersInTrigger[obj] = {type = typeName, num = num}

            -- 🟩 NEW: Register R only when entering the butcher trigger
            if self.butcherActionEventId == nil then
                local _, id = g_inputBinding:registerActionEvent(
                    InputAction.RLB_UNLOAD_TO_BUTCHER,
                    self,
                    self.onDeliverKeyPressed,
                    false, true, false, true
                )
                self.butcherActionEventId = id

                if id then
                    -- g_inputBinding:setActionEventText(id, "Unload Animals To Butcher (Press R)")
					local keyName = self:getUnloadKeyName()
					g_inputBinding:setActionEventText(id, "Unload Animals To Butcher (Press " .. keyName .. ")")
                    g_inputBinding:setActionEventTextVisibility(id, true)
                    print("["..self.modName.."] Registered R for butcher trigger")
                end
            end

        elseif onLeave then
            print("["..self.modName.."] Trailer left trigger")
            self.trailersInTrigger[obj] = nil

            -- 🟩 NEW: fully remove R binding when last trailer leaves
            if next(self.trailersInTrigger) == nil then
                if self.butcherActionEventId ~= nil then
                    g_inputBinding:removeActionEvent(self.butcherActionEventId)
                    print("["..self.modName.."] Unregistered R for butcher trigger")
                    self.butcherActionEventId = nil
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- 🟦 Player or vehicle enters/leaves butcher trigger
    ----------------------------------------------------------------
    if g_currentMission.player and g_currentMission.player.rootNode == otherId then
        PRBFix.playerInTrigger = onEnter
    end

    local controlled = g_currentMission.controlledVehicle
    if controlled and controlled.rootNode == otherId then
        PRBFix.playerInTrigger = onEnter
    end
end

----------------------------------------------------------------
-- Barn capacity check (unchanged logic; min/max age currently unused)
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

    -- (minAge / maxAge lookup left in for future use; not used directly now)
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
-- Count age-valid animals and return valid clusters (with logs)
----------------------------------------------------------------
function PRBFix:countValidAnimals(trailer, animalType)
    local rule = PRBFix.AGE_RULES[animalType]
    if not rule then
        print(string.format("[%s] ❌ No AGE_RULES entry for %s", self.modName, tostring(animalType)))
        return 0, {}
    end

    local minAge = rule.min
    local maxAge = rule.max

    print(string.format("[%s] 🔍 Age filter for %s = %d–%d months",
        self.modName, animalType, minAge, maxAge))

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

        print(string.format("[%s] Cluster %d | age=%d | num=%d | VALID=%s",
            self.modName, idx, age, num, tostring(ok)))

        if ok then
            count = count + num
            table.insert(valid, idx)
        end
    end

    print(string.format("[%s] ---- AGE FILTER CHECK END ----", self.modName))
    print(string.format("[%s] RESULT: %d valid animals | valid clusters = %s",
        self.modName, count, table.concat(valid, ", ")))

    return count, valid
end

----------------------------------------------------------------
-- Press R: Opens butcher dialog (always fresh, no cached data)
----------------------------------------------------------------
function PRBFix:onDeliverKeyPressed(actionName, value, state, isAnalog)
    if not next(self.trailersInTrigger) then
        return
    end

    print(string.format("[%s] 🔔 onDeliverKeyPressed fired", self.modName))

    --------------------------------------------------------------------
    -- ALWAYS REFRESH TRAILER DATA (NO MORE CACHED VALUES!)
    --------------------------------------------------------------------
    for trailer, data in pairs(self.trailersInTrigger) do

        ------------------------------------------------------------
        -- Fresh count of animals in trailer
        ------------------------------------------------------------
        local numNow = trailer:getNumOfAnimals() or 0
        data.num = numNow   -- update it
        print(string.format("[%s] 🔄 Fresh trailer count = %d animals",
            self.modName, numNow))

        ------------------------------------------------------------
        -- Fresh capacity info
        ------------------------------------------------------------
        local cap = self:checkBarnCapacity(data.type)
        if not cap then
            print("["..self.modName.."] ⚠ No production storage found")
            return
        end

        ------------------------------------------------------------
        -- Fresh cluster analysis
        ------------------------------------------------------------
        local validCount, validClusters = self:countValidAnimals(trailer, data.type)

        local invalidCount = math.max(0, numNow - validCount)

        print(string.format("[%s] 🔄 Fresh valid=%d | invalid=%d",
            self.modName, validCount, invalidCount))

        ------------------------------------------------------------
        -- Fresh weights per cluster (weight × quality)
        ------------------------------------------------------------
        local cs = trailer.spec_livestockTrailer and trailer.spec_livestockTrailer.clusterSystem
        local clusterStats = {}
        local totalValidWeight = 0
        local totalRawWeight   = 0

        if cs and cs.animals then
            local breedMulSum = 0      -- for average breed bonus stat
            local breedCount  = 0

            for _, idx in ipairs(validClusters) do
                local c = cs.animals[idx]
                if c then
                    local num = c.numAnimals or 0

                    local w = tonumber(c.weight or 0) or 0.0
                    local q = 1.0
                    if c.genetics ~= nil and c.genetics.quality ~= nil then
                        q = tonumber(c.genetics.quality) or 1.0
                    end

                    -- NEW: per-breed multiplier (RealisticLivestock subtype)
                    local breedMul = PRBFix:getBreedMultiplier(data.type, c)

                    local adjW   = w * q * breedMul       -- effectiveWeight
                    --local adjW   = w * q
                    local totalW = num * adjW

                    print(string.format("[%s]    • Quality/BreedCheck | w=%.2f | q=%.3f | breed=%.3f | adjW=%.2f",
                        self.modName, w, q, breedMul, adjW))
                    --print(string.format("[%s]    • QualityCheck | w=%.2f | q=%.3f | adjW=%.2f",
                        --self.modName, w, q, adjW))

                    totalValidWeight = totalValidWeight + totalW
                    totalRawWeight   = totalRawWeight   + w

                    breedMulSum = breedMulSum + (breedMul * num)
                    breedCount  = breedCount  + num

                    table.insert(clusterStats, {
                        index       = idx,
                        num         = num,
                        rawWeight   = w,
                        quality     = q,
                        breedMul    = breedMul,
                        weight      = adjW,      -- adj weight (raw × quality)
                        totalWeight = totalW
                    })

                end
            end

            -- Average breed bonus for display (1.00 = no bonus)
            local avgBreedMul = 1.0
            if breedCount > 0 then
                avgBreedMul = breedMulSum / breedCount
            end
            data.breedBonus = avgBreedMul
        end

        print(string.format("[%s] Total raw weight = %d kg",
            self.modName, totalRawWeight))

        print(string.format("[%s] Total valid weight after quality check = %d kg",
            self.modName, totalValidWeight))

        ------------------------------------------------------------
        -- Average meat quality (weight-weighted over valid animals)
        ------------------------------------------------------------
        local avgQuality = 1.0
        if totalRawWeight > 0 then
            avgQuality = totalValidWeight / totalRawWeight
        end

        data.avgQuality = avgQuality

        print(string.format("[%s] Average quality for valid animals = %.3f (≈ %d%%)",
            self.modName, avgQuality, math.floor(avgQuality * 100 + 0.5)))

        ------------------------------------------------------------
        -- SAFE MAX DELIVERABLE (count only)
        ------------------------------------------------------------
        local maxDeliverable = math.max(0, math.min(cap.avail, validCount))

        ------------------------------------------------------------
        -- STORE ONLY FRESH VALUES
        ------------------------------------------------------------
        data.validCount         = validCount
        data.invalidCount       = invalidCount
        data.validClusters      = validClusters
        data.validClusterStats  = clusterStats
        data.totalValidWeight   = totalValidWeight

        ------------------------------------------------------------
        -- Prepare dialog data
        ------------------------------------------------------------
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
			trailer        = trailer,
			data           = data,
			cap            = cap,
			max            = maxDeliverable,
			farmId         = farmId,
			barnName       = barnName,
			callbackObject = self
		}
		


        ------------------------------------------------------------
        -- Open dialog
        ------------------------------------------------------------
        if g_gui and PRBDialog and PRBDialog.register then
            PRBDialog.register()

            if PRBDialog.INSTANCE then
                PRBDialog.INSTANCE:setDialogData(self.dialogData)
                print(string.format("[%s] 🧭 Opened Butcher Barn dialog | max=%d",
                    self.modName, maxDeliverable))
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
-- NEW: Open FS25 dialog (kept for safety / legacy)
----------------------------------------------------------------
function PRBFix:openButcherDialog(trailer, data, maxDeliverable)
    print(string.format("[%s] Opening PRBDialog... max=%d", self.modName, maxDeliverable or -1))

    if g_gui == nil or g_gui.showGui == nil then
        print(string.format("[%s] ❌ g_gui not ready, falling back to instant delivery", self.modName))
        self:deliverAnimals(trailer, data, maxDeliverable)
        return
    end

    local dialog = g_gui:showGui("PRBDialog")  -- MUST match Screen name & class
    if dialog == nil then
        print(string.format("[%s] ❌ PRBDialog not registered, falling back to instant delivery", self.modName))
        self:deliverAnimals(trailer, data, maxDeliverable)
        return
    end

    -- Pass data into dialog
    if dialog.setDialogData ~= nil then
        dialog:setDialogData({
            trailer = trailer,
            data = data,
            max = maxDeliverable,
            callbackObject = self
        })
    else
        print(string.format("[%s] ⚠️ PRBDialog has no setDialogData; falling back", self.modName))
        self:deliverAnimals(trailer, data, maxDeliverable)
    end
end

------------------------------------------------------------
-- Called by the dialog when player clicks OK
-- In SP: runs immediately via event:run() (local server)
-- In MP: client sends event → server runs deliverAnimals()
------------------------------------------------------------
function PRBFix:deliverAnimalsFromDialog(trailer, data, amount, farmId)
    print(string.format("[%s] deliverAnimalsFromDialog called, amount=%d, farmId=%s", 
        self.modName, amount or -1, tostring(farmId)))

    if amount == nil or amount <= 0 then
        print(string.format("[%s] ⚠️ Invalid amount from dialog, aborting", self.modName))
        return
    end

    if trailer == nil then
        print(string.format("[%s] ⚠️ deliverAnimalsFromDialog: trailer is nil", self.modName))
        return
    end

    if self.butcherBarnPlaceable == nil then
        print(string.format("[%s] ❌ deliverAnimalsFromDialog: butcherBarnPlaceable is nil", self.modName))
        return
    end

    -- Use the farmId that came from the dialog (fallback only if missing)
    farmId = farmId or 1
    if farmId == 1 and g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        farmId = g_currentMission:getFarmId()
    end

    if PR_DeliverAnimalsEvent ~= nil then
        print(string.format("[%s] ▶ Sending PR_DeliverAnimalsEvent (amount=%d, farmId=%d)", 
            self.modName, amount, farmId))
        PR_DeliverAnimalsEvent.send(farmId, self.butcherBarnPlaceable, trailer, amount, false)
    else
        print(string.format("[%s] ⚠️ PR_DeliverAnimalsEvent missing, calling deliverAnimals() locally", self.modName))
        if self.deliverAnimals ~= nil then
            self:deliverAnimals(trailer, data, amount)
        end
    end
end

------------------------------------------------------------
-- DELIVER ANIMALS (age-filtered, quality-weighted + Smart-Fit)
------------------------------------------------------------
function PRBFix:deliverAnimals(trailer, data, amount)
    if trailer == nil or data == nil then
        print(string.format("[%s] ⚠ deliverAnimals called with invalid args", self.modName))
        return
    end

    local typeName      = data.type or "UNKNOWN"
    local validClusters = data.validClusters or {}

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        print(string.format("[%s] ⚠ deliverAnimals: amount <= 0, nothing to do", self.modName))
        return
    end

    if #validClusters == 0 then
        print(string.format("[%s] ⚠ deliverAnimals: no valid clusters stored for trailer", self.modName))
        return
    end

    if amount > #validClusters then
        amount = #validClusters
    end

    local cap = self:checkBarnCapacity(typeName)
    if cap == nil then
        print(string.format("[%s] ⚠ deliverAnimals: no capacity info for '%s'", self.modName, typeName))
        return
    end

    local barn = self.butcherBarnPlaceable
    if barn == nil then
        print(string.format("[%s] ❌ deliverAnimals: butcherBarnPlaceable is nil", self.modName))
        return
    end

    local spec = barn.spec_extendedProductionPoint
    if spec == nil or spec.productionPoint == nil or spec.productionPoint.storage == nil then
        print(string.format("[%s] ❌ deliverAnimals: extendedProductionPoint / storage missing", self.modName))
        return
    end

    local st = spec.productionPoint.storage
    local ftIdx = g_fillTypeManager:getFillTypeIndexByName(cap.fillType)
    if ftIdx == nil then
        print(string.format("[%s] ❌ deliverAnimals: unknown fillType '%s'", self.modName, tostring(cap.fillType)))
        return
    end

    local specTrailer = trailer.spec_livestockTrailer
    if specTrailer == nil then
        print(string.format("[%s] ❌ deliverAnimals: trailer has no livestockTrailer spec", self.modName))
        return
    end

    local cs = specTrailer.clusterSystem
    if cs == nil or cs.animals == nil then
        print(string.format("[%s] ❌ deliverAnimals: trailer clusterSystem missing", self.modName))
        return
    end

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
    local prefix  = {0.0}

    for i, idx in ipairs(validClusters) do
        local cluster = cs.animals[idx]
        local w = 0.0

        if cluster ~= nil then
            local rawW = tonumber(cluster.weight or 0) or 0.0
            local q    = 1.0
            if cluster.genetics ~= nil and cluster.genetics.quality ~= nil then
                q = tonumber(cluster.genetics.quality) or 1.0
            end

            local breedMul = PRBFix:getBreedMultiplier(typeName, cluster)
            local adjW = rawW * q * breedMul

            print(string.format("[%s]    • DeliverCalc | raw=%.2f | q=%.3f | breed=%.3f | adj=%.2f",
                self.modName, rawW, q, breedMul, adjW))

            w = adjW
        end

        weights[i]     = w
        prefix[i + 1]  = prefix[i] + w
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

    local requested   = amount
    local used        = requested
    local availLiters = cap.avail or (cap.cap - cap.old)

    local simpleLiters = litersFor(used)

    if simpleLiters > availLiters + 0.0001 then
        while used > 0 and litersFor(used) > availLiters + 0.0001 do
            used = used - 1
        end

        print(string.format(
            "[%s] ⚖ Smart-Fit trimmed delivery from %d to %d animals to respect capacity (avail=%.2f L)",
            self.modName, requested, used, availLiters
        ))
    end

    if used <= 0 then
        print(string.format("[%s] ⚠ Smart-Fit result: 0 animals can be delivered within remaining capacity", self.modName))
        return
    end

    print(string.format("[%s] ---- DELIVERY DECISION BEGIN ----", self.modName))

    for i, idx in ipairs(validClusters) do
        local cluster = cs.animals[idx]
        if cluster ~= nil then
            local rawW = tonumber(cluster.weight or 0) or 0.0
            local q    = cluster.genetics and tonumber(cluster.genetics.quality) or 1.0
            local breedMul = PRBFix:getBreedMultiplier(typeName, cluster)
            local adjW = rawW * q * breedMul

            local status = (i <= used) and "DELIVER" or "SKIP"

            print(string.format(
                "[%s] Cluster %d | raw=%.2f | q=%.3f | breed=%.3f | adj=%.2f | %s",
                self.modName, idx, rawW, q, breedMul, adjW, status
            ))
        end
    end

    print(string.format("[%s] ---- DELIVERY DECISION END ----", self.modName))

    local totalWeight = totalWeightFor(used)
    local liters      = litersFor(used)

    local oldFill = cap.old
    local newFill = oldFill + liters

    if newFill > cap.cap then
        newFill = cap.cap
        liters  = cap.cap - oldFill
    end

    st:setFillLevel(newFill, ftIdx)

	-- Force the production point to re-stream its storage to clients
	local pp = spec.productionPoint
	if pp ~= nil then
		if pp.raiseDirtyFlags ~= nil then
			pp:raiseDirtyFlags(pp.dirtyFlag or 1)
		end
		if pp.setIsDirty ~= nil then
			pp:setIsDirty()
		end
		if pp.raiseActive ~= nil then
			pp:raiseActive()
		end
	end
	
	-- PR_DeliverAnimalsEvent.send(self.barn, trailer, used, true, newFill)
	-- PR_DeliverAnimalsEvent.send(self.barn, trailer, used, true, newFill, data.type)
	PR_DeliverAnimalsEvent.send(self.barn, trailer, used, true, newFill, typeName)

    print(string.format(
        "[%s] ➕ Added %.2f L %s from %d animals (quality+breed-weighted weight=%.1f kg, baseline=%.1f kg, old=%.2f, new=%.2f)",
        self.modName, liters, typeName, used, totalWeight, baseline, oldFill, newFill
    ))

    -- RLRM-proper removal
    local clustersToRemove = {}
    for i = 1, used do
        local idx = validClusters[i]
        if idx ~= nil and cs.animals[idx] ~= nil then
            table.insert(clustersToRemove, cs.animals[idx])
        end
    end

    print(string.format("[%s] 🐄 Delivering %d valid animals...", self.modName, used))

    for _, animal in ipairs(clustersToRemove) do
        if animal ~= nil then
            print(string.format("[%s]    • Queuing removal of animal uniqueId=%s age=%s weight=%.1f",
                self.modName, tostring(animal.uniqueId), tostring(animal.age or "?"), tonumber(animal.weight or 0)))
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

    if trailer.raiseActive ~= nil then
        trailer:raiseActive()
    end

    if barn ~= nil and barn.raiseDirtyFlags ~= nil then
        barn:raiseDirtyFlags(barn.placeableDirtyFlag or 1)
    end

    print(string.format("[%s] ✅ Removed %d animals via filtered clusters", self.modName, used))

    -- if g_server ~= nil and PR_DeliverAnimalsEvent ~= nil then
        -- local farmId = 1
        -- if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
            -- farmId = g_currentMission:getFarmId()
        -- end

        -- PR_DeliverAnimalsEvent.send(farmId, barn, trailer, used, true)
        -- print(string.format("[%s] 📡 Broadcast delivery result to clients (used=%d)", self.modName, used))
    -- end
end




------------------------------------------------------------
-- NEW: Clients apply the delivery result (mirror server changes)
------------------------------------------------------------
function PRBFix:applyDeliveryResult(trailer, animalType, count)
    if trailer == nil then return end

    local spec = trailer.spec_livestockTrailer
    if spec == nil or spec.clusterSystem == nil or spec.clusterSystem.animals == nil then
        print(string.format("[%s] ⚠ applyDeliveryResult: no clusterSystem", self.modName))
        return
    end

    local cs = spec.clusterSystem
    local removed = 0

    -- Remove from the end (matches the server order)
    for i = #cs.animals, 1, -1 do
        if removed < count then
            cs:removeCluster(i)
            removed = removed + 1
        end
    end

    if cs.updateClusters ~= nil then
        cs:updateClusters()
    end

    -- Force visual system refresh (try several common RLRM / livestockTrailer methods)
    if spec.updateVisuals ~= nil then
        spec:updateVisuals()
    end
    if spec.updateAnimalVisuals ~= nil then
        spec:updateAnimalVisuals()
    end
    if spec.refreshVisuals ~= nil then
        spec:refreshVisuals()
    end
    if spec.updateFillUnit ~= nil then
        spec:updateFillUnit()
    end

    -- If RLRM keeps a separate visual animals table, clear it
    if spec.visualAnimals ~= nil then
        for i = #spec.visualAnimals, 1, -1 do
            local va = spec.visualAnimals[i]
            if va ~= nil and va.delete ~= nil then
                va:delete()
            end
            table.remove(spec.visualAnimals, i)
        end
    end

    if trailer.setIsDirty ~= nil then
        trailer:setIsDirty()
    end
    if trailer.raiseDirtyFlags ~= nil then
        trailer:raiseDirtyFlags(trailer.vehicleDirtyFlag or 1)
    end

    print(string.format("[%s] ✅ Client applied delivery result: removed %d animals from trailer", self.modName, removed))
end