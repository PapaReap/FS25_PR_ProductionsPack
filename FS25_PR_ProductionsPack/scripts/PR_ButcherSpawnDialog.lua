PRBSpawnDialog = {}

local PRBSpawnDialog_mt = Class(PRBSpawnDialog, DialogElement)

function PRBSpawnDialog.register()
    if PRBSpawnDialog.INSTANCE ~= nil then
        return
    end

    local modDir = PRBFix.modDirectory or g_currentModDirectory
    if modDir == nil then
        print("[PR Butcher Spawn Dialog] modDir is nil")
        return
    end

    local xmlPath = modDir .. "gui/ButcherSpawnDialog.xml"
    if not fileExists(xmlPath) then
        print("[PR Butcher Spawn Dialog] XML missing: " .. xmlPath)
        return
    end

    print("[PR Butcher Spawn Dialog] Registering at: " .. xmlPath)

	-- Create instance the same way the animal dialog does
	local instance = ScreenElement.new(nil)
	instance.onOpen = PRBSpawnDialog.onOpen
	instance.onClose = PRBSpawnDialog.onClose
	instance.onClickOk = PRBSpawnDialog.onClickOk
	instance.onClickCancel = PRBSpawnDialog.onClickCancel
	instance.setSpawnData = PRBSpawnDialog.setSpawnData
	instance.updateDisplay = PRBSpawnDialog.updateDisplay
	instance.keyEvent = PRBSpawnDialog.keyEvent

    local ok, err = pcall(function()
        g_gui:loadGui(xmlPath, "PRBSpawnDialog", instance)
    end)

    if not ok then
        print("[PR Butcher Spawn Dialog] loadGui failed: " .. tostring(err))
        return
    end

    PRBSpawnDialog.INSTANCE = instance
    print("[PR Butcher Spawn Dialog] Registered successfully")
end

function PRBSpawnDialog.new(target, custom_mt)
    local self = DialogElement.new(target, custom_mt or PRBSpawnDialog_mt)
    self.availableList = {}
    self.selectedIndex = 1
    self.farmId = 1
    return self
end

function PRBSpawnDialog:onOpen()
    PRBSpawnDialog:superClass().onOpen(self)
    self:updateDisplay()
    if self.dialogElement then
        self.dialogElement.mouseEvent = self.mouseEvent
    end
end

function PRBSpawnDialog:updateDisplay()
    local maxLines = 12
    for i = 1, maxLines do
        local nameEl  = self:getDescendantById("line" .. i)
        local amtEl   = self:getDescendantById("amt" .. i)
        local checkEl = self:getDescendantById("check" .. i)
        if nameEl then 
            nameEl:setText("")
            nameEl:setTextColor(1, 1, 1, 1)
        end
        if amtEl then 
            amtEl:setText("")
            amtEl:setTextColor(1, 1, 1, 1)
        end
        if checkEl then checkEl:setText("") end
    end

    -- Show remaining empty pallets
    local empty = 0
    if self.farmId and PRBFix.farmMeat and PRBFix.farmMeat[self.farmId] then
        empty = PRBFix.farmMeat[self.farmId]["EMPTYPALLET"] or 0
    end
    local storageEl = self:getDescendantById("palletStorageValue")
    if storageEl then
        storageEl:setText(string.format("%.0f L", empty))
    end

    if #self.availableList == 0 then
        local nameEl = self:getDescendantById("line1")
        if nameEl then
            nameEl:setText("No products ready for pickup")
            nameEl:setTextColor(1, 0.85, 0.3, 1)
        end
        return
    end

    for i, item in ipairs(self.availableList) do
        if i > maxLines then break end
        local nameEl  = self:getDescendantById("line" .. i)
        local amtEl   = self:getDescendantById("amt" .. i)
        local checkEl = self:getDescendantById("check" .. i)

        local isSelected = (i == self.selectedIndex)
        local r, g, b = 1, 1, 1
        if isSelected then
            r, g, b = 0.3, 1, 0.3
        end

        if nameEl then 
            -- nameEl:setText(item.fillType)
            -- nameEl:setTextColor(r, g, b, 1)
            local displayName = item.fillType:sub(1,1):upper() .. item.fillType:sub(2):lower()
            nameEl:setText(displayName)
            nameEl:setTextColor(r, g, b, 1)
        end
        if amtEl then 
            amtEl:setText(string.format("%.0f L", item.amount or 0))
            amtEl:setTextColor(r, g, b, 1)
        end
        if checkEl then
            checkEl:setText(item.selected and "[X]" or "[ ]")
            checkEl:setTextColor(r, g, b, 1)
        end
    end
