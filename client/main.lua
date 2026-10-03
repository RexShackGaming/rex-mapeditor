lib.locale()

local menuOpen = false
local hasAccess = false     -- set by the server (lib.callback); UX gate only, server re-checks everything
local placedProps = {}      -- [localId] = { entity, model, id (persisted id or nil), x,y,z,rx,ry,rz }
local currentMap = 'default'
local nextLocalId = 1

local grabbed = nil         -- prop being positioned: { entity, model, x,y,z,rx,ry,rz, localId }
local grabbedTick = nil

local confirmGrabbed, cancelGrabbed, clearImapRemovals -- forward declarations

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
local function notify(msg, nType)
    lib.notify({
        title = locale('menu_title'),
        description = msg,
        type = nType or 'inform',
        duration = 5000,
    })
end

RegisterNetEvent('rex-mapeditor:client:notify', notify)

-- Push every ui_* locale string to the NUI (html/app.js applies them).
local function sendNuiLocales()
    local strings = {}
    for key, value in pairs(lib.getLocales and lib.getLocales() or {}) do
        if key:sub(1, 3) == 'ui_' then strings[key] = value end
    end
    SendNUIMessage({ action = 'locales', locales = strings })
end

local function refreshAccess()
    hasAccess = lib.callback.await('rex-mapeditor:server:hasAccess', false) == true
    return hasAccess
end

-- ---------------------------------------------------------------------
-- RedM controls (named RDR3 INPUT_* hashes - GTA V numeric ids don't map)
-- https://github.com/femga/rdr3_discoveries/blob/master/Controls/README.md
-- ---------------------------------------------------------------------
local Controls = {
    FRONTEND_UP     = `INPUT_FRONTEND_UP`,      -- Arrow Up
    FRONTEND_DOWN   = `INPUT_FRONTEND_DOWN`,    -- Arrow Down
    FRONTEND_LEFT   = `INPUT_FRONTEND_LEFT`,    -- Arrow Left
    FRONTEND_RIGHT  = `INPUT_FRONTEND_RIGHT`,   -- Arrow Right
    RAISE           = `INPUT_CREATOR_LT`,       -- Page Up
    LOWER           = `INPUT_CREATOR_RT`,       -- Page Down
    ROTATE_LEFT     = `INPUT_FRONTEND_LB`,      -- Q
    ROTATE_RIGHT    = `INPUT_FRONTEND_RB`,      -- E
    PITCH_DOWN      = `INPUT_SNIPER_ZOOM_OUT_ONLY`, -- [
    PITCH_UP        = `INPUT_SNIPER_ZOOM_IN_ONLY`,  -- ]
    CONFIRM         = `INPUT_FRONTEND_ACCEPT`,  -- Enter
    CANCEL          = `INPUT_FRONTEND_CANCEL`,  -- Backspace / Esc
    DELETE_AIMED    = `INPUT_FRONTEND_DELETE`,  -- Delete
    SPRINT          = `INPUT_SPRINT`,           -- Shift (fast modifier)
    ATTACK          = `INPUT_ATTACK`,
    AIM             = `INPUT_AIM`,
    MELEE_ATTACK    = `INPUT_MELEE_ATTACK`,
}

-- Disabled every frame while placing so the character stays put. Q and E
-- share several other actions in RDR3 (cover, dive, grapple, eat...), which
-- is why those are listed too.
local FROZEN_MODE_CONTROLS = {
    `INPUT_LOOK_LR`, `INPUT_LOOK_UD`,
    `INPUT_MOVE_LR`, `INPUT_MOVE_UD`,
    `INPUT_MOVE_LEFT_ONLY`, `INPUT_MOVE_RIGHT_ONLY`, `INPUT_MOVE_UP_ONLY`, `INPUT_MOVE_DOWN_ONLY`,
    `INPUT_JUMP`, `INPUT_ATTACK`, `INPUT_ATTACK2`, `INPUT_MELEE_ATTACK`,
    `INPUT_RELOAD`, `INPUT_AIM`, `INPUT_CONTEXT`, `INPUT_ENTER`,
    `INPUT_WHISTLE_HORSEBACK`, `INPUT_SELECT_WEAPON`, `INPUT_DUCK`,
    `INPUT_COVER`, `INPUT_DIVE`, `INPUT_SPECIAL_ABILITY_ACTION`,
    `INPUT_INTERACT_LOCKON_STUDY_BINOCULARS`, `INPUT_INTERACT_LOCKON_TARGET_INFO`,
    `INPUT_MELEE_GRAPPLE`, `INPUT_MELEE_GRAPPLE_CHOKE`, `INPUT_CRAFTING_EAT`, `INPUT_INTERACT_LOCKON_Y`,
    Controls.FRONTEND_UP, Controls.FRONTEND_DOWN, Controls.FRONTEND_LEFT, Controls.FRONTEND_RIGHT,
    Controls.RAISE, Controls.LOWER, Controls.ROTATE_LEFT, Controls.ROTATE_RIGHT,
    Controls.PITCH_DOWN, Controls.PITCH_UP,
}

-- Accepts a model name, or a numeric hash typed as text.
local function loadModel(model)
    local hash = tonumber(model) or (type(model) == 'string' and joaat(model)) or nil
    if not hash or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(50)
    end
    return HasModelLoaded(hash) and hash or nil
end

local function rotationToDirection(rot)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local cx = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * cx, math.cos(rz) * cx, math.sin(rx))
end

