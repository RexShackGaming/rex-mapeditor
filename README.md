# rex-mapeditor

An in-game prop placement tool for RedM/RSG-Core servers. Browse and spawn static props from an NUI menu, position them with keyboard controls, save your layout, and export it to a CMapData (`.ymap`) XML file for use in CodeWalker.

## Features

- **NUI prop browser** — searchable, categorized list of common RDR2 static props, plus a free-text field to spawn any model by name/hash.
- **Full prop library** — ships all 14,856 props grouped by category/subcategory. Type 2+ characters in the search box to search across it (results are capped at 250 matches at a time to keep the UI responsive); it's not shown by default to keep the menu fast on open.
- **In-world placement controls** — newly spawned props enter a "placement mode": arrow keys move, Page Up/Down adjust height, Q/E rotate yaw, `[`/`]` fine-tune pitch, Enter confirms, Backspace/Esc cancels. Hold Shift for faster movement/rotation. Bindings use RDR3's real named controls (`INPUT_FRONTEND_*`, `INPUT_CREATOR_LT/RT`, etc.) rather than GTA V's numeric control IDs, which don't map correctly in RedM.
- **Placement Panel (click-based alternative to keybinds)** — while placing a prop, a small, semi-transparent, draggable panel appears with buttons for every placement action (move, height, yaw, pitch, a Fast-movement toggle, Confirm, Cancel). Click once to nudge, or click-and-hold to repeat, same as holding a key. Drag it by its header to keep it clear of the prop you're positioning — it never takes over the screen: uses `SetNuiFocusKeepInput` so camera look and all the keybinds above keep working at the same time, letting you freely mix mouse clicks and keys.
- **Character locked during placement** — the player ped is frozen in place and every normal movement/combat/interaction control (walking, jumping, firing, reloading, melee, mounting, whistling for a horse, etc.) is disabled for the duration of placement mode, so the character can't wander off, get shoved around, or accidentally do something else while you're positioning a prop. Everything is restored the moment you confirm or cancel.
- **Placed prop list** — every prop you've placed shows in the menu with its coordinates, a teleport-to button, and a delete button.
- **Aim-and-delete, dual purpose** — aim your camera at anything and press Delete:
  - If it's a prop *this tool placed*, it's removed from the saved map as usual.
  - If it's an **existing base-game world prop**, it's added to a persistent per-map removal list instead (see below), deleted immediately, and broadcast so it disappears for every connected player too.
  This listens to RDR3's native `INPUT_FRONTEND_DELETE` control directly, so it works even if `RegisterKeyMapping` isn't available on your server build.