end

function PRBSpawnDialog:onClickOk()
    if not self.availableList or #self.availableList == 0 then
        g_gui:closeDialogByName("PRBSpawnDialog")
        return
    end

    local farmId = self.farmId or (g_currentMission and g_currentMission:getFarmId()) or 1

    local selected = {}
    for _, item in ipairs(self.availableList) do
        if item.selected then
            table.insert(selected, item.fillType)
        end
    end

    if #selected == 0 then
        print("[PR Butcher Spawn Dialog] Nothing selected")
        g_gui:closeDialogByName("PRBSpawnDialog")
        return
    end

    -- Cap at 10
    local toSpawn = {}
    for i = 1, math.min(10, #selected) do
        table.insert(toSpawn, selected[i])
    end

    print(string.format("[PR Butcher Spawn Dialog] Requesting spawn of %d products for farm %d", #toSpawn, farmId))

    -- Send request to the server
    if g_server then
        -- We are the server, do it directly
        PRBFix:handleSpawnRequest(toSpawn, farmId)
    else
        -- Client: send event
        g_client:getServerConnection():sendEvent(PR_SpawnPalletsEvent.new(toSpawn, farmId))
    end

    g_gui:closeDialogByName("PRBSpawnDialog")
end

function PRBSpawnDialog:onClickCancel()
    print("[PR Butcher Spawn Dialog] Cancel clicked")
    g_gui:closeDialogByName("PRBSpawnDialog")
end

function PRBSpawnDialog.show(availableList, farmId)
    if PRBSpawnDialog.INSTANCE == nil then
        print("[PR Butcher Spawn Dialog] INSTANCE is nil")
        return
    end

    local dialog = PRBSpawnDialog.INSTANCE
    dialog.availableList = availableList or {}
    dialog.farmId = farmId or 1
    dialog.selectedIndex = 1

    g_gui:showDialog("PRBSpawnDialog")
end

function PRBSpawnDialog:keyEvent(unicode, sym, modifier, isDown)
    if not isDown then return end
    if #self.availableList == 0 then return end

    if sym == Input.KEY_up then
        self.selectedIndex = self.selectedIndex - 1
        if self.selectedIndex < 1 then self.selectedIndex = #self.availableList end
        self:updateDisplay()
    elseif sym == Input.KEY_down then
        self.selectedIndex = self.selectedIndex + 1
        if self.selectedIndex > #self.availableList then self.selectedIndex = 1 end
        self:updateDisplay()
    elseif sym == Input.KEY_space or sym == Input.KEY_return then
        local item = self.availableList[self.selectedIndex]
        if item then
            item.selected = not item.selected
            self:updateDisplay()
        end
    end
end

function PRBSpawnDialog:mouseEvent(posX, posY, isDown, isUp, button)
    if not isDown or button ~= Input.MOUSE_BUTTON_LEFT then return end
    if #self.availableList == 0 then return end

    -- Ignore clicks that are low on the screen (button bar)
    if posY < 0.18 then return end

    local lineHeight = 0.028
    local startY = 0.68
    local leftX  = 0.22
    local rightX = 0.78

    if posX < leftX or posX > rightX then return end

    for i = 1, math.min(15, #self.availableList) do
        local lineTop    = startY - (i - 1) * lineHeight
        local lineBottom = lineTop - lineHeight

        if posY <= lineTop and posY >= lineBottom then
            local item = self.availableList[i]
            if item then
                item.selected = not item.selected
                self.selectedIndex = i
                self:updateDisplay()
                print(string.format("[PR Butcher Spawn Dialog] Toggled line %d (%s)", i, item.fillType))
            end
            return
        end
    end
end