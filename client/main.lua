local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local menuOpen = false
local placedProps = {}      -- [localId] = { entity = handle, model = string, id = serverId or nil, x,y,z,rx,ry,rz }
local currentMap = 'default'
local nextLocalId = 1

local grabbed = nil         -- currently-being-placed entity info: { entity, model, x,y,z,rx,ry,rz, localId, isNew }
local grabbedTick = nil

-- Ask the server for any persisted world-prop removals on the default map as
-- soon as this resource starts, so they're enforced for every player without
-- anyone needing to open the menu first.
AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    TriggerServerEvent('rex-mapeditor:server:requestRemovedProps', 'default')
end)

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

-- ox_lib uses 'inform' | 'success' | 'error' | 'warning' as notification types;
-- this resource internally uses 'primary' | 'success' | 'error', so map accordingly.
local oxTypeMap = {
    primary = 'inform',
    success = 'success',
    error = 'error',
}

local function notify(msg, type)
    local ok = false
    if lib and lib.notify then
        ok = pcall(function()
            lib.notify({
                title = locale('menu_title'),
                description = msg,
                type = oxTypeMap[type] or 'inform',
                duration = 4000,
            })
        end)
    end
    if not ok then
        -- Fallback if ox_lib isn't available/loaded on this build
        print(('[rex-mapeditor] %s'):format(msg))
        TriggerEvent('chat:addMessage', {
            args = { '[rex-mapeditor]', msg }
        })
    end
end

-- ---------------------------------------------------------------------
-- RedM controls
--
-- RedM (RDR3) does NOT use GTA V's numeric control-ID scheme for most
-- actions - it uses named INPUT_* hashes with its own default bindings,
-- so plugging in FiveM's classic numbers (e.g. 172 for "up") either does
-- nothing or hits an unrelated action. These are resolved via GetHashKey
-- against the documented RDR3 control names, all confirmed available in
-- the "OnFoot" control context:
--   https://github.com/femga/rdr3_discoveries/blob/master/Controls/README.md
-- ---------------------------------------------------------------------
local Controls = {
    FRONTEND_UP     = GetHashKey('INPUT_FRONTEND_UP'),      -- Arrow Up
    FRONTEND_DOWN   = GetHashKey('INPUT_FRONTEND_DOWN'),    -- Arrow Down
    FRONTEND_LEFT   = GetHashKey('INPUT_FRONTEND_LEFT'),    -- Arrow Left
    FRONTEND_RIGHT  = GetHashKey('INPUT_FRONTEND_RIGHT'),   -- Arrow Right
    RAISE           = GetHashKey('INPUT_CREATOR_LT'),       -- Page Up
    LOWER           = GetHashKey('INPUT_CREATOR_RT'),       -- Page Down
    ROTATE_LEFT     = GetHashKey('INPUT_FRONTEND_LB'),      -- Q
    ROTATE_RIGHT    = GetHashKey('INPUT_FRONTEND_RB'),      -- E

    -- Q and E are each bound to several OTHER actions at the same time in
    -- RDR3 (not just the frontend bumper actions above), which is what was
    -- causing the character to dive/cover/lunge when rotating a prop. All of
    -- these share the physical Q or E key and need disabling too.
    Q_COVER         = GetHashKey('INPUT_COVER'),
    Q_DIVE          = GetHashKey('INPUT_DIVE'),
    Q_SPECIAL       = GetHashKey('INPUT_SPECIAL_ABILITY_ACTION'),
    Q_STUDY         = GetHashKey('INPUT_INTERACT_LOCKON_STUDY_BINOCULARS'),
    Q_TARGET_INFO   = GetHashKey('INPUT_INTERACT_LOCKON_TARGET_INFO'),
    E_GRAPPLE       = GetHashKey('INPUT_MELEE_GRAPPLE'),
    E_GRAPPLE_CHOKE = GetHashKey('INPUT_MELEE_GRAPPLE_CHOKE'),
    E_EAT           = GetHashKey('INPUT_CRAFTING_EAT'),
    E_LOCKON_Y      = GetHashKey('INPUT_INTERACT_LOCKON_Y'),
    PITCH_DOWN      = GetHashKey('INPUT_SNIPER_ZOOM_OUT_ONLY'), -- [
    PITCH_UP        = GetHashKey('INPUT_SNIPER_ZOOM_IN_ONLY'),  -- ]
    CONFIRM         = GetHashKey('INPUT_FRONTEND_ACCEPT'),  -- Enter
    CANCEL          = GetHashKey('INPUT_FRONTEND_CANCEL'),  -- Backspace / Esc
    DELETE_AIMED    = GetHashKey('INPUT_FRONTEND_DELETE'),  -- Delete
    SPRINT          = GetHashKey('INPUT_SPRINT'),           -- Left Shift (fast movement modifier)
    LOOK_LR         = GetHashKey('INPUT_LOOK_LR'),
    LOOK_UD         = GetHashKey('INPUT_LOOK_UD'),

    -- Extra controls disabled purely to stop the character from moving,
    -- attacking, jumping, etc. while a prop is being positioned.
    MOVE_LR         = GetHashKey('INPUT_MOVE_LR'),
    MOVE_UD         = GetHashKey('INPUT_MOVE_UD'),
    MOVE_LEFT_ONLY  = GetHashKey('INPUT_MOVE_LEFT_ONLY'),
    MOVE_RIGHT_ONLY = GetHashKey('INPUT_MOVE_RIGHT_ONLY'),
    MOVE_UP_ONLY    = GetHashKey('INPUT_MOVE_UP_ONLY'),
    MOVE_DOWN_ONLY  = GetHashKey('INPUT_MOVE_DOWN_ONLY'),
    JUMP            = GetHashKey('INPUT_JUMP'),
    ATTACK          = GetHashKey('INPUT_ATTACK'),
    ATTACK2         = GetHashKey('INPUT_ATTACK2'),
    MELEE_ATTACK    = GetHashKey('INPUT_MELEE_ATTACK'),
    RELOAD          = GetHashKey('INPUT_RELOAD'),
    AIM             = GetHashKey('INPUT_AIM'),
    CONTEXT         = GetHashKey('INPUT_CONTEXT'),       -- interact / talk
    ENTER_VEHICLE   = GetHashKey('INPUT_ENTER'),
    WHISTLE_HORSE   = GetHashKey('INPUT_WHISTLE_HORSEBACK'),
    SELECT_WEAPON   = GetHashKey('INPUT_SELECT_WEAPON'),
    DUCK            = GetHashKey('INPUT_DUCK'),
}

