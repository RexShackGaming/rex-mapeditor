lib.locale()

local RESOURCE = GetCurrentResourceName()

-- ---------------------------------------------------------------------
-- Limits (server-side sanity caps on anything the client sends)
-- ---------------------------------------------------------------------
local MAX_PROPS_PER_MAP = 2000
local MAX_STRING_LEN    = 64
local MAX_COORD         = 20000.0
local WRITE_COOLDOWN_MS = 250

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
-- RSG-Core is optional: used for its permission groups (admin / god).
local RSGCore = GetResourceState('rsg-core') == 'started' and exports['rsg-core']:GetCoreObject() or nil

-- Allowed if the player has the ACE permission OR one of the RSG-Core
-- permission groups in Config.AdminGroups.
local function isAuthorized(src)
    if not Config.RestrictToAdmins then return true end
    src = tonumber(src)
    if not src or src <= 0 then return false end
    local id = tostring(src)
    if Config.AdminAce and IsPlayerAceAllowed(id, Config.AdminAce) then return true end
    for _, group in ipairs(Config.AdminGroups or {}) do
        -- 'god' / 'rsgcore.god' style aces (RSG server.cfg recipes use both)
        if IsPlayerAceAllowed(id, group) or IsPlayerAceAllowed(id, 'rsgcore.' .. group) then return true end
        if RSGCore and RSGCore.Functions.HasPermission and RSGCore.Functions.HasPermission(src, group) then
            return true
        end
    end
    return false
end

-- Per-player throttle for every event that writes to disk / broadcasts.
local lastWrite = {}
local function throttled(src)
    local now = GetGameTimer()
    if lastWrite[src] and now - lastWrite[src] < WRITE_COOLDOWN_MS then return true end
    lastWrite[src] = now
    return false
end
AddEventHandler('playerDropped', function() lastWrite[source] = nil end)

-- Common guard for privileged write events. Logs unauthorized attempts.
local function guard(src, eventName)
    if not isAuthorized(src) then
        print(locale('server_unauthorized', eventName, src))
        return false
    end
    return not throttled(src)
end

local function cleanString(v, maxLen)
    if type(v) ~= 'string' and type(v) ~= 'number' then return '' end
    v = tostring(v):gsub('^%s+', ''):gsub('%s+$', '')
    return v:sub(1, maxLen or MAX_STRING_LEN)
end

local function cleanModel(v)
    return (cleanString(v):gsub('[^%w_%-]', ''))
end

local function num(v, limit)
    v = tonumber(v)
    if not v or v ~= v then return nil end -- nil / NaN
    limit = limit or MAX_COORD
    if v > limit or v < -limit then return nil end
    return v + 0.0
end

local function sanitizeMapName(name)
    name = cleanString(name, 48):gsub('[^%w_%-]', '')
    return name ~= '' and name or 'default'
end

local function readJson(path, default)
    local raw = LoadResourceFile(RESOURCE, path)
    if not raw or raw == '' then return default end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return default end
    return decoded
end

local function writeJson(path, data)
    SaveResourceFile(RESOURCE, path, json.encode(data), -1)
end

-- Send only to currently authorized players (keeps admin data off normal
-- clients and avoids pointless network traffic).
local function sendToAuthorized(eventName, ...)
    for _, id in ipairs(GetPlayers()) do
        local pid = tonumber(id)
        if isAuthorized(pid) then
            TriggerClientEvent(eventName, pid, ...)
        end
    end
end

local function mapPath(m)     return ('data/%s.json'):format(m) end
local function removedPath(m) return ('data/%s.removed.json'):format(m) end
local function imapPath(m)    return ('data/%s.imaps.json'):format(m) end
local FAVORITES_FILE    = 'data/favorites.json'
local CUSTOM_PROPS_FILE = 'data/custom_props.json'

local function loadCustomProps()
    local d = readJson(CUSTOM_PROPS_FILE, {})
    d.additions = d.additions or {}
    d.removals  = d.removals or {}
    d.overrides = d.overrides or {}
    return d
end

