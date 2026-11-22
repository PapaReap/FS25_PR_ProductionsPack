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
end

function PRBSpawnDialog:updateDisplay()
    if #self.availableList == 0 then
        if self.productText then self.productText:setText("No pallets ready") end
        if self.amountText then self.amountText:setText("") end
        return
    end

    local item = self.availableList[self.selectedIndex]
    if item then
        if self.productText then
            self.productText:setText(string.format("%s  (%d / %d)", item.fillType, self.selectedIndex, #self.availableList))
        end
        if self.amountText then
            self.amountText:setText(string.format("%.0f L", item.amount or 0))
        end
    end
end

function PRBSpawnDialog:onClickOk()
    if not self.availableList or #self.availableList == 0 then
        g_gui:closeDialogByName("PRBSpawnDialog")
        return
    end

    local item = self.availableList[self.selectedIndex]
    if item == nil then
        g_gui:closeDialogByName("PRBSpawnDialog")
        return
    end

    local farmId = self.farmId or (g_currentMission and g_currentMission:getFarmId()) or 1

    print(string.format("[PR Butcher Spawn Dialog] Spawn requested: %s for farm %d", item.fillType, farmId))

    if PRBFix and PRBFix.doSpawnPallet then
        PRBFix:doSpawnPallet(item.fillType, farmId)
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