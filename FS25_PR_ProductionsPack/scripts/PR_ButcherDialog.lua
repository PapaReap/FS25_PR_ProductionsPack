-- PR_ButcherDialog.lua
-- Author: PapaReap
-- Contributers: ChatGPT 5

--------------------------
-- CLASS TABLE
--------------------------
PRBDialog = {}
--PRBDialog.VERSION = PRBFix.VERSION
--PRBDialog.modName = "PR Butcher Dialog"
PRBDialog.INSTANCE = nil

------------------------------------------------------------
-- CREATE INSTANCE — FS25 SAFE (NO METATABLES)
------------------------------------------------------------
local function createDialogInstance()
    local self = ScreenElement.new(nil)

    ----------------------------------------------------
    -- Bind all instance methods
    ----------------------------------------------------
    self.setDialogData  = PRBDialog.setDialogData
    self.updateDisplay  = PRBDialog.updateDisplay
    self.onOpen         = PRBDialog.onOpen
    self.onClose        = PRBDialog.onClose
    self.onClickOk      = PRBDialog.onClickOk
    self.onClickBack    = PRBDialog.onClickBack
    self.onClickMinus   = PRBDialog.onClickMinus
    self.onClickPlus    = PRBDialog.onClickPlus

    -- Arrow key support
    self.keyEvent       = PRBDialog.keyEvent

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
        "amountMinus",
        "amountPlus",
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

-- helper: compute total delivered weight for current amount
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

    local cap  = data.cap or {}
    local info = data.data or {}

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

    -- invalid age count (total in trailer - valid)
    if self.invalidAgeValue ~= nil then
        local totalInTrailer = info.num or 0
        local validCount     = info.validCount or 0
        local invalidCount   = math.max(0, totalInTrailer - validCount)
        self.invalidAgeValue:setText(tostring(invalidCount))
    end

    -- Default selected amount = maximum possible
    self.amount = data.max or 0
    if self.amountValue ~= nil then
        self.amountValue:setText(tostring(self.amount))
    end

    -- Delivered weight preview (QUALITY-BASED, via validClusterStats.weight)
    if self.deliveredWeightValue ~= nil then
        local totalWeight = computeDeliveredWeight(info, self.amount)
        self.deliveredWeightValue:setText(string.format("%.1f kg", totalWeight))
    end

    --------------------------------------------------------
    -- Meat Quality (initial display setup)
    --------------------------------------------------------
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

        local txt = string.format("%d%%  %s", percent, category)
        self.meatQualityValue:setText(txt)
    end
end

------------------------------------------------------------
-- OPEN EVENT
------------------------------------------------------------
function PRBDialog:onOpen()
	-- if PRBFix.disabled then 
		-- g_gui:closeDialogByName("PRBDialog")
		-- return 
	-- end

    print("["..PRBFix.modNameDialog.."] Dialog opened")

    if not self.data then
        print("["..PRBFix.modNameDialog.."] ❌ onOpen called with no data")
        return
    end

    -- reset amount each time we open, based on current max
    self.amount = self.data.max or 0
    self:updateDisplay()
end

------------------------------------------------------------
-- CLOSE EVENT
------------------------------------------------------------
function PRBDialog:onClose()
    print("["..PRBFix.modNameDialog.."] Dialog closed")
end

------------------------------------------------------------
-- UPDATE DISPLAY — refresh all visible values
------------------------------------------------------------
function PRBDialog:updateDisplay()
	-- if PRBFix.disabled then 
		-- g_gui:closeDialogByName("PRBDialog")
		-- return 
	-- end

    if not self.data then
        print("["..PRBFix.modNameDialog.."] ❌ updateDisplay called with no data")
        return
    end

    local cap  = self.data.cap or {}
    local info = self.data.data or {}

    -- clamp amount inside [0, max]
    local max = self.data.max or 0
    local amt = self.amount or max
    if amt < 0 then amt = 0 end
    if amt > max then amt = max end

    -- force whole integer
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

    --------------------------------------------------------
    -- Meat Quality (dynamic based on selected amount)
    --------------------------------------------------------
    if self.meatQualityValue ~= nil then
        local stats = info.validClusterStats or {}
        local amt   = self.amount or 0

        local totalQ = 0
        local totalAnimals = 0

        -- accumulate quality for FIRST amt animals
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

        -- default 1.0 if 0 animals selected
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

	--------------------------------------------------------
	-- Breed Bonus (Average breed multiplier of selected animals)
	--------------------------------------------------------
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
-- Spinner controls: MOUSE +/- (kept for safety)
------------------------------------------------------------
------------------------------------------------------------
-- MOUSE: MINUS BUTTON (wrap-around)
------------------------------------------------------------
function PRBDialog:onClickMinus()
    if not self.data or not self.amountValue then return end

    local max = self.data.max or 0
    local v   = tonumber(self.amountValue:getText()) or 0

    -- decrement with wrap-around
    v = v - 1
    if v < 0 then
        v = max
    end

    self.amountValue:setText(tostring(v))
    self.amount = v
    self:updateDisplay()
