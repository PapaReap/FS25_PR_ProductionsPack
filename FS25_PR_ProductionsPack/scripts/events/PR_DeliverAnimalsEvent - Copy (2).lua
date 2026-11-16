-- -- scripts/events/PR_DeliverAnimalsEvent.lua
-- -- Network event so the SERVER performs the actual animal delivery.
-- -- Works in SP (runs locally) and MP (client → server).

-- PR_DeliverAnimalsEvent = {}
-- local PR_DeliverAnimalsEvent_mt = Class(PR_DeliverAnimalsEvent, Event)

-- InitEventClass(PR_DeliverAnimalsEvent, "PR_DeliverAnimalsEvent")

-- ------------------------------------------------------------
-- -- Constructors
-- ------------------------------------------------------------
-- function PR_DeliverAnimalsEvent.emptyNew()
    -- local self = Event.new(PR_DeliverAnimalsEvent_mt)
    -- return self
-- end

-- --- farmId is just informational for now, but we keep it if we ever want farm checks.
-- function PR_DeliverAnimalsEvent.new(farmId, barn, trailer, amount, animalType, validClusters)
    -- local self = PR_DeliverAnimalsEvent.emptyNew()
    -- self.farmId        = farmId or 0
    -- self.barn          = barn
    -- self.trailer       = trailer
    -- self.amount        = amount or 0
    -- self.animalType    = animalType or "UNKNOWN"
    -- self.validClusters = validClusters or {}
    -- return self
-- end

-- ------------------------------------------------------------
-- -- Stream (MP sync)
-- ------------------------------------------------------------
-- function PR_DeliverAnimalsEvent:writeStream(streamId, connection)
    -- -- barn & trailer are placeable/vehicle objects
    -- NetworkUtil.writeNodeObject(streamId, self.barn)
    -- NetworkUtil.writeNodeObject(streamId, self.trailer)

    -- streamWriteInt32(streamId, self.farmId or 0)
    -- streamWriteString(streamId, self.animalType or "UNKNOWN")
    -- streamWriteUInt16(streamId, math.max(0, self.amount or 0))

    -- local num = 0
    -- if self.validClusters ~= nil then
        -- num = #self.validClusters
    -- end
    -- if num > 255 then
        -- num = 255 -- safety clamp; nobody is moving 255 animals in one trailer anyway
    -- end

    -- streamWriteUIntN(streamId, num, 8)
    -- for i = 1, num do
        -- local idx = self.validClusters[i] or 0
        -- -- cluster indices are small; 16 bits is plenty
        -- streamWriteUIntN(streamId, idx, 16)
    -- end
-- end

-- function PR_DeliverAnimalsEvent:readStream(streamId, connection)
    -- self.barn    = NetworkUtil.readNodeObject(streamId)
    -- self.trailer = NetworkUtil.readNodeObject(streamId)

    -- self.farmId     = streamReadInt32(streamId)
    -- self.animalType = streamReadString(streamId)
    -- self.amount     = streamReadUInt16(streamId)

    -- local num = streamReadUIntN(streamId, 8)
    -- self.validClusters = {}
    -- for i = 1, num do
        -- self.validClusters[i] = streamReadUIntN(streamId, 16)
    -- end

    -- self:run(connection)
-- end

-- ------------------------------------------------------------
-- -- Run on server
-- ------------------------------------------------------------
-- -- function PR_DeliverAnimalsEvent:run(connection)
    -- -- -- Only the server performs the actual delivery logic
    -- -- if g_server == nil then
		-- -- print("[PR Butcher Fix] ❌ g_server is not you")
        -- -- return
    -- -- end

    -- -- -- Validate incoming data
    -- -- if self.barnPlaceable == nil or self.trailer == nil then
        -- -- print(string.format("[%s] ❌ PR_DeliverAnimalsEvent: barnPlaceable or trailer is nil on server",
            -- -- PRBFix and PRBFix.modName or "PR Butcher Fix"))
        -- -- return
    -- -- end

    -- -- if PRBFix == nil or PRBFix.deliverAnimals == nil then
        -- -- print("[PR Butcher Fix] ❌ PRBFix or PRBFix.deliverAnimals missing on server")
        -- -- return
    -- -- end

    -- -- ------------------------------------------------------------
    -- -- -- Reconstruct minimal data table for server-side processing
    -- -- -- deliverAnimals() only needs:
    -- -- --   • data.type
    -- -- --   • data.validClusters
    -- -- ------------------------------------------------------------
    -- -- local data = {
        -- -- type          = self.animalType or "UNKNOWN",
        -- -- validClusters = self.validClusters or {}
    -- -- }

    -- -- ------------------------------------------------------------
    -- -- -- Run the server-side delivery (weight, quality, capacity,
    -- -- -- liters, cluster removal — all done inside deliverAnimals)
    -- -- ------------------------------------------------------------
    -- -- PRBFix:deliverAnimals(self.trailer, data, self.amount)