-- All of the above, disabled every frame while placing a prop so the
-- character stays put and doesn't fire, swing, jump, mount up, etc.
local FROZEN_MODE_CONTROLS = {
    Controls.LOOK_LR, Controls.LOOK_UD,
    Controls.MOVE_LR, Controls.MOVE_UD,
    Controls.MOVE_LEFT_ONLY, Controls.MOVE_RIGHT_ONLY, Controls.MOVE_UP_ONLY, Controls.MOVE_DOWN_ONLY,
    Controls.JUMP, Controls.ATTACK, Controls.ATTACK2, Controls.MELEE_ATTACK,
    Controls.RELOAD, Controls.AIM, Controls.CONTEXT, Controls.ENTER_VEHICLE,
    Controls.WHISTLE_HORSE, Controls.SELECT_WEAPON, Controls.DUCK,
    Controls.FRONTEND_UP, Controls.FRONTEND_DOWN, Controls.FRONTEND_LEFT, Controls.FRONTEND_RIGHT,
    Controls.RAISE, Controls.LOWER, Controls.ROTATE_LEFT, Controls.ROTATE_RIGHT,
    Controls.PITCH_DOWN, Controls.PITCH_UP,
    Controls.Q_COVER, Controls.Q_DIVE, Controls.Q_SPECIAL, Controls.Q_STUDY, Controls.Q_TARGET_INFO,
    Controls.E_GRAPPLE, Controls.E_GRAPPLE_CHOKE, Controls.E_EAT, Controls.E_LOCKON_Y,
}

local function loadModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelValid(hash) then
        return nil
    end
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 5000 do
        Wait(50)
        timeout = timeout + 50
    end
    if not HasModelLoaded(hash) then
        return nil
    end
    return hash
end

-- Raycast forward from the camera to find a placement point in the world
local function getAimCoords(maxDistance)
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local direction = RotationToDirection(camRot)
    local destination = vector3(
        camCoords.x + direction.x * maxDistance,
        camCoords.y + direction.y * maxDistance,
        camCoords.z + direction.z * maxDistance
    )
    local rayHandle = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, destination.x, destination.y, destination.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords, _, entityHit = GetShapeTestResult(rayHandle)
    if hit == 1 then
        return endCoords, entityHit
    end
    return destination, 0
end

function RotationToDirection(rotation)
    local adjustedRotation = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z
    }
    local direction = {
        x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        z = math.sin(adjustedRotation.x)
    }
    return direction
end

local function registerAsMissionEntity(entity)
    SetEntityAsMissionEntity(entity, true, true)
end

