local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local function isAuthorized(source)
    if not Config.RestrictToAdmins then return true end
    return IsPlayerAceAllowed(source, Config.AdminAce)
end

local function sanitizeMapName(name)
    name = tostring(name or 'default')
    name = name:gsub('[^%w_%-]', '')
    if name == '' then name = 'default' end
    return name
end

local function mapFilePath(mapname)
    return ('data/%s.json'):format(mapname)
end

local function loadMapFile(mapname)
    local raw = LoadResourceFile(GetCurrentResourceName(), mapFilePath(mapname))
    if not raw then return {} end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return {} end
    return decoded
end

local function saveMapFile(mapname, props)
    SaveResourceFile(GetCurrentResourceName(), mapFilePath(mapname), json.encode(props), -1)
end

-- ---------------------------------------------------------------------
-- Persisted removals of EXISTING base-game world props (not ones placed
-- with this tool). See the client-side comment above tryDeleteAimedProp
-- for why this is a runtime removal list rather than a real ymap edit.
-- ---------------------------------------------------------------------
local function removedPropsFilePath(mapname)
    return ('data/%s.removed.json'):format(mapname)
end

local function loadRemovedPropsFile(mapname)
    local raw = LoadResourceFile(GetCurrentResourceName(), removedPropsFilePath(mapname))
    if not raw then return {} end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return {} end
    return decoded
end

local function saveRemovedPropsFile(mapname, removals)
    SaveResourceFile(GetCurrentResourceName(), removedPropsFilePath(mapname), json.encode(removals), -1)
end

local REMOVAL_MATCH_RADIUS = Config.RemovalMatchRadius or 1.5

local function isSameRemoval(a, model, x, y, z)
    if a.model ~= model then return false end
    local dx, dy, dz = a.x - x, a.y - y, a.z - z
    return (dx * dx + dy * dy + dz * dz) <= (REMOVAL_MATCH_RADIUS * REMOVAL_MATCH_RADIUS)
end

-- ---------------------------------------------------------------------
-- Favorited props: a shared (server-wide) list of props any tool user has
-- starred, so they show up in everyone's Prop Library on next NUI open
-- without needing to re-search for them.
-- ---------------------------------------------------------------------
local FAVORITES_FILE = 'data/favorites.json'

local function loadFavoritesFile()
    local raw = LoadResourceFile(GetCurrentResourceName(), FAVORITES_FILE)
    if not raw then return {} end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return {} end
    return decoded
end

local function saveFavoritesFile(favorites)
    SaveResourceFile(GetCurrentResourceName(), FAVORITES_FILE, json.encode(favorites), -1)
end

RegisterNetEvent('rex-mapeditor:server:requestFavorites', function()
    local src = source
    TriggerClientEvent('rex-mapeditor:client:favoritesList', src, loadFavoritesFile())
end)