-- -- end
-- ------------------------------------------------------------
-- -- Run on server
-- ------------------------------------------------------------
-- function PR_DeliverAnimalsEvent:run(connection)
    -- -- Only the server performs the actual delivery logic
    -- if g_server == nil then
        -- print("[PR Butcher Fix] ❌ PR_DeliverAnimalsEvent.run called but g_server is nil")
        -- return
    -- end

    -- --------------------------------------------------------
    -- -- Validate barn and trailer (correct field names!)
    -- --------------------------------------------------------
    -- if self.barn == nil then
        -- print("[PR Butcher Fix] ❌ Event.run: barn is NIL on server")
    -- else
        -- print(string.format("[PR Butcher Fix] Event.run: barn OK (nodeId=%s)",
            -- tostring(self.barn.nodeId)))
    -- end

    -- if self.trailer == nil then
        -- print("[PR Butcher Fix] ❌ Event.run: trailer is NIL on server")
    -- else
        -- print(string.format("[PR Butcher Fix] Event.run: trailer OK (rootNode=%s)",
            -- tostring(self.trailer.rootNode)))
    -- end

    -- if self.barn == nil or self.trailer == nil then
        -- print("[PR Butcher Fix] ❌ PR_DeliverAnimalsEvent: barn or trailer is nil on server")
        -- return
    -- end

    -- if PRBFix == nil or PRBFix.deliverAnimals == nil then
        -- print("[PR Butcher Fix] ❌ PRBFix or PRBFix.deliverAnimals missing on server")
        -- return
    -- end

    -- --------------------------------------------------------
    -- -- Reconstruct minimal data table for server processing
    -- --------------------------------------------------------
    -- local data = {
        -- type          = self.animalType or "UNKNOWN",
        -- validClusters = self.validClusters or {}
    -- }

    -- --------------------------------------------------------
    -- -- Perform delivery (cluster removal, liters, quality, etc.)
    -- --------------------------------------------------------
    -- print(string.format("[PR Butcher Fix] ▶ Server delivering %d animals of type '%s'",
        -- self.amount, tostring(self.animalType)))

    -- PRBFix:deliverAnimals(self.trailer, data, self.amount)
-- end



-- ------------------------------------------------------------
-- -- Helper: send (SP + MP safe)
-- ------------------------------------------------------------
-- -- function PR_DeliverAnimalsEvent.send(farmId, barn, trailer, amount, data)
    -- -- if barn == nil or trailer == nil then
        -- -- print("[PR Butcher Fix] ⚠ PR_DeliverAnimalsEvent.send called with nil barn or trailer")
        -- -- return
    -- -- end

    -- -- local animalType    = "UNKNOWN"
    -- -- local validClusters = {}

    -- -- if data ~= nil then
        -- -- animalType    = data.type or data.animalType or animalType
        -- -- validClusters = data.validClusters or validClusters
    -- -- end

    -- -- local event = PR_DeliverAnimalsEvent.new(farmId, barn, trailer, amount, animalType, validClusters)

    -- -- -- SP or MP host: server is local → just run immediately
    -- -- if g_server ~= nil then
        -- -- event:run(nil)
    -- -- -- Remote client: send to dedicated / host server
    -- -- elseif g_client ~= nil then
        -- -- g_client:getServerConnection():sendEvent(event)
    -- -- else
        -- -- -- Very weird situation, but just log and bail
        -- -- print("[PR Butcher Fix] ⚠ No g_server or g_client in PR_DeliverAnimalsEvent.send")
    -- -- end
