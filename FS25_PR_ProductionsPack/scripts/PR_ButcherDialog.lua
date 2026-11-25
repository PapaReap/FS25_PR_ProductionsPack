-- PR_ButcherDialog.lua
-- Author: PapaReap
-- Contributers: Grok, Gemini, ChatGPT 5

--------------------------
-- CLASS TABLE
--------------------------
PRBDialog = {}
PRBDialog.INSTANCE = nil

------------------------------------------------------------
-- CREATE INSTANCE — FS25 SAFE (NO METATABLES)
------------------------------------------------------------
local function createDialogInstance()
    local self = ScreenElement.new(nil)

    self.setDialogData   = PRBDialog.setDialogData
    self.updateDisplay   = PRBDialog.updateDisplay
    self.onOpen          = PRBDialog.onOpen
    self.onClose         = PRBDialog.onClose
    self.onClickOk       = PRBDialog.onClickOk
    self.onClickBack     = PRBDialog.onClickBack
    self.onClickMinus    = PRBDialog.onClickMinus
    self.onClickPlus     = PRBDialog.onClickPlus
    self.onClickNextFarm = PRBDialog.onClickNextFarm
    self.onClickPrevFarm = PRBDialog.onClickPrevFarm
    self.cycleFarm       = PRBDialog.cycleFarm
    self.keyEvent        = PRBDialog.keyEvent
    self.update          = PRBDialog.update

    return self
end

------------------------------------------------------------
-- REGISTER GUI CONTROLS
------------------------------------------------------------
function PRBDialog:onCreate()
    self:registerControls({
        "titleText",
        "capacityValue",
        "storedValue",
        "trailerValue",
        "availableValue",
        "animalTypeValue",
        "invalidAgeValue",
        "amountValue",
        "deliveredWeightValue",
        "meatQualityValue",
        "farmValue",
        "okButton",
        "backButton"
    })
end

------------------------------------------------------------
-- helper for 2-decimal formatting
------------------------------------------------------------
local function fmt2(v)
    v = v or 0
    return string.format("%.2f", v)
end

local function computeDeliveredWeight(info, amount)
    local stats = info.validClusterStats
    if not stats or not amount or amount <= 0 then
        return 0
    end

    local remaining = amount
    local total = 0

    for _, s in ipairs(stats) do
        if remaining <= 0 then break end
        local num = math.min(remaining, s.num or 0)
        local w   = s.weight or 0
        total = total + (w * num)
        remaining = remaining - num
    end

    return total
end

------------------------------------------------------------
-- DIALOG DATA SETUP
------------------------------------------------------------
function PRBDialog:setDialogData(data)
    self.data = data
    self.selectedFarmId = data.farmId or (g_currentMission and g_currentMission:getFarmId()) or 1

    local cap  = data.cap or {}
    local info = data.data or {}

	if self.titleText ~= nil and self.data.barnName ~= nil then
		self.titleText:setText(self.data.barnName)
	end

    if self.capacityValue ~= nil then
        self.capacityValue:setText(tostring(cap.cap or 0))
    end

    if self.storedValue ~= nil then
        self.storedValue:setText(fmt2(cap.old))
    end

    if self.trailerValue ~= nil then
        self.trailerValue:setText(tostring(info.num or 0))
    end

    if self.availableValue ~= nil then
        self.availableValue:setText(fmt2(cap.avail))
    end

    if self.animalTypeValue ~= nil then
        local t = info.type or info.animalType or "COW"
        self.animalTypeValue:setText(string.upper(t))
    end

    if self.invalidAgeValue ~= nil then
        local totalInTrailer = info.num or 0
        local validCount     = info.validCount or 0
        local invalidCount   = math.max(0, totalInTrailer - validCount)
        self.invalidAgeValue:setText(tostring(invalidCount))
    end

    self.amount = data.max or 0
    if self.amountValue ~= nil then
        self.amountValue:setText(tostring(self.amount))
    end

    if self.deliveredWeightValue ~= nil then
        local totalWeight = computeDeliveredWeight(info, self.amount)
        self.deliveredWeightValue:setText(string.format("%.1f kg", totalWeight))
    end

    if self.meatQualityValue ~= nil then
        local avgQ    = info.avgQuality or 1.0
        local percent = math.floor(avgQ * 100 + 0.5)

        local category = ""
        if     avgQ >= 1.65 then category = "Extremely High"
        elseif avgQ >= 1.40 then category = "Very High"
        elseif avgQ >= 1.10 then category = "High"
        elseif avgQ >= 0.90 then category = "Average"
        elseif avgQ >= 0.70 then category = "Low"
        elseif avgQ >= 0.35 then category = "Very Low"
        else                     category = "Extremely Low"
        end

        self.meatQualityValue:setText(string.format("%d%%  %s", percent, category))
    end

    -- Delay the farm name resolve by one frame
    self.pendingFarmUpdate = true
	    -- Resolve farm name immediately
    self:updateDisplay()