-- Raycast forward from the gameplay camera.
local function getAimCoords(maxDistance)
    local camCoords = GetGameplayCamCoord()
    local dest = camCoords + rotationToDirection(GetGameplayCamRot(2)) * maxDistance
    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, dest.x, dest.y, dest.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords, _, entityHit = GetShapeTestResult(ray)
    if hit == 1 then return endCoords, entityHit end
    return dest, 0
end

local function createPlacedObject(hash, x, y, z, rx, ry, rz)
    local entity = CreateObject(hash, x, y, z, true, true, false)
    SetEntityRotation(entity, rx or 0.0, ry or 0.0, rz or 0.0, 2, true)
    FreezeEntityPosition(entity, true)
    SetEntityAsMissionEntity(entity, true, true)
    SetModelAsNoLongerNeeded(hash)
    return entity
end

local function deletePlacedEntities()
    for _, data in pairs(placedProps) do
        if DoesEntityExist(data.entity) then DeleteEntity(data.entity) end
    end
    placedProps = {}
end

local function refreshEntityList()
    local list = {}
    for localId, d in pairs(placedProps) do
        list[#list + 1] = { localId = localId, id = d.id, model = d.model, x = d.x, y = d.y, z = d.z }
    end
    table.sort(list, function(a, b) return a.localId < b.localId end)
    SendNUIMessage({ action = 'refreshList', props = list, mapname = currentMap })
end

-- ---------------------------------------------------------------------
-- Placement adjustment (shared by keybinds AND the Placement Panel NUI)
-- ---------------------------------------------------------------------
local function updateGrabbedEntity()
    SetEntityCoordsNoOffset(grabbed.entity, grabbed.x, grabbed.y, grabbed.z, true, true, true)
    SetEntityRotation(grabbed.entity, grabbed.rx, grabbed.ry, grabbed.rz, 2, true)
end

local function nudgeGrabbed(direction, fast)
    if not grabbed then return end
    local step = fast and Config.MoveStepFast or Config.MoveStep
    local rad = math.rad(GetGameplayCamRot(2).z)
    local fx, fy = -math.sin(rad), math.cos(rad) -- camera forward
    local rx, ry = math.cos(rad), math.sin(rad)  -- camera right
    if direction == 'up' then
        grabbed.x, grabbed.y = grabbed.x + fx * step, grabbed.y + fy * step
    elseif direction == 'down' then
        grabbed.x, grabbed.y = grabbed.x - fx * step, grabbed.y - fy * step
    elseif direction == 'left' then
        grabbed.x, grabbed.y = grabbed.x - rx * step, grabbed.y - ry * step
    elseif direction == 'right' then
        grabbed.x, grabbed.y = grabbed.x + rx * step, grabbed.y + ry * step
    else
        return
    end
    updateGrabbedEntity()
end

local function heightGrabbed(direction, fast)
    if not grabbed then return end
    local step = fast and (Config.HeightStepFast or Config.HeightStep) or Config.HeightStep
    if direction == 'up' then grabbed.z = grabbed.z + step
    elseif direction == 'down' then grabbed.z = grabbed.z - step
    else return end
    updateGrabbedEntity()
end

local function rotateGrabbed(direction, fast)
    if not grabbed then return end
    local step = fast and Config.RotateStepFast or Config.RotateStep
    if direction == 'left' then grabbed.rz = (grabbed.rz - step) % 360
    elseif direction == 'right' then grabbed.rz = (grabbed.rz + step) % 360
    else return end
    updateGrabbedEntity()
end

local function pitchGrabbed(direction, fast)
    if not grabbed then return end
    local step = fast and Config.RotateStepFast or Config.RotateStep
    if direction == 'down' then grabbed.rx = (grabbed.rx - step) % 360
    elseif direction == 'up' then grabbed.rx = (grabbed.rx + step) % 360
    else return end
    updateGrabbedEntity()
end

local function startGrabbedTick()
    if grabbedTick then return end
    grabbedTick = true
    CreateThread(function()
        while grabbed do
            Wait(0)
            for i = 1, #FROZEN_MODE_CONTROLS do
                DisableControlAction(0, FROZEN_MODE_CONTROLS[i], true)
            end

            local fast = IsControlPressed(0, Controls.SPRINT) or IsDisabledControlPressed(0, Controls.SPRINT)

            if IsDisabledControlPressed(0, Controls.FRONTEND_UP) then nudgeGrabbed('up', fast) end
            if IsDisabledControlPressed(0, Controls.FRONTEND_DOWN) then nudgeGrabbed('down', fast) end
            if IsDisabledControlPressed(0, Controls.FRONTEND_LEFT) then nudgeGrabbed('left', fast) end
            if IsDisabledControlPressed(0, Controls.FRONTEND_RIGHT) then nudgeGrabbed('right', fast) end
            if IsDisabledControlPressed(0, Controls.RAISE) then heightGrabbed('up', fast) end
            if IsDisabledControlPressed(0, Controls.LOWER) then heightGrabbed('down', fast) end
            if IsDisabledControlPressed(0, Controls.ROTATE_LEFT) then rotateGrabbed('left', fast) end
            if IsDisabledControlPressed(0, Controls.ROTATE_RIGHT) then rotateGrabbed('right', fast) end
            if IsDisabledControlPressed(0, Controls.PITCH_DOWN) then pitchGrabbed('down', fast) end
            if IsDisabledControlPressed(0, Controls.PITCH_UP) then pitchGrabbed('up', fast) end

            -- Frontend accept/cancel are disabled outside menus, so read the
            -- "Disabled" variant.
            if IsDisabledControlJustPressed(0, Controls.CONFIRM) then
                confirmGrabbed()
            elseif IsDisabledControlJustPressed(0, Controls.CANCEL) then
                cancelGrabbed()
            end
        end
        grabbedTick = nil
    end)
end

-- Placement Panel: SetNuiFocusKeepInput lets the game keep receiving input
-- while the small NUI panel is clickable, so keys and clicks can be mixed.
local function showPlacementControlsUI(model)
    SendNUIMessage({ action = 'showPlacement', model = model })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
end

local function hidePlacementControlsUI()
    SendNUIMessage({ action = 'hidePlacement' })
    SetNuiFocusKeepInput(false)
    if menuOpen then
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'show' })
    else
        SetNuiFocus(false, false)
    end
