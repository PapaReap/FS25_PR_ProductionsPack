-- PR_DeliverAnimalsEvent.lua

PR_DeliverAnimalsEvent = {}
local PR_DeliverAnimalsEvent_mt = Class(PR_DeliverAnimalsEvent, Event)

InitEventClass(PR_DeliverAnimalsEvent, "PR_DeliverAnimalsEvent")

function PR_DeliverAnimalsEvent.emptyNew()
    local self = Event.new(PR_DeliverAnimalsEvent_mt)
    return self
end

function PR_DeliverAnimalsEvent.new(arg1, arg2, arg3, arg4, arg5, arg6)
    local self = PR_DeliverAnimalsEvent.emptyNew()

    -- Dialog call style: send(farmId, barn, trailer, amount, data)
    -- Result call style:  send(barn, trailer, amount, true, newFillLevel, animalTypeName)
    local isDialogCall = (type(arg5) == "table") or (type(arg1) == "number" and type(arg5) ~= "number" and type(arg5) ~= "boolean")

    if isDialogCall then
        self.farmId        = arg1 or 0
        self.barn          = arg2
        self.trailer       = arg3
        self.amount        = arg4 or 0
        self.isResult      = false
        self.newFillLevel  = 0
        self.animalType    = ""
        print(string.format("[PR Butcher Fix] Event created (REQUEST) farm=%d amount=%d", self.farmId, self.amount))
    else
        self.farmId        = 0
        self.barn          = arg1
        self.trailer       = arg2
        self.amount        = tonumber(arg3) or 0
        self.isResult      = (arg4 == true)
        self.newFillLevel  = tonumber(arg5) or 0
        self.animalType    = arg6 or "CHICKEN"
        print(string.format("[PR Butcher Fix] Event created (RESULT) amount=%d newFill=%.2f type=%s", self.amount, self.newFillLevel, self.animalType))
    end

    return self
end

function PR_DeliverAnimalsEvent:readStream(streamId, connection)
    self.farmId       = streamReadUInt8(streamId)
    self.barn         = NetworkUtil.readNodeObject(streamId)
    self.trailer      = NetworkUtil.readNodeObject(streamId)
    self.amount       = streamReadUInt16(streamId)
    self.isResult     = streamReadBool(streamId)
    self.newFillLevel = streamReadFloat32(streamId)
    self.animalType   = streamReadString(streamId)

    print(string.format("[PR Butcher Fix] Event.readStream isResult=%s amount=%d newFill=%.2f type=%s barn=%s trailer=%s",
        tostring(self.isResult), self.amount, self.newFillLevel or 0, self.animalType or "?",
        tostring(self.barn ~= nil), tostring(self.trailer ~= nil)))

    self:run(connection)
end

function PR_DeliverAnimalsEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.farmId or 0)
    NetworkUtil.writeNodeObject(streamId, self.barn)
    NetworkUtil.writeNodeObject(streamId, self.trailer)
    streamWriteUInt16(streamId, self.amount or 0)
    streamWriteBool(streamId, self.isResult == true)
    streamWriteFloat32(streamId, self.newFillLevel or 0)
    streamWriteString(streamId, self.animalType or "")
end

function PR_DeliverAnimalsEvent:run(connection)
    print(string.format("[PR Butcher Fix] Event.run isResult=%s amount=%d newFill=%.2f type=%s",
        tostring(self.isResult), self.amount, self.newFillLevel or 0, self.animalType or "?"))

    if self.isResult then
        -- Clients: remove animals from trailer
        if self.trailer ~= nil and PRBFix ~= nil and PRBFix.applyDeliveryResult ~= nil then
            PRBFix:applyDeliveryResult(self.trailer, nil, self.amount)
        end

        -- Clients: force the correct meat fill type on the production point
        if self.newFillLevel ~= nil and self.newFillLevel > 0 and self.animalType ~= nil and self.animalType ~= "" then
            local barn = self.barn
            if barn == nil and PRBFix ~= nil then
                barn = PRBFix.butcherBarnPlaceable
            end

            if barn ~= nil then
                local spec = barn.spec_extendedProductionPoint
                if spec ~= nil and spec.productionPoint ~= nil and spec.productionPoint.storage ~= nil then
                    local st = spec.productionPoint.storage

                    local meatFillType = "POULTRY"
                    if PRBFix ~= nil and PRBFix.ANIMAL_TO_MEAT_FILLTYPE ~= nil then
                        meatFillType = PRBFix.ANIMAL_TO_MEAT_FILLTYPE[self.animalType] or meatFillType
                    end

                    local ftIdx = g_fillTypeManager:getFillTypeIndexByName(meatFillType)
                    if ftIdx ~= nil then
                        st:setFillLevel(self.newFillLevel, ftIdx)
                        if st.fillLevels ~= nil then
                            st.fillLevels[ftIdx] = self.newFillLevel
                        end
                        if st.fillLevelChangedListeners ~= nil then
                            for _, func in ipairs(st.fillLevelChangedListeners) do
                                func(ftIdx, 0)
                            end
                        end
                        print(string.format("[PR Butcher Fix] Client forced %s fill to %.2f (animal=%s)", meatFillType, self.newFillLevel, self.animalType))
                    else
                        print(string.format("[PR Butcher Fix] Client could not find fill type index for %s", meatFillType))
                    end
                else
                    print("[PR Butcher Fix] Client missing extendedProductionPoint / storage")
                end
            else
                print("[PR Butcher Fix] Client has no barn reference at all")
            end
        end
    else
        -- Server: process the actual delivery against the specific barn sent in the event
        if g_server ~= nil and PRBFix ~= nil and self.trailer ~= nil then
            local targetBarn = self.barn or PRBFix.butcherBarnPlaceable
            local targetBarnKey = PRBFix.getBarnKey and PRBFix:getBarnKey(targetBarn) or nil

            local animalType = self.trailer:getCurrentAnimalType()
            local typeName = (animalType and animalType.name) or "CHICKEN"

            local validCount, validClusters = PRBFix:countValidAnimals(self.trailer, typeName)
            local data = {
                type = typeName,
                validClusters = validClusters,
                validCount = validCount,
                barn = targetBarn,
                barnKey = targetBarnKey
            }

            print(string.format("[PR Butcher Fix] Server processing request: type=%s valid=%d amount=%d barn=%s",
                typeName, validCount, self.amount, tostring(targetBarnKey)))
            PRBFix:deliverAnimals(self.trailer, data, self.amount, self.farmId)
        else
            print("[PR Butcher Fix] Event.run request skipped (no server, no PRBFix, or no trailer)")
        end
    end
end

-- function PR_DeliverAnimalsEvent.send(...)
    -- local event = PR_DeliverAnimalsEvent.new(...)
    -- if g_server ~= nil then
        -- print("[PR Butcher Fix] Broadcasting event from server")
        -- g_server:broadcastEvent(event)
    -- else
        -- print("[PR Butcher Fix] Sending event from client to server")
        -- g_client:getServerConnection():sendEvent(event)
    -- end
-- end
function PR_DeliverAnimalsEvent.send(...)
    local event = PR_DeliverAnimalsEvent.new(...)
    if g_server ~= nil then
        print("[PR Butcher Fix] Broadcasting event from server")
        g_server:broadcastEvent(event)

        -- SP / host: also run the request locally
        if not event.isResult then
            event:run(nil)
        end
    else
        print("[PR Butcher Fix] Sending event from client to server")
        g_client:getServerConnection():sendEvent(event)
    end
end