end

------------------------------------------------------------
-- MOUSE: PLUS BUTTON (wrap-around)
------------------------------------------------------------
function PRBDialog:onClickPlus()
    if not self.data or not self.amountValue then return end

    local max = self.data.max or 0
    local v   = tonumber(self.amountValue:getText()) or 0

    -- increment with wrap-around
    v = v + 1
    if v > max then
        v = 0
    end

    self.amountValue:setText(tostring(v))
    self.amount = v
    self:updateDisplay()
end

------------------------------------------------------------
-- Keyboard input: arrows + SHIFT, digits, backspace, enter/esc
------------------------------------------------------------
function PRBDialog:keyEvent(unicode, sym, modifier, isDown)
    -- Only react on key down and when dialog is active
    if not isDown or not self.data or not self.amountValue then
        return
    end

    local max = self.data.max or 0
    local text = self.amountValue:getText() or ""
    local value = tonumber(text) or 0

    --------------------------------------------------------
    -- ENTER → OK
    --------------------------------------------------------
    if sym == Input.KEY_return or sym == Input.KEY_enter then
        self:onClickOk()
        return
    end

    --------------------------------------------------------
    -- ESC → BACK
    --------------------------------------------------------
    if sym == Input.KEY_back or sym == Input.KEY_escape then
        self:onClickBack()
        return
    end

    --------------------------------------------------------
    -- SHIFT multiplier
    --------------------------------------------------------
    local step = 1
    if bitAND ~= nil and bitAND(modifier, Input.MOD_SHIFT) > 0 then
        step = 10
    end

    --------------------------------------------------------
    -- LEFT ARROW = decrease (with wrap)
    --------------------------------------------------------
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

    --------------------------------------------------------
    -- RIGHT ARROW = increase (with wrap)
    --------------------------------------------------------
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

    --------------------------------------------------------
    -- BACKSPACE / DELETE = remove last digit
    --------------------------------------------------------
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

    --------------------------------------------------------
    -- DIGITS via unicode (works for main row + numpad)
    --------------------------------------------------------
    if unicode and unicode >= 48 and unicode <= 57 then
        local digit = unicode - 48  -- '0'..'9' → 0..9

        -- Drop leading zero
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

    print(string.format("[%s] OK clicked → Deliver %d animals",
        PRBFix.modNameDialog, amount))

    local trailer = self.data.trailer
    local info    = self.data.data

    --------------------------------------------------------
    -- Multiplayer-safe: always use PRBFix.butcherBarnPlaceable
    --------------------------------------------------------
    local barn = PRBFix.butcherBarnPlaceable
    if barn == nil then
        print("[PRBDialog] ❌ butcherBarnPlaceable missing on client — cannot send event")
        return
    end

    --------------------------------------------------------
    -- Send event (MP) or fallback to SP logic
    --------------------------------------------------------
    if PR_DeliverAnimalsEvent ~= nil then
        local farmId = g_currentMission:getFarmId()

        print(string.format(
            "[PRBDialog] ▶ Sending event: farm=%d, amount=%d", farmId, amount
        ))

        PR_DeliverAnimalsEvent.send(farmId, barn, trailer, amount, info)
    else
        print("[PRBDialog] ❌ PR_DeliverAnimalsEvent missing, fallback to SP deliver")
        if PRBFix and PRBFix.deliverAnimals then
            PRBFix:deliverAnimals(trailer, info, amount)
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
-- ONE-TIME REGISTRATION (unchanged, but using table class)
------------------------------------------------------------
function PRBDialog.register()
    if PRBDialog.INSTANCE ~= nil then
        return
    end

    --------------------------------------------------------
    -- Get correct mod directory from PR_ButcherFix.lua
    --------------------------------------------------------
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
-- EXPORT
------------------------------------------------------------
return PRBDialog