local function refreshEntityList()
    local list = {}
    for localId, data in pairs(placedProps) do
        list[#list + 1] = {
            localId = localId,
            id = data.id,
            model = data.model,
            x = data.x, y = data.y, z = data.z,
            rx = data.rx, ry = data.ry, rz = data.rz,
        }
    end
    SendNUIMessage({ action = 'refreshList', props = list, mapname = currentMap })
end

-- ---------------------------------------------------------------------
-- Placement / grab loop
-- ---------------------------------------------------------------------

local function updateGrabbedEntity()
    if not grabbed then return end
    SetEntityCoordsNoOffset(grabbed.entity, grabbed.x, grabbed.y, grabbed.z, true, true, true)
    SetEntityRotation(grabbed.entity, grabbed.rx, grabbed.ry, grabbed.rz, 2, true)
end

-- ---------------------------------------------------------------------
-- Placement adjustment helpers - shared by both the keybind loop below
-- AND the click-based Placement Panel NUI callbacks further down, so the
-- two input methods stay perfectly in sync and can be used interchangeably
-- (even mid-placement).
-- ---------------------------------------------------------------------

local function nudgeGrabbed(direction, fast)
    if not grabbed then return end
    local moveStep = fast and Config.MoveStepFast or Config.MoveStep
    local camRot = GetGameplayCamRot(2)
    local rad = camRot.z * math.pi / 180.0

    if direction == 'up' then
        grabbed.x = grabbed.x + (-math.sin(rad) * moveStep)
        grabbed.y = grabbed.y + (math.cos(rad) * moveStep)
    elseif direction == 'down' then
        grabbed.x = grabbed.x - (-math.sin(rad) * moveStep)
        grabbed.y = grabbed.y - (math.cos(rad) * moveStep)
    elseif direction == 'left' then
        grabbed.x = grabbed.x - (math.cos(rad) * moveStep)
        grabbed.y = grabbed.y - (math.sin(rad) * moveStep)
    elseif direction == 'right' then
        grabbed.x = grabbed.x + (math.cos(rad) * moveStep)
        grabbed.y = grabbed.y + (math.sin(rad) * moveStep)
    end
    updateGrabbedEntity()
end

local function heightGrabbed(direction, fast)
    if not grabbed then return end
    local heightStep = fast and (Config.HeightStepFast or Config.HeightStep) or Config.HeightStep
    if direction == 'up' then
        grabbed.z = grabbed.z + heightStep
    elseif direction == 'down' then
        grabbed.z = grabbed.z - heightStep
    end
    updateGrabbedEntity()
end

local function rotateGrabbed(direction, fast)
    if not grabbed then return end
    local rotStep = fast and Config.RotateStepFast or Config.RotateStep
    if direction == 'left' then
        grabbed.rz = grabbed.rz - rotStep
    elseif direction == 'right' then
        grabbed.rz = grabbed.rz + rotStep
    end
    updateGrabbedEntity()
end

local function pitchGrabbed(direction, fast)
    if not grabbed then return end
    local rotStep = fast and Config.RotateStepFast or Config.RotateStep
    if direction == 'down' then
        grabbed.rx = grabbed.rx - rotStep
    elseif direction == 'up' then
        grabbed.rx = grabbed.rx + rotStep
    end
    updateGrabbedEntity()
end

local function startGrabbedTick()
    if grabbedTick then return end
    grabbedTick = CreateThread(function()
        while grabbed do
            Wait(0)

            -- Suppress the default behavior of every control we're repurposing
            -- (camera look, cover, bumper actions, sniper zoom) plus normal
            -- movement/combat/interaction controls, so the character stays
            -- put and doesn't walk, jump, fire, mount up, etc. while a prop
            -- is being positioned. We still read pressed state for the ones
            -- we care about via the "Disabled" variants below.
            for _, control in ipairs(FROZEN_MODE_CONTROLS) do
                DisableControlAction(0, control, true)
            end

            local fast = IsControlPressed(0, Controls.SPRINT)

            -- Arrow keys: move on X/Y plane relative to camera heading
            if IsDisabledControlPressed(0, Controls.FRONTEND_UP) then nudgeGrabbed('up', fast) end
            if IsDisabledControlPressed(0, Controls.FRONTEND_DOWN) then nudgeGrabbed('down', fast) end
            if IsDisabledControlPressed(0, Controls.FRONTEND_LEFT) then nudgeGrabbed('left', fast) end
            if IsDisabledControlPressed(0, Controls.FRONTEND_RIGHT) then nudgeGrabbed('right', fast) end

            -- Page Up/Down: height
            if IsDisabledControlPressed(0, Controls.RAISE) then heightGrabbed('up', fast) end
            if IsDisabledControlPressed(0, Controls.LOWER) then heightGrabbed('down', fast) end

            -- Q/E: yaw rotate
            if IsDisabledControlPressed(0, Controls.ROTATE_LEFT) then rotateGrabbed('left', fast) end
            if IsDisabledControlPressed(0, Controls.ROTATE_RIGHT) then rotateGrabbed('right', fast) end

            -- [ / ]: pitch fine-tuning
            if IsDisabledControlPressed(0, Controls.PITCH_DOWN) then pitchGrabbed('down', fast) end
            if IsDisabledControlPressed(0, Controls.PITCH_UP) then pitchGrabbed('up', fast) end

            -- Enter: confirm placement
            -- (INPUT_FRONTEND_ACCEPT/CANCEL are "frontend" controls the game
            -- disables by default outside menus - like the FRONTEND_UP/DOWN/
            -- LEFT/RIGHT reads above, they need the "Disabled" variant to
            -- register at all while nothing has enabled them.)
            if IsDisabledControlJustPressed(0, Controls.CONFIRM) then
                confirmGrabbed()
                break
            end
            -- Backspace/Esc: cancel
            if IsDisabledControlJustPressed(0, Controls.CANCEL) then
                cancelGrabbed()
                break
            end
        end
        grabbedTick = nil
    end)