end

------------------------------------------------------------
-- UPDATE (delayed farm name resolve)
------------------------------------------------------------
function PRBDialog:update(dt)
    if self.pendingFarmUpdate then
        self.pendingFarmUpdate = false
        self:updateDisplay()
    end
end

------------------------------------------------------------
-- OPEN EVENT
------------------------------------------------------------
function PRBDialog:onOpen()
    print("["..PRBFix.modNameDialog.."] Dialog opened")

    if not self.data then
        print("["..PRBFix.modNameDialog.."] ❌ onOpen called with no data")
        return
    end

    self.amount = self.data.max or 0
    -- Force farm name resolve on open
    self:updateDisplay()

    print(string.format("[PRBDialog] onOpen selectedFarmId=%s", tostring(self.selectedFarmId)))
	
    -- Enable mouse on the buttons without touching the dialog's own input
    if self.okButton then
        self.okButton.onClick = self.onClickOk
    end
    if self.backButton then
        self.backButton.onClick = self.onClickBack
    end
	
    -- Debug
    if g_farmManager and g_farmManager.farms then
        local farm = g_farmManager.farms[self.selectedFarmId]
        print(string.format("[PRBDialog] farm object=%s name=%s", tostring(farm), farm and tostring(farm.name) or "nil"))
    else
        print("[PRBDialog] g_farmManager.farms is nil")
    end
	
    if g_inputBinding then
        g_inputBinding:setShowMouseCursor(true)
    end
end

------------------------------------------------------------
-- CLOSE EVENT
------------------------------------------------------------
function PRBDialog:onClose()
    if g_inputBinding then
        g_inputBinding:setShowMouseCursor(false)
    end
	
    print("["..PRBFix.modNameDialog.."] Dialog closed")
end

------------------------------------------------------------
-- UPDATE DISPLAY
------------------------------------------------------------
function PRBDialog:updateDisplay()
    if not self.data then
        print("["..PRBFix.modNameDialog.."] ❌ updateDisplay called with no data")
        return
    end

    -- Farm name
if self.farmValue ~= nil then
    local farmName = "Farm " .. tostring(self.selectedFarmId)
    local targetId = self.selectedFarmId

    if g_farmManager ~= nil and g_farmManager.farms ~= nil then
        local farm = nil

        -- Search for the farm whose id or farmId matches
        for _, f in pairs(g_farmManager.farms) do
            if f ~= nil then
                if f.id == targetId or f.farmId == targetId then
                    farm = f
                    break
                end
            end
        end

        -- Fallback
        if farm == nil and g_farmManager.getFarmById ~= nil then
            farm = g_farmManager:getFarmById(targetId)
        end

        -- DEBUG
        if farm ~= nil then
            print("[PRBDialog] farm fields:")
            for k, v in pairs(farm) do
                if type(v) == "string" or type(v) == "number" then
                    print(string.format("  %s = %s", tostring(k), tostring(v)))
                end
            end
        else
            print(string.format("[PRBDialog] no farm found for id=%s", tostring(targetId)))
        end

        if farm ~= nil then
            if farm.name ~= nil and farm.name ~= "" then
                farmName = farm.name
            elseif farm.farmName ~= nil and farm.farmName ~= "" then
                farmName = farm.farmName
            end
        end
    end

    self.farmValue:setText(farmName)
