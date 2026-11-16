PlaneAnimator = {}
print("PR PlaneAnimator: started")
function PlaneAnimator.prerequisitesPresent(specializations)
    return true
end

function PlaneAnimator.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "loadVisualPlanes", PlaneAnimator.loadVisualPlanes)
end

function PlaneAnimator.registerOverwrittenFunctions(placeableType)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "finalizePlacement", PlaneAnimator.finalizePlacement)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "update", PlaneAnimator.update)
end

function PlaneAnimator:loadVisualPlanes()
    self._animatedPlanes = {}

    local function addPlane(name, fillTypeName, minY, maxY)
    local mapping = self:getI3dMapping(name)
    if mapping ~= nil then
        local node = mapping.node
        local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)

        if node ~= nil and fillTypeIndex ~= nil then
            setVisibility(node, false)
            table.insert(self._animatedPlanes, {
                node = node,
                fillType = fillTypeIndex,
                minY = minY,
                maxY = maxY,
                visible = false
            })
        end
    else
        Logging.warning("PlaneAnimator: Node mapping '%s' not found", name)
    end
end

    -- Add only if node is present
    addPlane("waterPlane", "WATER", -0.682, 0.0)
    addPlane("crawfishPlane01", "CRAWFISH", -0.318, 0.0)
end

function PlaneAnimator:finalizePlacement(superFunc)
	print("PR PlaneAnimator: FinalizePlacement Loaded")
    if superFunc ~= nil then
        superFunc(self)
    end

    if self.isClient then
        self:loadVisualPlanes()
    end
end

function PlaneAnimator:update(superFunc, dt)
	print("PR PlaneAnimator: update")
    if superFunc ~= nil then
        superFunc(self, dt)
    end

    if self.isClient and self._animatedPlanes ~= nil then
        for _, plane in ipairs(self._animatedPlanes) do
            local fillLevel = self:getFillLevel(plane.fillType)
            local capacity = self:getCapacity(plane.fillType)

            if capacity > 0 then
                local percent = math.min(math.max(fillLevel / capacity, 0), 1)
                local y = plane.minY + (plane.maxY - plane.minY) * percent

                local x, _, z = getTranslation(plane.node)
                setTranslation(plane.node, x, y, z)

                local show = fillLevel > 1
                if show ~= plane.visible then
                    setVisibility(plane.node, show)
                    plane.visible = show
                end
            end
        end
    end
end