local REMOVAL_RADIUS_SQ = (Config.RemovalMatchRadius or 1.5) ^ 2
local function isSameRemoval(a, model, x, y, z)
    if a.model ~= model then return false end
    local dx, dy, dz = a.x - x, a.y - y, a.z - z
    return (dx * dx + dy * dy + dz * dz) <= REMOVAL_RADIUS_SQ
end

-- ---------------------------------------------------------------------
-- Access check used by the client to enable/disable the tool
-- ---------------------------------------------------------------------
lib.callback.register('rex-mapeditor:server:hasAccess', function(src)
    local ok = isAuthorized(src)
    if not ok then print(locale('server_access_denied', GetPlayerName(src) or '?', src)) end
    return ok
end)

-- ---------------------------------------------------------------------
-- Favorites (shared between all tool users)
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:server:requestFavorites', function()
    local src = source
    if not isAuthorized(src) then return end
    TriggerClientEvent('rex-mapeditor:client:favoritesList', src, readJson(FAVORITES_FILE, {}))
end)

RegisterNetEvent('rex-mapeditor:server:addFavorite', function(model, label)
    local src = source
    if not guard(src, 'addFavorite') then return end
    model = cleanModel(model)
    if model == '' then return end
    label = cleanString(label)
    if label == '' then label = model end

    local favorites = readJson(FAVORITES_FILE, {})
    for _, f in ipairs(favorites) do
        if f.model == model then return end
    end
    favorites[#favorites + 1] = { model = model, label = label }
    writeJson(FAVORITES_FILE, favorites)
    sendToAuthorized('rex-mapeditor:client:favoritesList', favorites)
end)

RegisterNetEvent('rex-mapeditor:server:removeFavorite', function(model)
    local src = source
    if not guard(src, 'removeFavorite') then return end
    model = cleanModel(model)

    local favorites, out = readJson(FAVORITES_FILE, {}), {}
    for _, f in ipairs(favorites) do
        if f.model ~= model then out[#out + 1] = f end
    end
    if #out == #favorites then return end
    writeJson(FAVORITES_FILE, out)
    sendToAuthorized('rex-mapeditor:client:favoritesList', out)
end)

-- ---------------------------------------------------------------------
-- Custom Prop Library overlay (additions / removals / overrides on top of
-- the bundled html/props.json, which is never edited on disk)
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:server:requestCustomProps', function()
    local src = source
    if not isAuthorized(src) then return end
    TriggerClientEvent('rex-mapeditor:client:customPropsList', src, loadCustomProps())
end)

RegisterNetEvent('rex-mapeditor:server:addLibraryProp', function(model, label, category)
    local src = source
    if not guard(src, 'addLibraryProp') then return end
    model = cleanModel(model)
    if model == '' then return end
    label = cleanString(label)
    category = cleanString(category)
    if label == '' then label = model end
    if category == '' then category = 'Custom' end

    local data = loadCustomProps()

    -- Re-adding a removed (blacklisted) model makes it visible again.
    local removals = {}
    for _, m in ipairs(data.removals) do
        if m ~= model then removals[#removals + 1] = m end
    end
    data.removals = removals

    local exists = false
    for _, p in ipairs(data.additions) do
        if p.model == model then exists = true break end
    end
    if not exists then
        data.additions[#data.additions + 1] = { model = model, label = label, category = category }
        data.overrides[model] = nil
    end

    writeJson(CUSTOM_PROPS_FILE, data)
    sendToAuthorized('rex-mapeditor:client:customPropsList', data)
end)

-- Label/category may be blank; a blank new model means "no rename".
RegisterNetEvent('rex-mapeditor:server:editLibraryProp', function(origModel, newModel, label, category)
    local src = source
    if not guard(src, 'editLibraryProp') then return end
    origModel = cleanModel(origModel)
    if origModel == '' then return end
    newModel = cleanModel(newModel)
    label = cleanString(label)
    category = cleanString(category)

    local data = loadCustomProps()
    local foundCustom = false
    for _, p in ipairs(data.additions) do
        if p.model == origModel then
            if newModel ~= '' then p.model = newModel end
            p.label, p.category = label, category
            foundCustom = true
            break
        end
    end
    if not foundCustom then
        data.overrides[origModel] = { model = newModel, label = label, category = category }
    end

    writeJson(CUSTOM_PROPS_FILE, data)
    sendToAuthorized('rex-mapeditor:client:customPropsList', data)
end)

RegisterNetEvent('rex-mapeditor:server:removeLibraryProp', function(model)
    local src = source
    if not guard(src, 'removeLibraryProp') then return end
    model = cleanModel(model)
    if model == '' then return end

    local data = loadCustomProps()
    local additions = {}
    for _, p in ipairs(data.additions) do
        if p.model ~= model then additions[#additions + 1] = p end
    end
    data.additions = additions
    data.overrides[model] = nil

    local blacklisted = false
    for _, m in ipairs(data.removals) do
        if m == model then blacklisted = true break end
    end
    if not blacklisted then data.removals[#data.removals + 1] = model end

    writeJson(CUSTOM_PROPS_FILE, data)
    sendToAuthorized('rex-mapeditor:client:customPropsList', data)
end)

-- ---------------------------------------------------------------------
-- Maps: save / load / remove single prop
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:server:saveMap', function(mapname, props)
    local src = source
    if not guard(src, 'saveMap') then return end
    if type(props) ~= 'table' then return end
    mapname = sanitizeMapName(mapname)

    local out, idMap = {}, {}
    for _, p in ipairs(props) do
        if #out >= MAX_PROPS_PER_MAP then break end
        if type(p) == 'table' then
            local model = cleanModel(p.model)
            local x, y, z = num(p.x), num(p.y), num(p.z)
            local rx, ry, rz = num(p.rx, 36000.0), num(p.ry, 36000.0), num(p.rz, 36000.0)
            if model ~= '' and x and y and z and rx and ry and rz then
                local id = #out + 1
                out[id] = { id = id, model = model, x = x, y = y, z = z, rx = rx % 360, ry = ry % 360, rz = rz % 360 }
                local localId = tonumber(p.localId)
                if localId then idMap[#idMap + 1] = { localId = localId, id = id } end
            end
        end
    end

    writeJson(mapPath(mapname), out)
    -- Ids are renumbered on every save, so hand them back to the client to
    -- keep its rows in sync (otherwise later deletes hit the wrong entry).
    TriggerClientEvent('rex-mapeditor:client:mapSaved', src, mapname, #out, idMap)
end)

RegisterNetEvent('rex-mapeditor:server:loadMap', function(mapname)
    local src = source
    if not guard(src, 'loadMap') then return end
    mapname = sanitizeMapName(mapname)
    TriggerClientEvent('rex-mapeditor:client:mapLoaded', src, mapname, readJson(mapPath(mapname), {}))
end)

RegisterNetEvent('rex-mapeditor:server:removeProp', function(mapname, id)
    local src = source
    if not isAuthorized(src) then return end
    id = tonumber(id)
    if not id then return end
    mapname = sanitizeMapName(mapname)

    local props, out = readJson(mapPath(mapname), {}), {}
    for _, p in ipairs(props) do
        if p.id ~= id then out[#out + 1] = p end
    end
    if #out ~= #props then writeJson(mapPath(mapname), out) end
end)

-- ---------------------------------------------------------------------
-- Persistent removal of EXISTING base-game world props
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:server:removeWorldProp', function(mapname, model, x, y, z, rx, ry, rz, kind)
    local src = source
    if not guard(src, 'removeWorldProp') then return end
    model = math.tointeger(tonumber(model))
    x, y, z = num(x), num(y), num(z)
    if not model or model == 0 or not x or not y or not z then return end
    mapname = sanitizeMapName(mapname)

    local removals = readJson(removedPath(mapname), {})
    local tracked = false
    for _, r in ipairs(removals) do
        if isSameRemoval(r, model, x, y, z) then tracked = true break end
    end
    if not tracked then
        removals[#removals + 1] = { model = model, x = x, y = y, z = z, rx = num(rx) or 0.0, ry = num(ry) or 0.0, rz = num(rz) or 0.0,
            kind = (kind == 'object' or kind == 'map') and kind or nil }
        writeJson(removedPath(mapname), removals)
    end

    TriggerClientEvent('rex-mapeditor:client:worldPropRemoved', -1, mapname, model, x, y, z)
end)

-- Restore a previously removed world prop (undo a removal).
RegisterNetEvent('rex-mapeditor:server:restoreWorldProp', function(mapname, model, x, y, z)
    local src = source
    if not guard(src, 'restoreWorldProp') then return end
    model = math.tointeger(tonumber(model))
    x, y, z = num(x), num(y), num(z)
    if not model or not x or not y or not z then return end
    mapname = sanitizeMapName(mapname)

    local removals, out, found = readJson(removedPath(mapname), {}), {}, nil
    for _, r in ipairs(removals) do
        if not found and isSameRemoval(r, model, x, y, z) then found = r else out[#out + 1] = r end
    end
    if not found then return end
    writeJson(removedPath(mapname), out)
    -- Broadcast the stored entry (exact coords + rotation, if recorded).
    TriggerClientEvent('rex-mapeditor:client:worldPropRestored', -1, mapname, found.model, found.x, found.y, found.z,
        found.rx, found.ry, found.rz, found.kind)
end)

-- Read-only: every player needs these applied, so no permission check.
RegisterNetEvent('rex-mapeditor:server:requestRemovedProps', function(mapname)
    local src = source
    mapname = sanitizeMapName(mapname)
    TriggerClientEvent('rex-mapeditor:client:removedPropsList', src, mapname, readJson(removedPath(mapname), {}))
end)

-- ---------------------------------------------------------------------
-- IMAP removals (whole map sections), per map
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:server:setImap', function(mapname, hash, removed)
    local src = source
    if not guard(src, 'setImap') then return end
    hash = math.tointeger(tonumber(hash))
    if not hash then return end
    removed = removed == true
    mapname = sanitizeMapName(mapname)

    local out = {}
    for _, h in ipairs(readJson(imapPath(mapname), {})) do
        if h ~= hash then out[#out + 1] = h end
    end
    if removed then out[#out + 1] = hash end
    writeJson(imapPath(mapname), out)
    TriggerClientEvent('rex-mapeditor:client:imapChanged', -1, mapname, hash, removed)
end)

RegisterNetEvent('rex-mapeditor:server:requestImaps', function(mapname)
    local src = source
    mapname = sanitizeMapName(mapname)
    TriggerClientEvent('rex-mapeditor:client:imapList', src, mapname, readJson(imapPath(mapname), {}))
end)

-- ---------------------------------------------------------------------
-- Export to CMapData (.ymap) XML - see server/ymap.lua
-- ---------------------------------------------------------------------
local function doExport(mapname)
    mapname = sanitizeMapName(mapname)
    local props = readJson(mapPath(mapname), {})
    local removals = readJson(removedPath(mapname), {})
    if #props == 0 and #removals == 0 then
        return nil, locale('export_no_data', mapname)
    end
    local outPath = ('data/%s.ymap.xml'):format(mapname)
    SaveResourceFile(RESOURCE, outPath, BuildYmapXml(mapname, props, removals), -1)
    return outPath, #props, #removals
end

RegisterNetEvent('rex-mapeditor:server:exportYmap', function(mapname)
    local src = source
    if not guard(src, 'exportYmap') then return end
    local outPath, countOrErr, removalCount = doExport(mapname)
    if not outPath then
        TriggerClientEvent('rex-mapeditor:client:notify', src, countOrErr, 'error')
        return
    end
    TriggerClientEvent('rex-mapeditor:client:notify', src,
        locale('ymap_exported', locale('export_success', outPath, countOrErr, removalCount)), 'success')
end)

-- Console / ACE-restricted command (command.exportymap)
RegisterCommand('exportymap', function(source, args)
    if source ~= 0 and not isAuthorized(source) then return end
    local outPath, countOrErr, removalCount = doExport(args[1])
    if not outPath then
        print(locale('server_log_prefix', countOrErr))
        return
    end
    print(locale('server_export_log', countOrErr, removalCount, outPath))
end, true)