RegisterNetEvent('rex-mapeditor:server:addFavorite', function(model, label)
    local src = source
    if not isAuthorized(src) then return end
    model = tostring(model or ''):gsub('%s+', '')
    if model == '' then return end
    label = tostring(label or model)

    local favorites = loadFavoritesFile()
    for _, f in ipairs(favorites) do
        if f.model == model then
            TriggerClientEvent('rex-mapeditor:client:favoritesList', -1, favorites)
            return
        end
    end
    favorites[#favorites + 1] = { model = model, label = label }
    saveFavoritesFile(favorites)
    TriggerClientEvent('rex-mapeditor:client:favoritesList', -1, favorites)
end)

RegisterNetEvent('rex-mapeditor:server:removeFavorite', function(model)
    local src = source
    if not isAuthorized(src) then return end
    model = tostring(model or '')

    local favorites = loadFavoritesFile()
    local out = {}
    for _, f in ipairs(favorites) do
        if f.model ~= model then
            out[#out + 1] = f
        end
    end
    saveFavoritesFile(out)
    TriggerClientEvent('rex-mapeditor:client:favoritesList', -1, out)
end)

-- ---------------------------------------------------------------------
-- Save the full current placement state for a map
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:server:saveMap', function(mapname, props)
    local src = source
    if not isAuthorized(src) then
        print(locale('server_unauthorized_savemap', src))
        return
    end
    mapname = sanitizeMapName(mapname)

    local out = {}
    for i, p in ipairs(props) do
        out[#out + 1] = {
            id = i,
            model = p.model,
            x = p.x, y = p.y, z = p.z,
            rx = p.rx, ry = p.ry, rz = p.rz,
        }
    end

    saveMapFile(mapname, out)
    TriggerClientEvent('rex-mapeditor:client:mapSaved', src, mapname, #out)
end)

-- ---------------------------------------------------------------------
-- Load a map's props to the requesting client
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:server:loadMap', function(mapname)
    local src = source
    if not isAuthorized(src) then return end
    mapname = sanitizeMapName(mapname)

    local props = loadMapFile(mapname)
    TriggerClientEvent('rex-mapeditor:client:mapLoaded', src, mapname, props)
end)

-- ---------------------------------------------------------------------
-- Remove a single prop (by persisted id) from a map file immediately
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:server:removeProp', function(mapname, id)
    local src = source
    if not isAuthorized(src) then return end
    mapname = sanitizeMapName(mapname)

    local props = loadMapFile(mapname)
    local out = {}
    for _, p in ipairs(props) do
        if p.id ~= id then
            out[#out + 1] = p
        end
    end
    saveMapFile(mapname, out)
end)

-- ---------------------------------------------------------------------
-- Persist a removal of an EXISTING base-game world prop, then broadcast it
-- to every connected client so it disappears for everyone immediately.
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:server:removeWorldProp', function(mapname, model, x, y, z)
    local src = source
    if not isAuthorized(src) then
        print(locale('server_unauthorized_removeworldprop', src))
        return
    end
    mapname = sanitizeMapName(mapname)

    local removals = loadRemovedPropsFile(mapname)
    for _, r in ipairs(removals) do
        if isSameRemoval(r, model, x, y, z) then
            -- Already tracked - just make sure every client has it applied.
            TriggerClientEvent('rex-mapeditor:client:worldPropRemoved', -1, mapname, model, x, y, z)
            return
        end
    end

    removals[#removals + 1] = { model = model, x = x, y = y, z = z }
    saveRemovedPropsFile(mapname, removals)

    TriggerClientEvent('rex-mapeditor:client:worldPropRemoved', -1, mapname, model, x, y, z)
end)

-- ---------------------------------------------------------------------
-- Send the full list of persisted world-prop removals for a map to
-- whoever asks (every player needs this applied, not just admins, so
-- there's no permission check here - it's read-only).
-- ---------------------------------------------------------------------
RegisterNetEvent('rex-mapeditor:server:requestRemovedProps', function(mapname)
    local src = source
    mapname = sanitizeMapName(mapname)
    local removals = loadRemovedPropsFile(mapname)
    TriggerClientEvent('rex-mapeditor:client:removedPropsList', src, mapname, removals)
end)

-- ---------------------------------------------------------------------
-- Export a map to CMapData (.ymap) XML - see server/ymap.lua
-- ---------------------------------------------------------------------
local function doExport(mapname)
    mapname = sanitizeMapName(mapname)
    local props = loadMapFile(mapname)
    local removals = loadRemovedPropsFile(mapname)
    if #props == 0 and #removals == 0 then
        return nil, locale('export_no_data', mapname)
    end
    local xml = BuildYmapXml(mapname, props, removals)
    local outPath = ('data/%s.ymap.xml'):format(mapname)
    SaveResourceFile(GetCurrentResourceName(), outPath, xml, -1)
    return outPath, #props, #removals
end

RegisterNetEvent('rex-mapeditor:server:exportYmap', function(mapname)
    local src = source
    if not isAuthorized(src) then return end

    local outPath, propCountOrErr, removalCount = doExport(mapname)
    if not outPath then
        TriggerClientEvent('rex-mapeditor:client:ymapExported', src, propCountOrErr)
        return
    end

    TriggerClientEvent(
        'rex-mapeditor:client:ymapExported',
        src,
        locale('export_success', outPath, propCountOrErr, removalCount)
    )
end)

RegisterCommand('exportymap', function(source, args)
    if source ~= 0 and not isAuthorized(source) then return end
    local outPath, propCountOrErr, removalCount = doExport(args[1])
    if not outPath then
        print('[rex-mapeditor] ' .. propCountOrErr)
        return
    end
    print(locale('server_export_log', propCountOrErr, removalCount, outPath))
end, true)