- **Aim-and-fire delete mode** — press **B** (or run `/propdeleteaim`) to toggle a mode where you point a drawn weapon at a prop and pull the trigger to delete it, using the weapon's own sight as a clear visual preview of what will be removed. Targeting uses RDR3's real free-aim natives (`IsPlayerFreeAiming` / `GetEntityPlayerIsFreeAimingAt`) rather than a plain camera raycast, so it tracks whatever the weapon's reticle is actually locked onto. The weapon is prevented from actually discharging while this mode is active (no bullet, no ammo used, no damage/noise) — firing is only read as a confirm gesture. Uses the same placed-prop/world-prop deletion logic as the Delete-key shortcut above. Auto-disables if you start placing/grabbing a prop.
- **Persistent world-prop removal** — removed base-game props are stored in `data/<mapname>.removed.json` (model + coordinates). On resource start, and whenever a map is loaded, the full removal list is sent to clients and enforced by a background loop that re-deletes matching entities if the game respawns them when the area streams back in. This is a runtime removal, not a file edit — see the note below on why that's the right approach here.
- **Save / Load maps** — persist your current layout to a named JSON file on the server, and reload it later (also restores the props in the world and re-applies that map's world-prop removals).
- **Export to ymap XML** — generates a CodeWalker-compatible CMapData XML file with accurate positions, rotations (converted to quaternions), and streaming extents for every saved prop, plus an XML comment block listing any world-prop removals for that map (model + coordinates) for manual cross-referencing in CodeWalker.
- **Permission-gated** — save/load/remove/export/world-prop-removal actions are re-checked server-side via ACE permission, independent of the client. Reading back removal lists (so every player sees a consistent world) is not permission-gated, since it's read-only.

### A note on ymap export and world-prop removal

RedM streams binary `.ymap` files, and there is no public tool to compile RDR3 map resources directly to binary. The export produces the **plaintext XML** representation of a CMapData resource (the same schema CodeWalker uses for XML import/export). To get a usable binary `.ymap`:

1. Open CodeWalker (RDR3 project mode).
2. File → XML → Import Ymap, and select the exported `.ymap.xml` file.
3. Export it from CodeWalker as a binary `.ymap`.
4. Add the resulting file to a stream/data resource on your server.

Removing an *existing* base-game prop can't be done the same way — those props live inside Rockstar's own packed game archives, and there's no supported way for a distributable multiplayer resource to bake a "delete this entity" instruction into a ymap that affects them. Editing those files directly would mean shipping modified copies of Rockstar's assets, which isn't something this tool does. Instead, world-prop removals are enforced live: every client deletes matching entities near the recorded coordinates and keeps re-deleting them if they respawn when the area streams back in. The result is the same from a player's perspective (the prop stays gone, every session, for everyone), it just isn't a file-level edit. If you additionally want a true binary-level removal for single-player/offline use, the exported ymap XML lists the removed props' model and coordinates in a comment block so you can manually delete the equivalent entities from the vanilla ymap yourself in CodeWalker.

## Installation

1. Copy the `rex-mapeditor` folder into your server's `resources` directory.
2. Add to your `server.cfg`:
   ```
   ensure rex-mapeditor
   ```
3. Make sure it starts **after** `rsg-core`, `oxmysql`, and `ox_lib` (required for in-game notifications).
4. Grant the ACE permission needed to use the tool (see Configuration below), e.g.:
   ```
   add_ace group.admin command allow
   add_principal identifier.xxxxxxxx group.admin
   ```
5. Restart the resource or restart your server.

## Usage

- Press **F6** (or run `/mapeditor`) in-game to open the menu. F6 is bound via `RegisterKeyMapping`, which isn't available on every RedM build — if F6 does nothing, use `/mapeditor`, or bind it yourself with `bind keyboard F6 mapeditor` in the F8 console.
- Search or scroll the prop library and click **Spawn**, or type an exact model name and click **Spawn typed model**.
- Position the prop with the in-world controls (arrows/PageUp/PageDown/Q/E/`[`/`]`, then Enter to confirm) or with the draggable Placement Panel that appears on screen — click its buttons instead, or mix both.
- Repeat for as many props as you want, then set a map name and click **Save Map**.
- Click **Load** to restore a previously saved map's props into the world.
- Click **Export to .ymap** to generate the CMapData XML (written to `data/<mapname>.ymap.xml` inside the resource folder).
- Console command `exportymap <mapname>` is also available for server-side use.
- To delete a prop, either aim your camera at it and press **Delete**, or press **B** to toggle aim-and-fire delete mode, point a drawn weapon at it, and pull the trigger.

## Configuration

All settings live in `config.lua`.

| Setting | Description | Default |
|---|---|---|
| `Config.OpenCommand` | Command name used to open the menu | `'mapeditor'` |
| `Config.OpenKey` | Default keybind (rebindable in FiveM/RedM keybind settings) | `'F6'` |
| `Config.RestrictToAdmins` | If `true`, only players with the configured ACE permission can use the tool | `true` |
| `Config.AdminAce` | ACE permission string required when `RestrictToAdmins` is `true` | `'command'` |
| `Config.SpawnDistance` | Fallback spawn distance (meters) from camera | `3.0` |
| `Config.MaxRaycastDistance` | Max raycast distance used to find a placement point | `50.0` |
| `Config.MoveStep` / `Config.MoveStepFast` | Movement step size per tick (normal / Shift held), in meters | `0.05` / `0.25` |
| `Config.RotateStep` / `Config.RotateStepFast` | Rotation step size per tick (normal / Shift held), in degrees | `1.0` / `5.0` |
| `Config.HeightStep` | Height adjustment step per tick, in meters | `0.05` |
| `Config.DefaultLodDist` | LOD distance written into exported ymap entities | `500.0` |
| `Config.DefaultChildLodDist` | Child LOD distance written into exported ymap entities | `0.0` |
| `Config.DefaultPriorityLevel` | Streaming priority level written into exported ymap entities | `'PRI_REQUIRED'` |
| `Config.DefaultFlags` | Entity flags written into exported ymap entities | `32` |
| `Config.RemovalMatchRadius` | Radius (meters) used to find/match an existing base-game prop for the persistent world-prop removal feature | `1.5` |

The NUI Prop Library has no static/curated list. By default it shows only your **Favorites** (see below). Type 2+ characters into the search box to query the full 14,856-prop Spooni library (`html/spooni_props.json`); star (☆) any result to save it as a favorite, which persists server-side and is shared with every tool user — favorites show up at the top of the library on every future menu open, so you don't have to re-search for props you use often. Use the free-text search field to spawn any model by its exact name or hash even if it isn't in the Spooni library.

## File structure

```
rex-mapeditor/
├── fxmanifest.lua
├── config.lua
├── client/
│   └── main.lua        -- menu, placement controls, entity spawning/tracking
├── server/
│   ├── main.lua         -- save/load/remove/export events, permission checks
│   └── ymap.lua         -- CMapData XML builder
├── html/
│   ├── index.html
│   ├── style.css
│   ├── app.js               -- NUI logic
│   └── spooni_props.json    -- full 14,856-prop Spooni library, search-only
└── data/                -- saved maps (<mapname>.json), world-prop removals
                          -- (<mapname>.removed.json), and exported ymap XML
                          -- (<mapname>.ymap.xml) land here
```

## Permissions

Server-side authorization is the real security boundary: every save, load, remove, and export event re-checks `IsPlayerAceAllowed(source, Config.AdminAce)` regardless of what the client sends. The client-side check only hides prompts from non-admins for UX purposes and should not be relied on for security by itself.
