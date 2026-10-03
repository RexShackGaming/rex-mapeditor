Config = {}

-- Command / keybind used to open the placement tool
Config.OpenCommand = 'mapeditor'
Config.OpenKey = 'F6'

-- Who is allowed to use the tool.
-- Set to false to allow every player (not recommended on a live server).
Config.RestrictToAdmins = true
-- A player is allowed if EITHER check passes:
Config.AdminAce = 'command'            -- ACE permission, e.g. add_ace group.admin command allow
Config.AdminGroups = { 'admin', 'god' } -- RSG-Core permission groups (RSGCore.Functions.HasPermission)

-- Max raycast distance (meters) used to find a placement point in front of the camera
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

-- Radius (meters) used to hide map-baked props (type "Map / Building") that
-- have no deletable entity, at the removal spot.
Config.ModelHideRadius = 1.5