end

local function restoreMenuAfterPlacement()
    if menuOpen then
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'show' })
    else
        SetNuiFocus(false, false)
    end
end

-- ---------------------------------------------------------------------
-- Placement Panel: a small, draggable, click-based NUI alternative to the
-- keybinds below. Both work at the same time and share the exact same
-- nudge/rotate/height/pitch functions above, so switching between mouse
-- clicks and keys mid-placement just works.
--
-- SetNuiFocusKeepInput(true) is the key piece: normally SetNuiFocus(true,
-- true) hands the browser exclusive keyboard/mouse capture, which would
-- freeze camera look and block every keybind above. KeepInput instead lets
-- the game keep receiving input WHILE the NUI also receives clicks, so the
-- panel's buttons work without taking over the screen or blocking the
-- player's view/aim of the prop being placed.
-- ---------------------------------------------------------------------

local function setPlacementNuiMode(enabled)
    if enabled then
        SetNuiFocus(true, true)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(true) end
    else
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    end
end

local function showPlacementControlsUI(model)
    SendNUIMessage({ action = 'showPlacement', model = model })
    setPlacementNuiMode(true)
end

local function hidePlacementControlsUI()
    SendNUIMessage({ action = 'hidePlacement' })
    setPlacementNuiMode(false)
end

-- Freeze the player ped in place for the duration of placement mode, on top
-- of the per-frame control disabling, so they can't be pushed/shoved out of
-- position or walk off while positioning a prop. Also blocks the ped's
-- ambient/scenario behavior - otherwise holding a control (e.g. the E/rotate
-- key) while stationary can make RDR3's idle-ambient system kick in a
-- "rest" animation even though the control itself is disabled, since that's
-- driven by the ped standing idle rather than the raw input.
local function freezePlayerForPlacement(freeze)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, freeze)
    SetPedCanPlayAmbientAnims(ped, not freeze)
    SetPedCanPlayGestureAnims(ped, not freeze)
    SetPedCanPlayAmbientBaseAnims(ped, not freeze)
    SetBlockingOfNonTemporaryEvents(ped, freeze)
    if freeze then
        ClearPedTasksImmediately(ped)
    end
    -- Take the ped fully out of the game's own control/AI-reaction loop.
    -- The E/context key held near a placed prop (bedroll, chair, campfire,
    -- etc.) can trigger the game's built-in "hold to rest" scenario prompt
    -- for that object - that's driven by the native player-control system
    -- reacting to input, not by our per-control DisableControlAction list,
    -- so disabling individual controls doesn't stop it. Fully revoking
    -- player control does, while our script still reads raw key state via
    -- IsControlPressed/IsDisabledControlPressed for the placement controls.
    SetPlayerControl(PlayerId(), not freeze, 0)
end

function confirmGrabbed()
    if not grabbed then return end
    local localId = grabbed.localId
    placedProps[localId] = {
        entity = grabbed.entity,
        model = grabbed.model,
        x = grabbed.x, y = grabbed.y, z = grabbed.z,
        rx = grabbed.rx, ry = grabbed.ry, rz = grabbed.rz,
        id = placedProps[localId] and placedProps[localId].id or nil,
    }
    notify(locale('prop_placed'), 'success')
    grabbed = nil
    freezePlayerForPlacement(false)
    hidePlacementControlsUI()
    restoreMenuAfterPlacement()
    refreshEntityList()
