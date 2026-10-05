# rex-mapeditor

An in-game prop placement tool for RedM / RSG Framework servers. Browse and spawn static props from an NUI menu, position them with keyboard or mouse controls, remove existing world props, save your layout, and export it to a CMapData (`.ymap`) XML file for CodeWalker.

<img width="1920" height="1080" alt="20261005075837_1" src="https://github.com/user-attachments/assets/b259b01b-0ac3-487f-ac6e-dc7c89c3f55c" />

## Features

- **Prop Library** — shows your **Favorites** and custom library entries on open. Type 2+ characters to search the full 14,856-prop library (`html/props.json`, capped at 250 results per search). Type any exact model name or numeric hash and click **Spawn typed model** to spawn something that isn't listed.
- **Favorites & custom library** — star (☆) any prop to keep it at the top of the list. **+ Add to Library** adds your own models; every row has ✎ (edit model/label/category) and ✕ (remove). Bundled entries are never edited on disk — edits are stored as overrides in `data/custom_props.json`. Favorites and library changes are shared with every tool user.
- **Placement mode** — arrows move (relative to the camera), Page Up/Down change height, Q/E rotate yaw, `[`/`]` pitch, Enter confirms, Backspace/Esc cancels. Hold Shift for faster steps. The character is frozen and normal movement/combat/interaction controls are disabled until you confirm or cancel.
- **Placement Panel** — a small draggable panel with buttons for every placement action (click to nudge, hold to repeat, plus a Fast toggle). Keybinds keep working at the same time.
- **Placed prop list** — every placed prop is listed with teleport and delete buttons.
- **Delete key** — aim your camera at something and press **Delete**:
  - a prop placed with this tool is removed from the map;
  - any other world prop is added to the map's persistent removal list, deleted, and removed for every connected player.
