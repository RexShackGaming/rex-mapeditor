Config = {}

-- Command / keybind used to open the placement tool
Config.OpenCommand = 'mapeditor'
Config.OpenKey = 'F6'

-- Who is allowed to use the tool.
-- Set to false to allow every player (not recommended on a live server).
Config.RestrictToAdmins = true
Config.AdminGroups = { 'admin', 'god' } -- checked against RSGCore.Functions.HasPermission / Player.PlayerData.job? we use ACE below
Config.AdminAce = 'command' -- ACE permission required, e.g. add_ace identifier.xxxx group.admin command allow

-- Distance (meters) from the camera that a prop is raycast-placed at when spawned
Config.SpawnDistance = 3.0
Config.MaxRaycastDistance = 50.0

-- Movement/rotation step sizes while a prop is in "placement" (grabbed) mode
Config.MoveStep = 0.05          -- meters per tick when nudging with arrow keys
Config.MoveStepFast = 0.25      -- meters per tick when holding shift
Config.RotateStep = 1.0         -- degrees per tick
Config.RotateStepFast = 5.0
Config.HeightStep = 0.015     -- meters per tick when nudging height (Page Up/Down)
Config.HeightStepFast = 0.075 -- meters per tick when holding shift

-- Default streaming/LOD values written into exported ymap entities
Config.DefaultLodDist = 500.0
Config.DefaultChildLodDist = 0.0
Config.DefaultPriorityLevel = 'PRI_REQUIRED'
Config.DefaultFlags = 32

-- Radius (meters) used when matching/finding an existing base-game world
-- prop to delete for the persistent world-prop removal feature. Also used
-- to de-duplicate removal entries that are effectively the same spot.
Config.RemovalMatchRadius = 1.5

-- The Prop Library NUI has no static/curated prop list - it shows only your
-- Favorites (persisted server-side, see server/main.lua) plus live search
-- results across the full Spooni prop library (14,856 props). Search for
-- anything and star it to keep it handy next time.