end



    local cap  = self.data.cap or {}
    local info = self.data.data or {}

    local max = self.data.max or 0
    local amt = self.amount or max
    if amt < 0 then amt = 0 end
    if amt > max then amt = max end
    amt = math.floor(amt)
    self.amount = amt

    if self.capacityValue ~= nil then
        self.capacityValue:setText(tostring(cap.cap or 0))
    end

    if self.storedValue ~= nil then
        self.storedValue:setText(fmt2(cap.old))
    end

    if self.trailerValue ~= nil then
        self.trailerValue:setText(tostring(info.num or 0))
    end

    if self.availableValue ~= nil then
        self.availableValue:setText(fmt2(cap.avail))
    end

    if self.animalTypeValue ~= nil then
        local t = info.type or info.animalType or "COW"
        self.animalTypeValue:setText(string.upper(t))
    end

    if self.invalidAgeValue ~= nil then
        local totalInTrailer = info.num or 0
        local validCount     = info.validCount or 0
        local invalidCount   = math.max(0, totalInTrailer - validCount)
        self.invalidAgeValue:setText(tostring(invalidCount))
    end

    if self.amountValue ~= nil then
        self.amountValue:setText(string.format("%d", self.amount))
    end

    if self.deliveredWeightValue ~= nil then
        local totalWeight = computeDeliveredWeight(info, self.amount)
        self.deliveredWeightValue:setText(string.format("%.1f kg", totalWeight))
    end

    -- Meat Quality
    if self.meatQualityValue ~= nil then
        local stats = info.validClusterStats or {}
        local amt   = self.amount or 0

        local totalQ = 0
        local totalAnimals = 0

        for i = 1, #stats do
            local cs = stats[i]
            if cs and cs.quality and cs.num then
                for j = 1, cs.num do
                    totalQ = totalQ + cs.quality
                    totalAnimals = totalAnimals + 1
                    if totalAnimals >= amt then break end
                end
            end
            if totalAnimals >= amt then break end
        end

        local avgQ = (totalAnimals > 0) and (totalQ / totalAnimals) or 1.0
        local percent = math.floor(avgQ * 100 + 0.5)

        local category = ""
        if     avgQ >= 1.65 then category = "Extremely High"
        elseif avgQ >= 1.40 then category = "Very High"
        elseif avgQ >= 1.10 then category = "High"
        elseif avgQ >= 0.90 then category = "Average"
        elseif avgQ >= 0.70 then category = "Low"
        elseif avgQ >= 0.35 then category = "Very Low"
        else                     category = "Extremely Low"
        end

        self.meatQualityValue:setText(string.format("%d%%  %s", percent, category))
    end

    -- Breed Bonus
    if self.breedBonusValue ~= nil then
        local stats = info.validClusterStats or {}
        local used  = self.amount or 0

        if used > 0 then
            local breedSum = 0
            local count = 0

            for i = 1, #stats do
                local s = stats[i]
                if s and s.breedMul then
                    for j = 1, (s.num or 0) do
                        breedSum = breedSum + s.breedMul
                        count = count + 1
                        if count >= used then break end
                    end
                end
                if count >= used then break end
            end

            local avgBreed = breedSum / used
            local pct = math.floor(((avgBreed - 1) * 100) + 0.5)
            self.breedBonusValue:setText(string.format("+%d%%", pct))
        else
            self.breedBonusValue:setText("+0%")
        end
    end
end

------------------------------------------------------------
-- Farm cycling
------------------------------------------------------------
function PRBDialog:onClickNextFarm()
    self:cycleFarm(1)
end

function PRBDialog:onClickPrevFarm()
    self:cycleFarm(-1)
end