end

function cancelGrabbed()
    if not grabbed then return end
    if DoesEntityExist(grabbed.entity) then
        DeleteEntity(grabbed.entity)
    end
    grabbed = nil
    notify(locale('placement_cancelled'), 'error')
    freezePlayerForPlacement(false)
    hidePlacementControlsUI()
    restoreMenuAfterPlacement()
end

-- ---------------------------------------------------------------------
-- Spawning / deleting
-- ---------------------------------------------------------------------

local function spawnProp(model)
    local hash = loadModel(model)
    if not hash then
        notify(locale('invalid_model', tostring(model)), 'error')
        return
    end

    local coords, _ = getAimCoords(Config.MaxRaycastDistance)
    local entity = CreateObject(hash, coords.x, coords.y, coords.z, true, true, false)
    FreezeEntityPosition(entity, true)
    registerAsMissionEntity(entity)
    SetModelAsNoLongerNeeded(hash)

    local localId = nextLocalId
    nextLocalId = nextLocalId + 1

    grabbed = {
        entity = entity,
        model = model,
        x = coords.x, y = coords.y, z = coords.z,
        rx = 0.0, ry = 0.0, rz = 0.0,
        localId = localId,
    }

    -- Hide the main menu and switch to placement-mode NUI focus (see
    -- setPlacementNuiMode above) so the world/prop stays fully
    -- visible/controllable while the small Placement Panel is clickable.
    -- The menu reappears automatically once placement is confirmed/cancelled.
    SendNUIMessage({ action = 'hide' })

    freezePlayerForPlacement(true)
    showPlacementControlsUI(model)
    startGrabbedTick()
end

local function removePropByLocalId(localId)
    local data = placedProps[localId]
    if not data then return end
    if DoesEntityExist(data.entity) then
        DeleteEntity(data.entity)
    end
    if data.id then
        TriggerServerEvent('rex-mapeditor:server:removeProp', currentMap, data.id)
    end
    placedProps[localId] = nil
    refreshEntityList()
end

local function teleportToLocalId(localId)
    local data = placedProps[localId]
    if not data then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, data.x, data.y, data.z + 1.0, false, false, false, false)
end

-- ---------------------------------------------------------------------
-- Removing EXISTING base-game world props (not ones placed by this tool)
--
-- There's no way to bake "delete this entity" into a distributable .ymap -
-- base map props live inside Rockstar's own packed archives, and altering
-- those means replacing original game files, which a multiplayer resource
-- can't ship. Instead this keeps a persisted list of {model, x, y, z} per
-- map name; every client deletes matching entities near those coordinates
-- immediately and keeps re-deleting them if the game respawns them when
-- the area streams back in. That gives the same practical result (the
-- prop stays gone for everyone, every session) without touching game files.
-- ---------------------------------------------------------------------
local activeRemovals = {} -- array of { model = hash, x, y, z }
local REMOVAL_MATCH_RADIUS = Config.RemovalMatchRadius or 1.5

local function isSameRemoval(a, model, x, y, z)
    if a.model ~= model then return false end
    local dx, dy, dz = a.x - x, a.y - y, a.z - z
    return (dx * dx + dy * dy + dz * dz) <= (REMOVAL_MATCH_RADIUS * REMOVAL_MATCH_RADIUS)
end

-- Deletes any currently-streamed-in entity matching this removal right now.
local function deleteMatchingWorldEntity(model, x, y, z)
    local entity = GetClosestObjectOfType(x, y, z, REMOVAL_MATCH_RADIUS, model, false, false, false)
    if entity ~= 0 and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
        return true
    end
    return false
end

