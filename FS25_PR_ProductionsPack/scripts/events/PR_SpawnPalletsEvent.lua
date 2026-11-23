-- PR_SpawnPalletsEvent.lua

PR_SpawnPalletsEvent = {}
local PR_SpawnPalletsEvent_mt = Class(PR_SpawnPalletsEvent, Event)

InitEventClass(PR_SpawnPalletsEvent, "PR_SpawnPalletsEvent")

function PR_SpawnPalletsEvent.emptyNew()
    return Event.new(PR_SpawnPalletsEvent_mt)
end

function PR_SpawnPalletsEvent.new(fillTypes, farmId)
    local self = PR_SpawnPalletsEvent.emptyNew()
    self.fillTypes = fillTypes
    self.farmId = farmId
    return self
end

function PR_SpawnPalletsEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, #self.fillTypes)
    for _, ft in ipairs(self.fillTypes) do
        streamWriteString(streamId, ft)
    end
    streamWriteUInt8(streamId, self.farmId)
end

function PR_SpawnPalletsEvent:readStream(streamId, connection)
    local count = streamReadUInt8(streamId)
    self.fillTypes = {}
    for i = 1, count do
        self.fillTypes[i] = streamReadString(streamId)
    end
    self.farmId = streamReadUInt8(streamId)
    self:run(connection)
end

function PR_SpawnPalletsEvent:run(connection)
    if g_server and PRBFix and PRBFix.handleSpawnRequest then
        PRBFix:handleSpawnRequest(self.fillTypes, self.farmId)
    end
end