function PRBDialog:cycleFarm(direction)
    local farms = {}
    if g_farmManager and g_farmManager.farms then
        for _, farm in pairs(g_farmManager.farms) do
            if farm and not farm.isSpectator then
                local fid = farm.farmId or farm.id
                local name = farm.name or farm.farmName or ""

                -- Only include farms that have a real name
                if fid ~= nil and fid > 0 and name ~= "" then
                    table.insert(farms, fid)
                    print(string.format("[PRBDialog] cycleFarm adding id=%s name=%s", tostring(fid), name))
                end
            end
        end
        table.sort(farms)
    end

    print(string.format("[PRBDialog] cycleFarm list size=%d", #farms))

    if #farms == 0 then return end

    local currentIndex = 1
    for i, id in ipairs(farms) do
        if id == self.selectedFarmId then
            currentIndex = i
            break
        end
    end

    local newIndex = currentIndex + direction
    if newIndex < 1 then newIndex = #farms end
    if newIndex > #farms then newIndex = 1 end

    self.selectedFarmId = farms[newIndex]
    print(string.format("[PRBDialog] cycleFarm new selectedFarmId=%s", tostring(self.selectedFarmId)))
    self:updateDisplay()
end

------------------------------------------------------------
-- Spinner controls
------------------------------------------------------------
function PRBDialog:onClickMinus()
    if not self.data or not self.amountValue then return end

    local max = self.data.max or 0
    local v   = tonumber(self.amountValue:getText()) or 0

    v = v - 1
    if v < 0 then
        v = max
    end

    self.amountValue:setText(tostring(v))
    self.amount = v
    self:updateDisplay()
end

function PRBDialog:onClickPlus()
    if not self.data or not self.amountValue then return end

    local max = self.data.max or 0
    local v   = tonumber(self.amountValue:getText()) or 0

    v = v + 1
    if v > max then
        v = 0
    end

    self.amountValue:setText(tostring(v))
    self.amount = v
    self:updateDisplay()
end

------------------------------------------------------------
-- Keyboard input
------------------------------------------------------------
function PRBDialog:keyEvent(unicode, sym, modifier, isDown)
    if not isDown or not self.data or not self.amountValue then
        return
    end

    local max = self.data.max or 0
    local text = self.amountValue:getText() or ""
    local value = tonumber(text) or 0

    if sym == Input.KEY_return or sym == Input.KEY_enter then
        self:onClickOk()
        return
    end

    if sym == Input.KEY_back or sym == Input.KEY_escape then
        self:onClickBack()
        return
    end

    local step = 1
    if bitAND ~= nil and bitAND(modifier, Input.MOD_SHIFT) > 0 then
        step = 10
    end

    if sym == Input.KEY_left then
        value = value - step
        if value < 0 then
            value = max
        end
        self.amount = value
        self.amountValue:setText(tostring(value))
        self:updateDisplay()
        return
    end

    if sym == Input.KEY_right then
        value = value + step
        if value > max then
            value = 0
        end
        self.amount = value
        self.amountValue:setText(tostring(value))
        self:updateDisplay()
        return
    end

    if sym == Input.KEY_up then
        self:cycleFarm(-1)
        return
    end

    if sym == Input.KEY_down then
        self:cycleFarm(1)
        return
    end

    if sym == Input.KEY_backspace or sym == Input.KEY_delete then
        if #text > 0 then
            text = text:sub(1, #text - 1)
        end

        if text == "" then
            value = 0
        else
            value = tonumber(text) or 0
        end

        if value > max then
            value = max
        end

        self.amount = value
        self.amountValue:setText(tostring(value))
        self:updateDisplay()
        return
    end

    if unicode and unicode >= 48 and unicode <= 57 then
        local digit = unicode - 48

        if text == "0" then
            text = ""
        end

        text = text .. tostring(digit)
        local newValue = tonumber(text) or 0

        if newValue > max then
            newValue = max
            text = tostring(max)
        end

        self.amount = newValue
        self.amountValue:setText(text)
        self:updateDisplay()
        return
    end
end

------------------------------------------------------------
-- OK BUTTON
------------------------------------------------------------
function PRBDialog:onClickOk()
    if not self.data then return end

    local amount = 0
    if self.amountValue ~= nil then
        amount = tonumber(self.amountValue:getText()) or 0
    else
        amount = tonumber(self.amount) or 0
    end

    local trailer = self.data.trailer
    local info    = self.data.data
    local farmId  = self.selectedFarmId or 1

    print(string.format("[%s] OK clicked → Deliver %d animals for farm %d",
        PRBFix.modNameDialog, amount, farmId))

    local barn = (info and info.barn) or self.data.barn or PRBFix.butcherBarnPlaceable
    if barn == nil then
        print("[PRBDialog] ❌ butcherBarnPlaceable missing on client — cannot send event")
        return
    end

    if PR_DeliverAnimalsEvent ~= nil then
        print(string.format("[PRBDialog] ▶ Sending event: farm=%d, amount=%d", farmId, amount))
        PR_DeliverAnimalsEvent.send(farmId, barn, trailer, amount, info)
    else
        print("[PRBDialog] ❌ PR_DeliverAnimalsEvent missing, fallback to SP deliver")
        if PRBFix and PRBFix.deliverAnimals then
            PRBFix:deliverAnimals(trailer, info, amount, farmId)
        end
    end

    g_gui:closeDialogByName("PRBDialog")
end

------------------------------------------------------------
-- BACK BUTTON
------------------------------------------------------------
function PRBDialog:onClickBack()
    print("["..PRBFix.modNameDialog.."] Cancel clicked")
    g_gui:closeDialogByName("PRBDialog")
end

------------------------------------------------------------
-- ONE-TIME REGISTRATION
------------------------------------------------------------
function PRBDialog.register()
    if PRBDialog.INSTANCE ~= nil then
        return
    end

    local modDir = PRBFix and PRBFix.modDirectory
    if not modDir then
        print("["..PRBFix.modNameDialog.."] ❌ PRBFix.modDirectory not set — cannot load dialog")
        return
    end

    local xmlPath = modDir .. "gui/ButcherDialog.xml"
    if not fileExists(xmlPath) then
        print("["..PRBFix.modNameDialog.."] ❌ Dialog XML missing at: " .. xmlPath)
        return
    end

    print("["..PRBFix.modNameDialog.."] Registering PRBDialog at: " .. xmlPath)

    local instance = createDialogInstance()

    local ok, err = pcall(function()
        g_gui:loadGui(xmlPath, "PRBDialog", instance)
    end)

    if not ok then
        print("["..PRBFix.modNameDialog.."] ❌ loadGui failed: " .. tostring(err))
        return
    end

    PRBDialog.INSTANCE = instance
    print(string.format("[%s] ✅ Registered successfully (v%s)", PRBFix.modNameDialog, PRBFix.VersionDialog))
end

------------------------------------------------------------
-- SPAWN DIALOG (Available for pickup only)
------------------------------------------------------------
function PRBDialog:showSpawnDialog(availableList, farmId)
    print("[PR Butcher Dialog] showSpawnDialog called, count=" .. tostring(#availableList))

    self.spawnAvailableList = availableList or {}
    self.spawnFarmId = farmId
    self.spawnSelectedIndex = 1

    if #self.spawnAvailableList == 0 then
        print("[PR Butcher Dialog] No available products")
        return
    end

    -- Match the way the animal dialog is opened
    g_gui:showDialog("PRBDialog")

	print("[PR Butcher Dialog] g_gui:showDialog returned, currentDialog = " .. tostring(g_gui.currentDialogName))

    self:updateSpawnDisplay()
end

function PRBDialog:updateSpawnDisplay()
    print("[PR Butcher Dialog] updateSpawnDisplay called")
	
	if self.dialogTitle then
		self.dialogTitle:setText("SPAWN PALLET")
	end
	
    if not self.spawnAvailableList or #self.spawnAvailableList == 0 then return end

    local item = self.spawnAvailableList[self.spawnSelectedIndex]
    if item and self.titleText then
        self.titleText:setText(string.format("Spawn %s  (%.0f L ready)", item.fillType, item.amount))
    end

    if self.farmValue then
        local farm = g_farmManager and g_farmManager:getFarmById(self.spawnFarmId)
        local farmName = (farm and farm.name) or ("Farm " .. tostring(self.spawnFarmId))
        self.farmValue:setText(farmName)
    end

    -- Clear animal-specific fields so the dialog looks cleaner for spawn mode
    if self.animalTypeValue then self.animalTypeValue:setText("") end
    if self.trailerValue then self.trailerValue:setText("") end
    if self.amountValue then self.amountValue:setText("1000") end
end

function PRBDialog:onClickSpawnOK()
    if not self.spawnAvailableList or #self.spawnAvailableList == 0 then return end

    local item = self.spawnAvailableList[self.spawnSelectedIndex]
    local farmId = self.spawnFarmId
    local barnKey = item.barnKey or self.spawnBarnKey or (PRBFix and PRBFix.getBarnKey and PRBFix:getBarnKey(PRBFix.dialogBarn or PRBFix.butcherBarnPlaceable))

    print(string.format("[PR Butcher Dialog] Spawn OK → %s for farm %d at barn %s",
        item.fillType, farmId, tostring(barnKey)))

    local pallets = PRBFix.farmMeatPallets and barnKey and PRBFix.farmMeatPallets[barnKey] and PRBFix.farmMeatPallets[barnKey][farmId]
    if pallets and pallets[item.fillType] then
        local entry = pallets[item.fillType]
        if entry.amount >= 1000 then
            entry.amount = entry.amount - 1000
            if entry.amount < 0.01 then
                pallets[item.fillType] = nil
            end

            if PRBFix and PRBFix.spawnReadyPallet then
                PRBFix:spawnReadyPallet(farmId, item.fillType, barnKey)
            end

            if PRBFix.syncFarmMeat then
                PRBFix:syncFarmMeat()
            end
        end
    end

    g_gui:closeDialogByName("PRBDialog")
end

-- Optional: cycle through available products with up/down while in spawn mode
function PRBDialog:cycleSpawnProduct(direction)
    if not self.spawnAvailableList or #self.spawnAvailableList == 0 then return end
    self.spawnSelectedIndex = self.spawnSelectedIndex + direction
    if self.spawnSelectedIndex < 1 then self.spawnSelectedIndex = #self.spawnAvailableList end
    if self.spawnSelectedIndex > #self.spawnAvailableList then self.spawnSelectedIndex = 1 end
    self:updateSpawnDisplay()
end



------------------------------------------------------------
-- EXPORT
------------------------------------------------------------
return PRBDialog