-- Registers a removal (if not already tracked) and applies it immediately.
-- `knownEntity`, if given, is a handle we already know is the right prop
-- (e.g. the one the player just aimed at) - deleting it directly is more
-- reliable than re-finding it via GetClosestObjectOfType, which only
-- matches entities of type "object" within REMOVAL_MATCH_RADIUS and can
-- silently miss the very prop we're trying to remove.
local function applyWorldPropRemoval(model, x, y, z, knownEntity)
    local removed = false
    if knownEntity and knownEntity ~= 0 and DoesEntityExist(knownEntity) then
        SetEntityAsMissionEntity(knownEntity, true, true)
        DeleteEntity(knownEntity)
        removed = not DoesEntityExist(knownEntity)
    end

    local alreadyTracked = false
    for _, a in ipairs(activeRemovals) do
        if isSameRemoval(a, model, x, y, z) then
            alreadyTracked = true
            break
        end
    end
    if not alreadyTracked then
        activeRemovals[#activeRemovals + 1] = { model = model, x = x, y = y, z = z }
    end

    if not removed then
        removed = deleteMatchingWorldEntity(model, x, y, z)
    end

    return removed
end

-- Persistent enforcement loop: base-game props can respawn as the area
-- streams in again (e.g. the player rides away and comes back), so keep
-- re-deleting anything matching an active removal.
CreateThread(function()
    while true do
        Wait(2000)
        for _, a in ipairs(activeRemovals) do
            deleteMatchingWorldEntity(a.model, a.x, a.y, a.z)
        end
    end
end)

-- Returns the entity the player's weapon reticle is actually locked onto,
-- using the game's own free-aim targeting (accounts for weapon type/recoil/
-- reticle, unlike a plain camera-forward raycast). Returns 0 if not aiming
-- at anything.
local function getFreeAimEntity()
    local ok, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
    if ok and entity and entity ~= 0 then
        return entity
    end
    return 0
end

-- Delete an aimed-at object. If it's a prop this tool placed, remove it
-- from the saved map as before. Otherwise, treat it as a base-game world
-- prop and add it to the persistent removal list for the current map.
-- `preferredEntity`, if given (e.g. from GetEntityPlayerIsFreeAimingAt),
-- is used instead of the camera-forward raycast.
local function tryDeleteAimedProp(preferredEntity)
    local entityHit = preferredEntity
    if not entityHit or entityHit == 0 then
        _, entityHit = getAimCoords(10.0)
    end
    if not entityHit or entityHit == 0 then
        notify(locale('nothing_in_crosshair'), 'error')
        return
    end

    for localId, data in pairs(placedProps) do
        if data.entity == entityHit then
            removePropByLocalId(localId)
            return
        end
    end

    -- Not one of ours - treat as a world prop to remove persistently.
    local model = GetEntityModel(entityHit)
    local coords = GetEntityCoords(entityHit)
    local removed = applyWorldPropRemoval(model, coords.x, coords.y, coords.z, entityHit)
    TriggerServerEvent('rex-mapeditor:server:removeWorldProp', currentMap, model, coords.x, coords.y, coords.z)
    if removed then
        notify(locale('world_prop_removed'), 'success')
    else
        notify(locale('world_prop_remove_delayed'), 'error')
    end
end

-- ---------------------------------------------------------------------
-- Menu open/close
-- ---------------------------------------------------------------------

-- Client-side check is only used to skip showing the menu/prompts to
-- non-admins for UX purposes. The server independently re-checks the ACE
-- permission on every save/load/remove/export event, so this is not the
-- actual security boundary.
local function hasAccess()
    return true
end

local function openMenu()
    if menuOpen then return end
    if not hasAccess() then
        notify(locale('no_permission'), 'error')
        return
    end
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', mapname = currentMap, openKey = Config.OpenKey })
    refreshEntityList()
    TriggerServerEvent('rex-mapeditor:server:requestFavorites')
    TriggerServerEvent('rex-mapeditor:server:requestCustomProps')
end

local function closeMenu()
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterCommand(Config.OpenCommand, function()
    if menuOpen then closeMenu() else openMenu() end
end, false)

if RegisterKeyMapping then
    RegisterKeyMapping(Config.OpenCommand, locale('keymap_open_menu'), 'keyboard', Config.OpenKey)
end

RegisterCommand('propdelete', function()
    if not hasAccess() then return end
    tryDeleteAimedProp()
end, false)

if RegisterKeyMapping then
    RegisterKeyMapping('propdelete', locale('keymap_delete_prop'), 'keyboard', 'DELETE')
end

-- Also listen for the real RDR3 Delete-key control directly (INPUT_FRONTEND_DELETE).
-- This works even on builds where RegisterKeyMapping isn't available, and only
-- fires while not actively placing a prop (placement mode has its own controls).
CreateThread(function()
    while true do
        Wait(0)
        if not grabbed and IsControlJustPressed(0, Controls.DELETE_AIMED) then
            tryDeleteAimedProp()
        end
    end
end)