end

-- Freeze the ped and revoke player control while placing; this also stops
-- RDR3's idle/ambient and "hold to rest" scenario prompts from firing.
local function freezePlayerForPlacement(freeze)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, freeze)
    SetPedCanPlayAmbientAnims(ped, not freeze)
    SetPedCanPlayGestureAnims(ped, not freeze)
    SetPedCanPlayAmbientBaseAnims(ped, not freeze)
    SetBlockingOfNonTemporaryEvents(ped, freeze)
    if freeze then ClearPedTasksImmediately(ped) end
    SetPlayerControl(PlayerId(), not freeze, 0)
end

local function endPlacement()
    grabbed = nil
    freezePlayerForPlacement(false)
    hidePlacementControlsUI()
end

confirmGrabbed = function()
    if not grabbed then return end
    local g = grabbed
    placedProps[g.localId] = {
        entity = g.entity, model = g.model,
        x = g.x, y = g.y, z = g.z, rx = g.rx, ry = g.ry, rz = g.rz,
    }
    endPlacement()
    notify(locale('prop_placed'), 'success')
    refreshEntityList()
end

cancelGrabbed = function()
    if not grabbed then return end
    if DoesEntityExist(grabbed.entity) then DeleteEntity(grabbed.entity) end
    endPlacement()
    notify(locale('placement_cancelled'), 'warning')