-- -- end
-- ------------------------------------------------------------
-- -- Helper: send (Multiplayer-safe network routing)
-- ------------------------------------------------------------
-- function PR_DeliverAnimalsEvent.send(farmId, barn, trailer, amount, data)
    -- if barn == nil or trailer == nil then
        -- print("[PR Butcher Fix] ⚠ PR_DeliverAnimalsEvent.send called with nil barn or trailer")
        -- return
    -- end

    -- local animalType    = "UNKNOWN"
    -- local validClusters = {}

    -- if data ~= nil then
        -- animalType    = data.type or data.animalType or animalType
        -- validClusters = data.validClusters or validClusters
    -- end

    -- local event = PR_DeliverAnimalsEvent.new(farmId, barn, trailer, amount, animalType, validClusters)

    -- -- If we are a client connected to a server (even self-hosted host/client), 
    -- -- send the event through the network connection so the server executes it authoritatively.
    -- if g_client ~= nil then
        -- g_client:getServerConnection():sendEvent(event)
    -- elseif g_server ~= nil then
        -- -- Pure singleplayer fallback where client/server are strictly one
        -- event:run(nil)
    -- else
        -- print("[PR Butcher Fix] ⚠ No g_server or g_client in PR_DeliverAnimalsEvent.send")
    -- end
-- end

PR_DeliverAnimalsEvent = {}
local PR_DeliverAnimalsEvent_mt = Class(PR_DeliverAnimalsEvent, Event)
InitEventClass(PR_DeliverAnimalsEvent, "PR_DeliverAnimalsEvent")

function PR_DeliverAnimalsEvent.emptyNew()
    local self = Event.new(PR_DeliverAnimalsEvent_mt)
    return self
end

function PR_DeliverAnimalsEvent.new(barn, trailer, animalType, count, farmId, isResult)
    local self = PR_DeliverAnimalsEvent.emptyNew()
    self.barn = barn
    self.trailer = trailer
    self.animalType = animalType
    self.count = count
    self.farmId = farmId or 0
    self.isResult = isResult or false
    return self
end

function PR_DeliverAnimalsEvent:readStream(streamId, connection)
    self.barn = NetworkUtil.readNodeObject(streamId)
    self.trailer = NetworkUtil.readNodeObject(streamId)
    self.animalType = streamReadUInt8(streamId)
    self.count = streamReadUInt16(streamId)
    self.farmId = streamReadUInt8(streamId)
    self.isResult = streamReadBool(streamId)
    self:run(connection)
end

function PR_DeliverAnimalsEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.barn)
    NetworkUtil.writeNodeObject(streamId, self.trailer)
    streamWriteUInt8(streamId, self.animalType)
    streamWriteUInt16(streamId, self.count)
    streamWriteUInt8(streamId, self.farmId)
    streamWriteBool(streamId, self.isResult)
end

function PR_DeliverAnimalsEvent:run(connection)
    if self.barn == nil or self.trailer == nil then
        print("[PR Butcher Fix] Event.run: barn or trailer is nil")
        return
    end

    print(string.format("[PR Butcher Fix] Event.run: barn OK (nodeId=%s) isResult=%s", 
        tostring(self.barn.nodeId), tostring(self.isResult)))

    if self.isResult then
        -- Clients apply the delivery result
        if self.barn.getOwner ~= nil and self.barn:getOwner() ~= nil then
            self.barn:getOwner():applyDeliveryResult(self.trailer, self.animalType, self.count)
        end
    else
        -- Client → Server request (original path)
        if g_server ~= nil then
            if self.barn.getOwner ~= nil and self.barn:getOwner() ~= nil then
                self.barn:getOwner():deliverAnimals(self.trailer, self.barn, self.animalType, self.count)
            end
        end
    end
end

function PR_DeliverAnimalsEvent.sendEvent(barn, trailer, animalType, count, farmId, isResult)
    local event = PR_DeliverAnimalsEvent.new(barn, trailer, animalType, count, farmId, isResult)
    if g_server ~= nil then
        g_server:broadcastEvent(event)
    else
        g_client:getServerConnection():sendEvent(event)
    end
end