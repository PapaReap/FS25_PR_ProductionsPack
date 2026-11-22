PRBSpawnDialog = {}

local PRBSpawnDialog_mt = Class(PRBSpawnDialog, DialogElement)

function PRBSpawnDialog.register()
    local modDir = PRBFix.modDirectory or g_currentModDirectory
    if modDir == nil then
        print("[PR Butcher Spawn Dialog] modDir is nil")
        return
    end

    local xmlPath = modDir .. "gui/ButcherSpawnDialog.xml"
    g_gui:loadGui(xmlPath, "PRBSpawnDialog", PRBSpawnDialog.new, true)
    print("[PR Butcher Spawn Dialog] Registered")
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
    local item = self.availableList[self.selectedIndex]
    if item then
        print(string.format("[PR Butcher Spawn Dialog] Spawn requested: %s", item.fillType))
        -- TODO: call the actual spawn function here
        -- PRBFix:doSpawnPallet(item.fillType, self.farmId)
    end
    self:close()
end

function PRBSpawnDialog:onClickCancel()
    self:close()
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