end

-- ---------------------------------------------------------------------
-- Spawning / deleting placed props
-- ---------------------------------------------------------------------
local function spawnProp(model)
    if grabbed or not hasAccess then return end
    model = tostring(model or ''):gsub('%s+', '')
    if model == '' then return end

    local hash = loadModel(model)
    if not hash then
        notify(locale('invalid_model', model), 'error')
        return
    end

    local coords = getAimCoords(Config.MaxRaycastDistance)
    local localId = nextLocalId
    nextLocalId = nextLocalId + 1

    grabbed = {
        entity = createPlacedObject(hash, coords.x, coords.y, coords.z),
        model = model,
        x = coords.x, y = coords.y, z = coords.z,
        rx = 0.0, ry = 0.0, rz = 0.0,
        localId = localId,
    }

    -- Hide the main menu while placing; it comes back on confirm/cancel.
    SendNUIMessage({ action = 'hide' })
    freezePlayerForPlacement(true)
    showPlacementControlsUI(model)
    startGrabbedTick()
end

local function removePropByLocalId(localId)
    local data = placedProps[localId]
    if not data then return end
    if DoesEntityExist(data.entity) then DeleteEntity(data.entity) end
    if data.id then
        TriggerServerEvent('rex-mapeditor:server:removeProp', currentMap, data.id)
    end
    placedProps[localId] = nil
    refreshEntityList()
end

local function teleportToLocalId(localId)
    local data = placedProps[localId]
    if not data then return end
    SetEntityCoords(PlayerPedId(), data.x, data.y, data.z + 1.0, false, false, false, false)
end

-- ---------------------------------------------------------------------
-- Removing EXISTING base-game world props (runtime removal list, see README)
-- ---------------------------------------------------------------------
local REMOVAL_MATCH_RADIUS = Config.RemovalMatchRadius or 1.5
local HIDE_RADIUS = Config.ModelHideRadius or 1.5
local ENFORCE_DISTANCE = 300.0 -- only re-check removals near the player
local activeRemovals = {} -- { model, x, y, z, coords }
local activeHides = {}    -- { model, x, y, z }

local function isSameRemoval(a, model, x, y, z)
    if a.model ~= model then return false end
    local dx, dy, dz = a.x - x, a.y - y, a.z - z
    return (dx * dx + dy * dy + dz * dz) <= REMOVAL_MATCH_RADIUS * REMOVAL_MATCH_RADIUS
end

local function deleteMatchingWorldEntity(model, x, y, z)
    local entity = GetClosestObjectOfType(x, y, z, REMOVAL_MATCH_RADIUS, model, false, false, false)
    if entity ~= 0 and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
        return true
    end
    return false
end