- **Aim-and-fire delete mode** — press **B** (or `/propdeleteaim`) to toggle. Draw a weapon, aim at a prop and pull the trigger to delete it. The weapon never actually fires while this mode is on. It switches off automatically when you start placing a prop.
- **Aim inspector** — while aiming a weapon, a small card shows the model name/hash, type, coords, rotation, distance and whether the target can be removed, and the prop is outlined (green = deletable, amber = map-baked and will be hidden, red = can't be removed).
- **Persistent world-prop removal** — stored per map in `data/<map>.removed.json`. Removals for the `default` map are applied for every player on join. A background loop re-deletes nearby matches if the game streams them back in; map-baked props without an entity are hidden with a model hide.
- **Removed World Props list & restore** — the Map panel has a collapsible **Removed World Props (n)** section listing every world prop removed on the current map (model name or hash, plus coords). **TP** teleports you to the spot; **Restore** (with confirmation) takes it off the map's removal list for everyone. Hidden map-baked props reappear immediately. For deleted streamed objects, each client spawns a local stand-in at the saved position and rotation so the prop reappears instantly; the stand-in is dropped once the player is 350m+ away and the game's own object takes over when the area streams back in. Removals now record the prop's rotation — older entries without one restore facing the default direction until the area reloads.
- **IMAP removal** — `/imapremove <hash|name>` and `/imaprestore <hash|name>` unload or restore a whole map section for everyone, saved per map in `data/<map>.imaps.json`.
- **Save / Load maps** — save your layout to `data/<map>.json` and load it back later (also re-applies that map's world-prop and IMAP removals).
- **Export to ymap XML** — writes `data/<map>.ymap.xml`, a CodeWalker-compatible CMapData XML with positions, quaternion rotations and streaming extents, plus a comment block listing the map's world-prop removals for reference.

### A note on ymap export and world-prop removal

RedM streams binary `.ymap` files, and there's no public tool that compiles RDR3 map resources straight to binary. The export is the **XML** form of a CMapData resource. To use it:

1. Open CodeWalker (RDR3 project mode).
2. File → XML → Import Ymap, and select the exported `.ymap.xml`.
3. Export it from CodeWalker as a binary `.ymap`.
4. Add the file to a stream/data resource on your server.

Base-game props live inside Rockstar's packed archives, so a distributable resource can't remove them with a file edit. Instead, removals are enforced live on every client. The result is the same for players (the prop stays gone, for everyone, every session). The exported XML lists removed props so you can also delete them from the vanilla ymap in CodeWalker if you want a file-level edit.

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)

## Installation

1. Copy the `rex-mapeditor` folder into your server's `resources` directory.
2. Add to `server.cfg` (after `ox_lib`):
   ```
   ensure rex-mapeditor
   ```
3. Give admins access (see [Permissions](#permissions) below), e.g.:
   ```
   add_ace group.admin command allow
   add_principal identifier.xxxxxxxx group.admin
   ```
4. Restart the resource or the server.

## Usage

- Press **F6** (or run `/mapeditor`) to open/close the menu. If F6 does nothing on your build, use `/mapeditor` or `bind keyboard F6 mapeditor` in the F8 console.
- Search the library and click **Spawn**, then position the prop and press Enter (or click **Confirm**).
- Enter a map name, then **Save Map**, **Load**, or **Export to .ymap**. Map names may only contain letters, numbers, `_` and `-`.
- **Esc** cancels placement while placing, otherwise closes the menu.
- Server console: `exportymap <mapname>`.

| Command | Default key | Description |
|---|---|---|
| `/mapeditor` | F6 | Open / close the menu |
| `/propdelete` | Delete | Delete the prop under the camera crosshair |
| `/propdeleteaim` | B | Toggle aim-and-fire delete mode |
| `/imapremove <hash\|name>` | — | Remove an IMAP for the current map |
| `/imaprestore <hash\|name>` | — | Restore an IMAP for the current map |
| `exportymap <mapname>` | — | Server console / ACE: export a map to XML |

## Configuration

All settings are in `shared/config.lua`.

| Setting | Description | Default |
|---|---|---|
| `Config.OpenCommand` | Command used to open the menu | `'mapeditor'` |
| `Config.OpenKey` | Default keybind (rebindable in key settings) | `'F6'` |
| `Config.RestrictToAdmins` | Only admins (ACE or RSG-Core group) can use the tool | `true` |
| `Config.AdminAce` | ACE permission that grants access | `'command'` |
| `Config.AdminGroups` | RSG-Core permission groups that grant access | `{ 'admin', 'god' }` |
| `Config.MaxRaycastDistance` | Max raycast distance used to find a placement point | `50.0` |
| `Config.MoveStep` / `Config.MoveStepFast` | Move step per tick (normal / Shift), meters | `0.05` / `0.25` |
| `Config.RotateStep` / `Config.RotateStepFast` | Rotation step per tick (normal / Shift), degrees | `1.0` / `5.0` |
| `Config.HeightStep` / `Config.HeightStepFast` | Height step per tick (normal / Shift), meters | `0.015` / `0.075` |
| `Config.DefaultLodDist` | LOD distance written to exported entities | `500.0` |
| `Config.DefaultChildLodDist` | Child LOD distance written to exported entities | `0.0` |
| `Config.DefaultPriorityLevel` | Streaming priority written to exported entities | `'PRI_REQUIRED'` |
| `Config.DefaultFlags` | Entity flags written to exported entities | `32` |
| `Config.RemovalMatchRadius` | Radius used to match a world prop for removal | `1.5` |
| `Config.ModelHideRadius` | Radius used to hide map-baked props | `1.5` |

## Languages

All player-facing text — notifications, keybind labels, server console messages and the entire NUI (menu, placement panel, confirm box, aim inspector) — lives in `locales/<lang>.json`. Included: `en`, `de`, `el`, `es`, `fr`, `ja`, `nl`, `pl`, `pt-br`, `ro`.

Pick the language with ox_lib's convar in `server.cfg`, e.g.:
```
setr ox:locale de
```

Keys starting with `ui_` are sent to the NUI automatically, so to add a language just copy `en.json` to `locales/<code>.json` and translate the values (keep every `%s` placeholder, in the same order).

## File structure

```
rex-mapeditor/
├── fxmanifest.lua
├── shared/
│   └── config.lua
├── client/
│   └── main.lua           -- menu, placement, deletion, inspector, removals
├── server/
│   ├── main.lua           -- permission checks, validation, save/load/export
│   ├── ymap.lua           -- CMapData XML builder
│   └── versionchecker.lua
├── html/
│   ├── index.html
│   ├── style.css
│   ├── app.js             -- NUI logic
│   └── props.json         -- 14,856-prop library (search only)
├── locales/
│   └── en, de, el, es, fr, ja, nl, pl, pt-br, ro (.json)
└── data/                  -- created at runtime: <map>.json, <map>.removed.json,
                           -- <map>.imaps.json, <map>.ymap.xml,
                           -- favorites.json, custom_props.json
```

## Permissions

When `Config.RestrictToAdmins = true`, a player can use the tool if **any** of these pass on the server:

| Check | Example `server.cfg` |
|---|---|
| ACE permission `Config.AdminAce` (default `command`) | `add_ace rsgcore.god command allow` |
| ACE named after a group in `Config.AdminGroups` (`god`, `admin`) | `add_ace rsgcore.god god allow` |
| ACE `rsgcore.<group>` (e.g. `rsgcore.god`) | `add_ace rsgcore.god rsgcore.god allow` |
| RSG-Core `RSGCore.Functions.HasPermission(src, group)` | set by rsg-core / txAdmin |

A typical RSG setup that works:

```
# give the group its permissions
add_ace rsgcore.god command allow
add_ace rsgcore.god god allow

# put your licence in that group
add_principal identifier.license:YOUR_LICENSE rsgcore.god
```

### Troubleshooting "You do not have permission to use this tool"

1. **`add_principal` alone grants nothing.** It only puts you *in* a group. The group needs `add_ace ... allow` lines (above) or nobody in it has any permissions.
2. **Restart the server** (or run `refresh` then restart the resource) after editing `server.cfg` — ACE lines are read at startup.
3. **Check your identifier.** Run `status` (or open txAdmin → Players) and compare the `license:` value with the one in your `add_principal` line. Use `license:`, not `license2:`.
4. **Check the line order.** `add_ace` / `add_principal` lines should be in `server.cfg` itself (or an `exec`'d file), not inside a resource.
5. **Test the ACE in the server console:** `test_ace player.<id> command` (replace `<id>` with your in-game server id). It should print `allow`.
6. **Read the server console.** A refused player logs `[rex-mapeditor] Access denied for <name> (id <id>) ...`. If you see that line, the request reached the server and failed the checks above. If you see nothing, the resource probably failed to start — look for Lua errors when it loads.
7. **Using a different group name?** Add it to `Config.AdminGroups` in `shared/config.lua`, or change `Config.AdminAce` to an ACE your admins already have.
8. **Just testing locally?** Set `Config.RestrictToAdmins = false` to allow everyone (not for live servers).

## Security

- Every write event (save, load, delete, world-prop/IMAP removal and restore, export, favorites, library edits) re-checks access on the server (`Config.AdminAce` ACE or an RSG-Core group in `Config.AdminGroups`), validates every argument (types, string lengths, coordinate ranges, model names, max 2,000 props per map) and is rate-limited per player.
- The client asks the server whether the player has access (`lib.callback`) and only enables the menu, Delete key, delete-aim mode, inspector and IMAP commands for authorized players.
- Favorites and library updates are sent only to authorized players. Saved data files in `data/` are not shipped to clients.
- If an admin is refused, the server console prints an "Access denied" line with their name and id.
- Reading the removal lists (`requestRemovedProps` / `requestImaps`) is intentionally open, since every player needs them applied.