-- ---------------------------------------------------------------------
-- Aim-and-fire deletion mode
-- ---------------------------------------------------------------------
-- Lets a player point a drawn weapon at a prop and pull the trigger to
-- delete it, so they can clearly see what's about to be removed before
-- committing (the weapon's own crosshair/laser sight is the preview).
-- While this mode is active the player's weapon is prevented from
-- actually discharging (no bullet, no ammo consumed, no damage/noise) -
-- the trigger pull is only used as a confirm gesture.

local deleteAimModeActive = false

local function setDeleteAimMode(state)
    if deleteAimModeActive == state then return end
    deleteAimModeActive = state
    if state then
        notify(locale('delete_aim_on'), 'success')
    else
        notify(locale('delete_aim_off'), 'inform')
    end
end

RegisterCommand('propdeleteaim', function()
    if not hasAccess() then return end
    setDeleteAimMode(not deleteAimModeActive)
end, false)

if RegisterKeyMapping then
    RegisterKeyMapping('propdeleteaim', locale('keymap_toggle_delete_aim'), 'keyboard', 'B')
end

CreateThread(function()
    while true do
        local sleep = 250
        if deleteAimModeActive then
            sleep = 0
            local ped = PlayerPedId()

            if not deleteAimModeActive or grabbed or not hasAccess() then
                setDeleteAimMode(false)
            else
                -- IsPlayerFreeAiming() is the game's own "is the player looking
                -- down the sights at something" check - this is what actually
                -- works reliably in RedM (confirmed against rsg-propgun, which
                -- uses this same native + GetEntityPlayerIsFreeAimingAt() to
                -- read the aimed-at entity instead of a manual raycast).
                local _, currentWeapon = GetCurrentPedWeapon(ped, true)
                local isArmed = currentWeapon ~= nil and currentWeapon ~= `WEAPON_UNARMED`
                local isAiming = IsPlayerFreeAiming(PlayerId()) or IsControlPressed(0, Controls.AIM)

                -- Once DisablePlayerFiring()/DisableControlAction() suppress the
                -- attack control for this frame, IsControlJustPressed() stops
                -- reporting it - you have to read the *disabled* control state
                -- instead. Check both so it works whether or not the engine
                -- treats INPUT_ATTACK as disabled here.
                local firePressed = IsControlJustPressed(0, Controls.ATTACK)
                    or IsDisabledControlJustPressed(0, Controls.ATTACK)

                if isArmed and isAiming and firePressed then
                    tryDeleteAimedProp(getFreeAimEntity())
                end

                -- Never let the weapon actually fire while this mode is on.
                -- (Applied after reading the inputs above.)
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, Controls.MELEE_ATTACK, true)
            end
        end
        Wait(sleep)
    end
end)

-- ---------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb('ok')
end)

RegisterNUICallback('spawnProp', function(data, cb)
    spawnProp(data.model)
    cb('ok')
end)

RegisterNUICallback('deleteProp', function(data, cb)
    removePropByLocalId(tonumber(data.localId))
    cb('ok')
end)

RegisterNUICallback('teleportTo', function(data, cb)
    teleportToLocalId(tonumber(data.localId))
    cb('ok')
end)

-- ---------------------------------------------------------------------
-- Placement Panel button callbacks - mirror the keybinds exactly, driven
-- by the same shared nudge/rotate/height/pitch/confirm/cancel functions.
-- ---------------------------------------------------------------------

RegisterNUICallback('placementMove', function(data, cb)
    nudgeGrabbed(data.dir, data.fast)
    cb('ok')
end)

RegisterNUICallback('placementHeight', function(data, cb)
    heightGrabbed(data.dir, data.fast)
    cb('ok')
end)

RegisterNUICallback('placementRotate', function(data, cb)
    rotateGrabbed(data.dir, data.fast)
    cb('ok')
end)

RegisterNUICallback('placementPitch', function(data, cb)
    pitchGrabbed(data.dir, data.fast)
    cb('ok')
end)

RegisterNUICallback('placementConfirm', function(_, cb)
    confirmGrabbed()
    cb('ok')
end)

RegisterNUICallback('placementCancel', function(_, cb)
    cancelGrabbed()
    cb('ok')
end)

RegisterNUICallback('favoriteProp', function(data, cb)
    TriggerServerEvent('rex-mapeditor:server:addFavorite', data.model, data.label)
    cb('ok')
end)

RegisterNUICallback('unfavoriteProp', function(data, cb)
    TriggerServerEvent('rex-mapeditor:server:removeFavorite', data.model)
    cb('ok')
end)

RegisterNUICallback('addLibraryProp', function(data, cb)
    TriggerServerEvent('rex-mapeditor:server:addLibraryProp', data.model, data.label, data.category)
    cb('ok')
end)

RegisterNUICallback('removeLibraryProp', function(data, cb)
    TriggerServerEvent('rex-mapeditor:server:removeLibraryProp', data.model)
    cb('ok')
end)

RegisterNUICallback('editLibraryProp', function(data, cb)
    TriggerServerEvent('rex-mapeditor:server:editLibraryProp', data.model, data.newModel, data.label, data.category)
    cb('ok')
end)