-- Map-baked props have no deletable entity; ask the engine to stop drawing
-- that model at the spot instead (guarded in case a build lacks the native).
local function hideMapModel(model, x, y, z)
    for _, h in ipairs(activeHides) do
        if isSameRemoval(h, model, x, y, z) then return true end
    end
    if type(CreateModelHide) ~= 'function' then return false end
    if pcall(CreateModelHide, x + 0.0, y + 0.0, z + 0.0, HIDE_RADIUS + 0.0, model, true) then
        activeHides[#activeHides + 1] = { model = model, x = x, y = y, z = z }
        return true
    end
    return false
end

local function clearModelHides()
    if type(RemoveModelHide) == 'function' then
        for _, h in ipairs(activeHides) do
            pcall(RemoveModelHide, h.x + 0.0, h.y + 0.0, h.z + 0.0, HIDE_RADIUS + 0.0, h.model, true)
        end
    end
    activeHides = {}
end

-- Registers a removal (if new) and applies it. `knownEntity` is the exact
-- handle the player aimed at, which is more reliable than re-finding it.
local function applyWorldPropRemoval(model, x, y, z, knownEntity)
    if not model or model == 0 then return false end
    local removed = false
    if knownEntity and knownEntity ~= 0 and DoesEntityExist(knownEntity) then
        SetEntityAsMissionEntity(knownEntity, true, true)
        DeleteEntity(knownEntity)
        removed = not DoesEntityExist(knownEntity)
    end

    local tracked = false
    for _, a in ipairs(activeRemovals) do
        if isSameRemoval(a, model, x, y, z) then tracked = true break end
    end
    if not tracked then
        activeRemovals[#activeRemovals + 1] = { model = model, x = x, y = y, z = z, coords = vector3(x, y, z) }
    end

    if not removed then removed = deleteMatchingWorldEntity(model, x, y, z) end
    if hideMapModel(model, x, y, z) then removed = true end
    return removed
end

-- Base-game props can respawn when the area streams back in; keep
-- re-deleting nearby ones.
CreateThread(function()
    while true do
        Wait(2000)
        if #activeRemovals > 0 then
            local pos = GetEntityCoords(PlayerPedId())
            for _, a in ipairs(activeRemovals) do
                if #(pos - a.coords) < ENFORCE_DISTANCE then
                    deleteMatchingWorldEntity(a.model, a.x, a.y, a.z)
                end
            end
        end
    end
end)

local function getFreeAimEntity()
    local ok, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
    if ok and entity and entity ~= 0 then return entity end
    return 0
end

-- Delete an aimed-at object: placed props are removed from the map, any
-- other object is persistently removed from the world for everyone.
local function tryDeleteAimedProp(preferredEntity)
    if not hasAccess then return end
    local entityHit = preferredEntity
    if not entityHit or entityHit == 0 then
        _, entityHit = getAimCoords(10.0)
    end
    if not entityHit or entityHit == 0 or not DoesEntityExist(entityHit) then
        notify(locale('nothing_in_crosshair'), 'error')
        return
    end

    for localId, data in pairs(placedProps) do
        if data.entity == entityHit then
            removePropByLocalId(localId)
            return
        end
    end

    local model = GetEntityModel(entityHit)
    if model == 0 then
        notify(locale('nothing_in_crosshair'), 'error')
        return
    end
    local coords = GetEntityCoords(entityHit)
    local removed = applyWorldPropRemoval(model, coords.x, coords.y, coords.z, entityHit)
    TriggerServerEvent('rex-mapeditor:server:removeWorldProp', currentMap, model, coords.x, coords.y, coords.z)
    notify(locale(removed and 'world_prop_removed' or 'world_prop_remove_delayed'), removed and 'success' or 'warning')
end

-- ---------------------------------------------------------------------
-- Menu open/close
-- ---------------------------------------------------------------------
local function openMenu()
    if menuOpen or grabbed then return end
    if not refreshAccess() then
        notify(locale('no_permission'), 'error')
        return
    end
    menuOpen = true
    sendNuiLocales()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', mapname = currentMap, openKey = Config.OpenKey })
    refreshEntityList()
    TriggerServerEvent('rex-mapeditor:server:requestFavorites')
    TriggerServerEvent('rex-mapeditor:server:requestCustomProps')
end

local function closeMenu()
    menuOpen = false
    if not grabbed then SetNuiFocus(false, false) end
    SendNUIMessage({ action = 'close' })
end

-- RegisterKeyMapping isn't available on every RedM build.
local function keyMapping(cmd, label, key)
    if RegisterKeyMapping then RegisterKeyMapping(cmd, label, 'keyboard', key) end
end

RegisterCommand(Config.OpenCommand, function()
    if menuOpen then closeMenu() else CreateThread(openMenu) end
end, false)
keyMapping(Config.OpenCommand, locale('keymap_open_menu'), Config.OpenKey)

RegisterCommand('propdelete', function() tryDeleteAimedProp() end, false)
keyMapping('propdelete', locale('keymap_delete_prop'), 'DELETE')

-- Native Delete-key listener as a fallback for builds without key mappings.
-- Only runs for players with access.
CreateThread(function()
    while true do
        if hasAccess and not grabbed and not menuOpen then
            if IsControlJustPressed(0, Controls.DELETE_AIMED) then tryDeleteAimedProp() end
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

-- ---------------------------------------------------------------------
-- Aim-and-fire deletion mode (weapon never actually fires while active)
-- ---------------------------------------------------------------------
local deleteAimModeActive = false

local function setDeleteAimMode(state)
    if deleteAimModeActive == state then return end
    deleteAimModeActive = state
    notify(locale(state and 'delete_aim_on' or 'delete_aim_off'), state and 'success' or 'inform')
end

RegisterCommand('propdeleteaim', function()
    if not hasAccess then return end
    setDeleteAimMode(not deleteAimModeActive)
end, false)
keyMapping('propdeleteaim', locale('keymap_toggle_delete_aim'), 'B')

CreateThread(function()
    while true do
        if deleteAimModeActive then
            if grabbed or not hasAccess then
                setDeleteAimMode(false)
            else
                local pid = PlayerId()
                local _, weapon = GetCurrentPedWeapon(PlayerPedId(), true)
                local isArmed = weapon and weapon ~= `WEAPON_UNARMED`
                local isAiming = IsPlayerFreeAiming(pid) or IsControlPressed(0, Controls.AIM)
                -- Read both: once firing is disabled the attack control only
                -- reports through the "Disabled" variant.
                local firePressed = IsControlJustPressed(0, Controls.ATTACK)
                    or IsDisabledControlJustPressed(0, Controls.ATTACK)

                if isArmed and isAiming and firePressed then
                    tryDeleteAimedProp(getFreeAimEntity())
                end

                DisablePlayerFiring(pid, true)
                DisableControlAction(0, Controls.MELEE_ATTACK, true)
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- ---------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------
local function nui(name, fn)
    RegisterNUICallback(name, function(data, cb)
        fn(type(data) == 'table' and data or {})
        cb('ok')
    end)
end

nui('close', closeMenu)
nui('spawnProp', function(data) spawnProp(data.model) end)
nui('deleteProp', function(data) removePropByLocalId(tonumber(data.localId)) end)
nui('teleportTo', function(data) teleportToLocalId(tonumber(data.localId)) end)

-- Placement Panel buttons (mirror the keybinds)
nui('placementMove', function(data) nudgeGrabbed(data.dir, data.fast) end)
nui('placementHeight', function(data) heightGrabbed(data.dir, data.fast) end)
nui('placementRotate', function(data) rotateGrabbed(data.dir, data.fast) end)
nui('placementPitch', function(data) pitchGrabbed(data.dir, data.fast) end)
nui('placementConfirm', function() confirmGrabbed() end)
nui('placementCancel', function() cancelGrabbed() end)

-- Library / favorites (server validates and broadcasts the result)
nui('favoriteProp', function(data) TriggerServerEvent('rex-mapeditor:server:addFavorite', data.model, data.label) end)
nui('unfavoriteProp', function(data) TriggerServerEvent('rex-mapeditor:server:removeFavorite', data.model) end)
nui('addLibraryProp', function(data)
    TriggerServerEvent('rex-mapeditor:server:addLibraryProp', data.model, data.label, data.category)
end)
nui('removeLibraryProp', function(data) TriggerServerEvent('rex-mapeditor:server:removeLibraryProp', data.model) end)
nui('editLibraryProp', function(data)
    TriggerServerEvent('rex-mapeditor:server:editLibraryProp', data.model, data.newModel, data.label, data.category)
end)

nui('saveMap', function(data)
    currentMap = data.mapname or currentMap
    local payload = {}
    for localId, p in pairs(placedProps) do
        payload[#payload + 1] = {
            localId = localId, model = p.model,
            x = p.x, y = p.y, z = p.z, rx = p.rx, ry = p.ry, rz = p.rz,
        }
    end
    TriggerServerEvent('rex-mapeditor:server:saveMap', currentMap, payload)
end)

nui('loadMap', function(data)
    currentMap = data.mapname or 'default'
    clearImapRemovals()
    TriggerServerEvent('rex-mapeditor:server:loadMap', currentMap)
    TriggerServerEvent('rex-mapeditor:server:requestRemovedProps', currentMap)
    TriggerServerEvent('rex-mapeditor:server:requestImaps', currentMap)
end)

nui('exportYmap', function(data)
    TriggerServerEvent('rex-mapeditor:server:exportYmap', data.mapname)
end)

nui('clearAll', function()
    deletePlacedEntities()
    refreshEntityList()
end)

-- ---------------------------------------------------------------------
-- Server -> client events
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:client:mapSaved', function(mapname, count, idMap)
    for _, m in ipairs(idMap or {}) do
        if placedProps[m.localId] then placedProps[m.localId].id = m.id end
    end
    notify(locale('map_saved', count, mapname), 'success')
    refreshEntityList()
end)

RegisterNetEvent('rex-mapeditor:client:favoritesList', function(favorites)
    SendNUIMessage({ action = 'favoritesList', favorites = favorites })
end)

RegisterNetEvent('rex-mapeditor:client:customPropsList', function(customProps)
    SendNUIMessage({ action = 'customPropsList', customProps = customProps })
end)

RegisterNetEvent('rex-mapeditor:client:worldPropRemoved', function(mapname, model, x, y, z)
    if mapname ~= currentMap then return end
    applyWorldPropRemoval(model, x, y, z)
end)

RegisterNetEvent('rex-mapeditor:client:removedPropsList', function(mapname, removals)
    if mapname ~= currentMap then return end
    for _, r in ipairs(removals) do
        applyWorldPropRemoval(r.model, r.x, r.y, r.z)
    end
    if hasAccess and #removals > 0 then
        notify(locale('removed_props_applied', #removals, mapname), 'inform')
    end
end)

RegisterNetEvent('rex-mapeditor:client:mapLoaded', function(mapname, props)
    deletePlacedEntities()
    local count = 0
    for _, p in ipairs(props) do
        local hash = loadModel(p.model)
        if hash then
            local localId = nextLocalId
            nextLocalId = nextLocalId + 1
            placedProps[localId] = {
                entity = createPlacedObject(hash, p.x, p.y, p.z, p.rx, p.ry, p.rz),
                model = p.model, id = p.id,
                x = p.x, y = p.y, z = p.z, rx = p.rx, ry = p.ry, rz = p.rz,
            }
            count = count + 1
        end
    end
    currentMap = mapname
    notify(locale('map_loaded', count, mapname), 'success')
    refreshEntityList()
end)

-- ---------------------------------------------------------------------
-- IMAP removal: unload a whole map section, persisted per map.
--   /imapremove <hash|name>   /imaprestore <hash|name>
-- ---------------------------------------------------------------------
local removedImaps = {} -- [hash] = true

local function toImapHash(v)
    local n = tonumber(v)
    if n then
        if n > 0x7FFFFFFF then n = n - 0x100000000 end
        return math.floor(n)
    end
    return v and joaat(v) or nil
end

local function applyImapRemoval(hash)
    removedImaps[hash] = true
    RemoveImap(hash)
end

clearImapRemovals = function()
    for hash in pairs(removedImaps) do RequestImap(hash) end
    removedImaps = {}
end

local function imapCommand(remove)
    return function(_, args)
        if not hasAccess then return end
        local hash = toImapHash(args[1])
        if not hash then return notify(locale('imap_usage'), 'error') end
        TriggerServerEvent('rex-mapeditor:server:setImap', currentMap, hash, remove)
    end
end
RegisterCommand('imapremove', imapCommand(true), false)
RegisterCommand('imaprestore', imapCommand(false), false)

RegisterNetEvent('rex-mapeditor:client:imapChanged', function(mapname, hash, removed)
    if mapname ~= currentMap then return end
    if removed then
        applyImapRemoval(hash)
    else
        removedImaps[hash] = nil
        RequestImap(hash)
    end
    if hasAccess then
        notify(locale(removed and 'imap_removed' or 'imap_restored', tostring(hash)), 'success')
    end
end)

RegisterNetEvent('rex-mapeditor:client:imapList', function(mapname, list)
    if mapname ~= currentMap then return end
    for _, hash in ipairs(list) do applyImapRemoval(hash) end
end)

-- The game can re-request imaps while travelling; re-apply slowly.
CreateThread(function()
    while true do
        Wait(5000)
        for hash in pairs(removedImaps) do
            local active = IsImapActive(hash)
            if active == true or active == 1 then RemoveImap(hash) end
        end
    end
end)

-- ---------------------------------------------------------------------
-- Aim inspector: info card + coloured bounding box for whatever an
-- authorized player's weapon is pointed at.
-- ---------------------------------------------------------------------
local lastInspected = 0
local outlineColor = { 255, 255, 255 }
local ENTITY_TYPES = { [1] = 'ped', [2] = 'vehicle', [3] = 'object' } -- ui_type_* locale keys

local function hideInspector()
    if lastInspected ~= 0 then
        lastInspected = 0
        SendNUIMessage({ action = 'hideInspector' })
    end
end

local function isPlacedEntity(entity)
    for _, data in pairs(placedProps) do
        if data.entity == entity then return true end
    end
    return false
end

CreateThread(function()
    local canHide = type(CreateModelHide) == 'function'
    while true do
        local sleep = 500
        if hasAccess and not grabbed and not menuOpen and IsPlayerFreeAiming(PlayerId()) then
            sleep = 100
            local entity = getFreeAimEntity()
            if entity == 0 then
                _, entity = getAimCoords(Config.MaxRaycastDistance)
            end
            if entity and entity ~= 0 and DoesEntityExist(entity) then
                local coords = GetEntityCoords(entity)
                local rot = GetEntityRotation(entity, 2)
                local placed = isPlacedEntity(entity)
                local etype = GetEntityType(entity)
                if placed or etype == 3 then
                    outlineColor = { 111, 191, 115 }   -- deletable
                elseif canHide then
                    outlineColor = { 217, 164, 65 }    -- map-baked, will hide
                else
                    outlineColor = { 224, 85, 79 }     -- can't remove
                end
                lastInspected = entity
                SendNUIMessage({
                    action = 'showInspector',
                    hash = GetEntityModel(entity),
                    type = ENTITY_TYPES[etype] or 'map',
                    x = coords.x, y = coords.y, z = coords.z,
                    rx = rot.x, ry = rot.y, rz = rot.z,
                    distance = #(GetEntityCoords(PlayerPedId()) - coords),
                    placed = placed,
                    mission = IsEntityAMissionEntity(entity) == true or IsEntityAMissionEntity(entity) == 1,
                    networked = NetworkGetEntityIsNetworked(entity) == true or NetworkGetEntityIsNetworked(entity) == 1,
                    deletable = placed or etype == 3 or canHide,
                    map = currentMap,
                })
            else
                hideInspector()
            end
        else
            hideInspector()
        end
        Wait(sleep)
    end
end)

-- corner index = x*4 + y*2 + z + 1 (each 0/1)
local BOX_EDGES = {
    {1,2},{3,4},{5,6},{7,8},
    {1,3},{2,4},{5,7},{6,8},
    {1,5},{2,6},{3,7},{4,8},
}

local function drawEntityBox(entity, r, g, b)
    local min, max = GetModelDimensions(GetEntityModel(entity))
    local c, i = {}, 0
    for _, x in ipairs({ min.x, max.x }) do
        for _, y in ipairs({ min.y, max.y }) do
            for _, z in ipairs({ min.z, max.z }) do
                i = i + 1
                c[i] = GetOffsetFromEntityInWorldCoords(entity, x, y, z)
            end
        end
    end
    for _, e in ipairs(BOX_EDGES) do
        local a, b2 = c[e[1]], c[e[2]]
        DrawLine(a.x, a.y, a.z, b2.x, b2.y, b2.z, r, g, b, 255)
    end
end

CreateThread(function()
    while true do
        if lastInspected ~= 0 and DoesEntityExist(lastInspected) then
            drawEntityBox(lastInspected, outlineColor[1], outlineColor[2], outlineColor[3])
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- ---------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------
AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    -- Every player gets the default map's world removals applied on join.
    TriggerServerEvent('rex-mapeditor:server:requestRemovedProps', 'default')
    TriggerServerEvent('rex-mapeditor:server:requestImaps', 'default')
    CreateThread(function()
        refreshAccess()
        Wait(1000) -- give the NUI page time to load
        sendNuiLocales()
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    deletePlacedEntities()
    if grabbed then
        if DoesEntityExist(grabbed.entity) then DeleteEntity(grabbed.entity) end
        freezePlayerForPlacement(false)
        grabbed = nil
    end
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    clearModelHides()
    clearImapRemovals()
end)
