PR_DeliverAnimalsEvent = {}
local PR_DeliverAnimalsEvent_mt = Class(PR_DeliverAnimalsEvent, Event)

InitEventClass(PR_DeliverAnimalsEvent, "PR_DeliverAnimalsEvent")

function PR_DeliverAnimalsEvent.emptyNew()
    local self = Event.new(PR_DeliverAnimalsEvent_mt)
    return self
end

function PR_DeliverAnimalsEvent.new(arg1, arg2, arg3, arg4, arg5)
    local self = PR_DeliverAnimalsEvent.emptyNew()

    local isDialogCall = (type(arg5) == "table") or (type(arg1) == "number" and type(arg5) ~= "number" and type(arg5) ~= "boolean")

    if isDialogCall then
        self.farmId = arg1 or 0
        self.barn = arg2
        self.trailer = arg3
        self.amount = arg4 or 0
        self.isResult = false
        self.newFillLevel = 0
        print(string.format("[PR Butcher Fix] Event created (REQUEST) farm=%d amount=%d", self.farmId, self.amount))
    else
        self.farmId = 0
        self.barn = arg1
        self.trailer = arg2
        self.amount = tonumber(arg3) or 0
        self.isResult = (arg4 == true)
        self.newFillLevel = tonumber(arg5) or 0
        print(string.format("[PR Butcher Fix] Event created (RESULT) amount=%d newFill=%.2f", self.amount, self.newFillLevel))
    end

    return self
end

function PR_DeliverAnimalsEvent:readStream(streamId, connection)
    self.farmId = streamReadUInt8(streamId)
    self.barn = NetworkUtil.readNodeObject(streamId)
    self.trailer = NetworkUtil.readNodeObject(streamId)
    self.amount = streamReadUInt16(streamId)
    self.isResult = streamReadBool(streamId)
    self.newFillLevel = streamReadFloat32(streamId)
    print(string.format("[PR Butcher Fix] Event.readStream isResult=%s amount=%d newFill=%.2f barn=%s trailer=%s",
        tostring(self.isResult), self.amount, self.newFillLevel or 0,
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
end

function PR_DeliverAnimalsEvent:run(connection)
    print(string.format("[PR Butcher Fix] Event.run isResult=%s amount=%d newFill=%.2f", tostring(self.isResult), self.amount, self.newFillLevel or 0))

    if self.isResult then
        if self.trailer ~= nil and PRBFix ~= nil and PRBFix.applyDeliveryResult ~= nil then
            PRBFix:applyDeliveryResult(self.trailer, nil, self.amount)
        end

        if self.newFillLevel ~= nil and self.newFillLevel > 0 and PRBFix ~= nil then
            local barn = self.barn
            if barn == nil then
                barn = PRBFix.butcherBarnPlaceable
            end

            if barn ~= nil then
                local spec = barn.spec_extendedProductionPoint
                if spec ~= nil and spec.productionPoint ~= nil and spec.productionPoint.storage ~= nil then
                    local st = spec.productionPoint.storage
                    local ftIdx = g_fillTypeManager:getFillTypeIndexByName("CHICKEN")
                    if ftIdx ~= nil then
                        st:setFillLevel(self.newFillLevel, ftIdx)
                        print(string.format("[PR Butcher Fix] Client forced CHICKEN fill to %.2f", self.newFillLevel))
                    else
                        print("[PR Butcher Fix] Client could not find CHICKEN fill type index")
                    end
                else
                    print("[PR Butcher Fix] Client missing extendedProductionPoint / storage")
                end
            else
                print("[PR Butcher Fix] Client has no barn reference at all")
            end
        end
    else
        if g_server ~= nil and PRBFix ~= nil and self.trailer ~= nil then
            local animalType = self.trailer:getCurrentAnimalType()
            local typeName = (animalType and animalType.name) or "CHICKEN"
            local validCount, validClusters = PRBFix:countValidAnimals(self.trailer, typeName)
            local data = { type = typeName, validClusters = validClusters, validCount = validCount }
            print(string.format("[PR Butcher Fix] Server processing request: type=%s valid=%d amount=%d", typeName, validCount, self.amount))
            PRBFix:deliverAnimals(self.trailer, data, self.amount)
        else
            print("[PR Butcher Fix] Event.run request skipped (no server, no PRBFix, or no trailer)")
        end
    end
end

function PR_DeliverAnimalsEvent.send(...)
    local event = PR_DeliverAnimalsEvent.new(...)
    if g_server ~= nil then
        print("[PR Butcher Fix] Broadcasting event from server")
        g_server:broadcastEvent(event)
    else
        print("[PR Butcher Fix] Sending event from client to server")
        g_client:getServerConnection():sendEvent(event)
    end
end