RegisterNUICallback('setMapName', function(data, cb)
    currentMap = data.mapname
    cb('ok')
end)

RegisterNUICallback('saveMap', function(data, cb)
    local propsPayload = {}
    for localId, p in pairs(placedProps) do
        propsPayload[#propsPayload + 1] = {
            localId = localId,
            model = p.model,
            x = p.x, y = p.y, z = p.z,
            rx = p.rx, ry = p.ry, rz = p.rz,
        }
    end
    TriggerServerEvent('rex-mapeditor:server:saveMap', currentMap, propsPayload)
    cb('ok')
end)

RegisterNUICallback('loadMap', function(data, cb)
    TriggerServerEvent('rex-mapeditor:server:loadMap', data.mapname)
    TriggerServerEvent('rex-mapeditor:server:requestRemovedProps', data.mapname)
    cb('ok')
end)

RegisterNUICallback('exportYmap', function(data, cb)
    TriggerServerEvent('rex-mapeditor:server:exportYmap', data.mapname)
    cb('ok')
end)

RegisterNUICallback('clearAll', function(_, cb)
    for localId, data in pairs(placedProps) do
        if DoesEntityExist(data.entity) then
            DeleteEntity(data.entity)
        end
    end
    placedProps = {}
    refreshEntityList()
    cb('ok')
end)

-- ---------------------------------------------------------------------
-- Server -> client events
-- ---------------------------------------------------------------------

RegisterNetEvent('rex-mapeditor:client:mapSaved', function(mapname, count)
    notify(locale('map_saved', count, mapname), 'success')
end)

-- Shared favorites list, sent on menu open and rebroadcast to everyone
-- whenever any player favorites/unfavorites a prop.
RegisterNetEvent('rex-mapeditor:client:favoritesList', function(favorites)
    SendNUIMessage({ action = 'favoritesList', favorites = favorites })
end)

-- Shared custom-library overlay (user-added props + removed/blacklisted
-- models), sent on menu open and rebroadcast to everyone whenever any
-- player adds or removes a library entry.
RegisterNetEvent('rex-mapeditor:client:customPropsList', function(customProps)
    SendNUIMessage({ action = 'customPropsList', customProps = customProps })
end)

-- A world prop was removed (by anyone, on this or another client) - apply it
-- here too so it disappears for every player without needing a reload.
RegisterNetEvent('rex-mapeditor:client:worldPropRemoved', function(mapname, model, x, y, z)
    if mapname ~= currentMap then return end
    applyWorldPropRemoval(model, x, y, z)
end)

-- Full removed-props list for a map, sent on request (menu Load, or resource
-- start for the default map) or on join.
RegisterNetEvent('rex-mapeditor:client:removedPropsList', function(mapname, removals)
    if mapname ~= currentMap then return end
    for _, r in ipairs(removals) do
        applyWorldPropRemoval(r.model, r.x, r.y, r.z)
    end
    if #removals > 0 then
        notify(locale('removed_props_applied', #removals, mapname), 'primary')
    end
end)

RegisterNetEvent('rex-mapeditor:client:mapLoaded', function(mapname, props)
    -- clear existing first
    for localId, data in pairs(placedProps) do
        if DoesEntityExist(data.entity) then
            DeleteEntity(data.entity)
        end
    end
    placedProps = {}

    for _, p in ipairs(props) do
        local hash = loadModel(p.model)
        if hash then
            local entity = CreateObject(hash, p.x, p.y, p.z, true, true, false)
            SetEntityRotation(entity, p.rx, p.ry, p.rz, 2, true)
            FreezeEntityPosition(entity, true)
            registerAsMissionEntity(entity)
            SetModelAsNoLongerNeeded(hash)

            local localId = nextLocalId
            nextLocalId = nextLocalId + 1
            placedProps[localId] = {
                entity = entity,
                model = p.model,
                x = p.x, y = p.y, z = p.z,
                rx = p.rx, ry = p.ry, rz = p.rz,
                id = p.id,
            }
        end
    end
    currentMap = mapname
    notify(locale('map_loaded', #props, mapname), 'success')
    refreshEntityList()
end)

RegisterNetEvent('rex-mapeditor:client:ymapExported', function(path)
    notify(locale('ymap_exported', path), 'success')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, data in pairs(placedProps) do
        if DoesEntityExist(data.entity) then
            DeleteEntity(data.entity)
        end
    end
    if grabbed then
        if DoesEntityExist(grabbed.entity) then
            DeleteEntity(grabbed.entity)
        end
        freezePlayerForPlacement(false)
    end
    hidePlacementControlsUI()
end)
