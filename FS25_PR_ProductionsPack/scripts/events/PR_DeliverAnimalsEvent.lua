-- PR_DeliverAnimalsEvent.lua

PR_DeliverAnimalsEvent = {}
local PR_DeliverAnimalsEvent_mt = Class(PR_DeliverAnimalsEvent, Event)
InitEventClass(PR_DeliverAnimalsEvent, "PR_DeliverAnimalsEvent")

function PR_DeliverAnimalsEvent.emptyNew()
    local self = Event.new(PR_DeliverAnimalsEvent_mt)
    return self
end

-- Accepts both call styles:
--   send(farmId, barn, trailer, amount, isResult)
--   send(farmId, barn, trailer, amount, data, isResult)
function PR_DeliverAnimalsEvent.new(farmId, barn, trailer, amount, dataOrIsResult, isResult)
    local self = PR_DeliverAnimalsEvent.emptyNew()
    self.farmId = farmId or 0
    self.barn = barn
    self.trailer = trailer
    self.amount = amount or 0

    -- Figure out which argument is the bool
    if type(dataOrIsResult) == "boolean" then
        self.isResult = dataOrIsResult
    else
        self.isResult = isResult or false
    end

    return self
end

function PR_DeliverAnimalsEvent:readStream(streamId, connection)
    self.farmId = streamReadUInt8(streamId)
    self.barn = NetworkUtil.readNodeObject(streamId)
    self.trailer = NetworkUtil.readNodeObject(streamId)
    self.amount = streamReadUInt16(streamId)
    self.isResult = streamReadBool(streamId)
    self:run(connection)
end

function PR_DeliverAnimalsEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.farmId)
    NetworkUtil.writeNodeObject(streamId, self.barn)
    NetworkUtil.writeNodeObject(streamId, self.trailer)
    streamWriteUInt16(streamId, self.amount)
    streamWriteBool(streamId, self.isResult == true)  -- force a real bool
end

-- function PR_DeliverAnimalsEvent:run(connection)
    -- if self.barn == nil or self.trailer == nil then
        -- print("[PR Butcher Fix] Event.run: barn or trailer is nil")
        -- return
    -- end

    -- print(string.format("[PR Butcher Fix] Event.run: isResult=%s amount=%d", 
        -- tostring(self.isResult), self.amount))

    -- if self.isResult then
        -- -- Clients apply the result
        -- if self.barn.getOwner ~= nil and self.barn:getOwner() ~= nil then
            -- self.barn:getOwner():applyDeliveryResult(self.trailer, nil, self.amount)
        -- end
    -- else
        -- -- Server does the real delivery
        -- if g_server ~= nil then
            -- if self.barn.getOwner ~= nil and self.barn:getOwner() ~= nil then
                -- local owner = self.barn:getOwner()

                -- local animalType = self.trailer:getCurrentAnimalType()
                -- local typeName = (animalType and animalType.name) or "CHICKEN"

                -- local validCount, validClusters = owner:countValidAnimals(self.trailer, typeName)
                -- local data = {
                    -- type = typeName,
                    -- validClusters = validClusters,
                    -- validCount = validCount
                -- }

                -- print(string.format("[PR Butcher Fix] Server rebuilt data: type=%s valid=%d", typeName, validCount))
                -- owner:deliverAnimals(self.trailer, data, self.amount)
            -- end
        -- end
    -- end
-- end
function PR_DeliverAnimalsEvent:run(connection)
    if self.barn == nil or self.trailer == nil then
        print("[PR Butcher Fix] Event.run: barn or trailer is nil")
        return
    end

    print(string.format("[PR Butcher Fix] Event.run: isResult=%s amount=%d", 
        tostring(self.isResult), self.amount))

    if self.isResult then
        -- Clients apply the result
        if PRBFix ~= nil and PRBFix.applyDeliveryResult ~= nil then
            PRBFix:applyDeliveryResult(self.trailer, nil, self.amount)
        end

        -- Nudge the barn placeable so production storage updates on clients
        if self.barn ~= nil and self.barn.raiseDirtyFlags ~= nil then
            self.barn:raiseDirtyFlags(self.barn.placeableDirtyFlag or 1)
        end
    else
        -- Server does the real delivery
        if g_server ~= nil and PRBFix ~= nil then
            local animalType = self.trailer:getCurrentAnimalType()
            local typeName = (animalType and animalType.name) or "CHICKEN"

            local validCount, validClusters = PRBFix:countValidAnimals(self.trailer, typeName)
            local data = {
                type = typeName,
                validClusters = validClusters,
                validCount = validCount
            }

            print(string.format("[PR Butcher Fix] Server rebuilt data: type=%s valid=%d", typeName, validCount))
            PRBFix:deliverAnimals(self.trailer, data, self.amount)
        end
    end
end

-- Accepts both call styles
function PR_DeliverAnimalsEvent.send(farmId, barn, trailer, amount, dataOrIsResult, isResult)
    local event = PR_DeliverAnimalsEvent.new(farmId, barn, trailer, amount, dataOrIsResult, isResult)
    if g_server ~= nil then
        g_server:broadcastEvent(event)
    else
        g_client:getServerConnection():sendEvent(event)
    end
end