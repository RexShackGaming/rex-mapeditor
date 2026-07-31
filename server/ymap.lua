-- ---------------------------------------------------------------------
-- CMapData (.ymap) XML builder
--
-- IMPORTANT: this produces the plaintext "meta XML" representation of a
-- CMapData resource, in the same schema CodeWalker uses for its XML
-- import/export. It is NOT a binary .ymap file. RedM streams binary
-- .ymap files, so to actually use this in-game you need to open this
-- XML in CodeWalker (File -> XML -> Import Ymap, RDR3 project mode) and
-- export it as a binary .ymap, then add it to a stream/data resource.
-- This tool gets you the entity placement data out of the game world in
-- a standard, importable format - the binary conversion step still goes
-- through CodeWalker (or an equivalent RAGE resource compiler) because
-- that step requires access to RDR3's archetype/asset database that only
-- those tools maintain.
-- ---------------------------------------------------------------------

local function escapeXml(str)
    str = tostring(str)
    str = str:gsub('&', '&amp;')
    str = str:gsub('<', '&lt;')
    str = str:gsub('>', '&gt;')
    str = str:gsub('"', '&quot;')
    return str
end

-- Convert Euler angles (degrees, XYZ order as used by SetEntityRotation format 2)
-- into a quaternion (x,y,z,w) as expected by CMapData entityDef "rotation".
local function eulerToQuaternion(rxDeg, ryDeg, rzDeg)
    local rx = math.rad(rxDeg or 0.0) * 0.5
    local ry = math.rad(ryDeg or 0.0) * 0.5
    local rz = math.rad(rzDeg or 0.0) * 0.5

    local cx, sx = math.cos(rx), math.sin(rx)
    local cy, sy = math.cos(ry), math.sin(ry)
    local cz, sz = math.cos(rz), math.sin(rz)

    -- XYZ intrinsic rotation order
    local qx = sx * cy * cz - cx * sy * sz
    local qy = cx * sy * cz + sx * cy * sz
    local qz = cx * cy * sz - sx * sy * cz
    local qw = cx * cy * cz + sx * sy * sz

    return qx, qy, qz, qw
end

function BuildYmapXml(mapname, props, removals)
    removals = removals or {}
    local lines = {}
    local function w(s) lines[#lines + 1] = s end

    w('<?xml version="1.0" encoding="UTF-8"?>')

    if #removals > 0 then
        w('<!--')
        w('  World-prop removals for this map (not part of CMapData - RedM/RDR3 has')
        w('  no supported way to bake "delete this entity" into a distributable ymap,')
        w('  since base map props live inside Rockstar\'s own packed archives).')
        w('')
        w('  This resource enforces these removals at runtime instead (see')
        w('  client/main.lua - applyWorldPropRemoval). The list below is provided so')
        w('  you can ALSO manually delete the equivalent entities from the vanilla')
        w('  ymap yourself in CodeWalker, if you additionally want a true binary-level')
        w('  removal for single-player/offline use:')
        w('')
        for _, r in ipairs(removals) do
            w(('    model=%s  x=%.6f y=%.6f z=%.6f'):format(tostring(r.model), r.x, r.y, r.z))
        end
        w('-->')
    end

    w('<CMapData>')
    w('  <name>' .. escapeXml(mapname) .. '</name>')
    w('  <parent />')
    w('  <flags value="0" />')
    w('  <contentFlags value="0" />')
    -- Streaming extents are approximate bounding boxes around all placed props
    -- (and removal reference points, so the box still means something on a
    -- map with only removals and no placed props). CodeWalker will happily
    -- recompute these on import/export, so exact precision here isn't critical.
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for _, p in ipairs(props) do
        minX = math.min(minX, p.x); maxX = math.max(maxX, p.x)
        minY = math.min(minY, p.y); maxY = math.max(maxY, p.y)
        minZ = math.min(minZ, p.z); maxZ = math.max(maxZ, p.z)
    end
    for _, r in ipairs(removals) do
        minX = math.min(minX, r.x); maxX = math.max(maxX, r.x)
        minY = math.min(minY, r.y); maxY = math.max(maxY, r.y)
        minZ = math.min(minZ, r.z); maxZ = math.max(maxZ, r.z)
    end
    if minX == math.huge then
        -- Nothing at all (shouldn't happen - doExport guards against this)
        minX, minY, minZ = 0.0, 0.0, 0.0
        maxX, maxY, maxZ = 0.0, 0.0, 0.0
    end
    -- pad the box a little
    minX = minX - 10.0; minY = minY - 10.0; minZ = minZ - 10.0
    maxX = maxX + 10.0; maxY = maxY + 10.0; maxZ = maxZ + 10.0

    w(('  <streamingExtentsMin x="%.6f" y="%.6f" z="%.6f" />'):format(minX, minY, minZ))
    w(('  <streamingExtentsMax x="%.6f" y="%.6f" z="%.6f" />'):format(maxX, maxY, maxZ))
    w(('  <entitiesExtentsMin x="%.6f" y="%.6f" z="%.6f" />'):format(minX, minY, minZ))
    w(('  <entitiesExtentsMax x="%.6f" y="%.6f" z="%.6f" />'):format(maxX, maxY, maxZ))

    w('  <entities>')
    for i, p in ipairs(props) do
        local qx, qy, qz, qw = eulerToQuaternion(p.rx, p.ry, p.rz)
        w('    <Item type="CEntityDef">')
        w('      <archetypeName>' .. escapeXml(p.model) .. '</archetypeName>')
        w('      <flags value="' .. tostring(Config.DefaultFlags) .. '" />')
        w('      <guid value="' .. tostring(1000000 + i) .. '" />')
        w('      <position x="' .. ('%.6f'):format(p.x) .. '" y="' .. ('%.6f'):format(p.y) .. '" z="' .. ('%.6f'):format(p.z) .. '" />')
        w('      <rotation x="' .. ('%.8f'):format(qx) .. '" y="' .. ('%.8f'):format(qy) .. '" z="' .. ('%.8f'):format(qz) .. '" w="' .. ('%.8f'):format(qw) .. '" />')
        w('      <scaleXY value="1.00000000" />')
        w('      <scaleZ value="1.00000000" />')
        w('      <parentIndex value="-1" />')
        w('      <lodDist value="' .. ('%.6f'):format(Config.DefaultLodDist) .. '" />')
        w('      <childLodDist value="' .. ('%.6f'):format(Config.DefaultChildLodDist) .. '" />')
        w('      <lodLevel>LODTYPES_DEPTH_ORPHANHD</lodLevel>')
        w('      <numChildren value="0" />')
        w('      <priorityLevel>' .. tostring(Config.DefaultPriorityLevel) .. '</priorityLevel>')
        w('      <ambientOcclusionMultiplier value="255" />')
        w('      <artificialAmbientOcclusion value="255" />')
        w('      <tintValue value="0" />')
        w('    </Item>')
    end
    w('  </entities>')
    w('</CMapData>')

    return table.concat(lines, '\n')
end
