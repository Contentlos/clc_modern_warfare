# clc_modern_warfare_sim

A server-authoritative modern warfare simulation for FiveM. Factions fight for territory, vehicles are spawned via depots, and resources/tickets drive strategy. Includes NUI HUD + map with strict open/close focus discipline.

## Dependencies (optional)
- **oxmysql** (required only if `Config.UseSQL = true`)
- **ox_lib** (optional)
- **ox_target** (optional)

## Quick start
1) Add to your server.cfg:
```
ensure clc_modern_warfare_sim
```
2) Configure factions, zones, vehicles in `shared/config.lua`.
3) If using SQL, ensure `oxmysql` is started **before** this resource.

## Keybinds
- **F1**: Toggle HUD or open faction selection (if not chosen)
- **F3**: Toggle Map panel
- **E**: Open Depot panel when near a depot
- **ESC / BACKSPACE**: Close UI

## Commands
- `/joinfaction <factionId>` ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â choose a faction
- `/warstatus` ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â print war status
- `/war_reset` ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â reset war state (admin)
- `/war_setzone <zoneId> <factionId|neutral>` ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â force zone owner (admin)
- `/war_giveres <factionId> <fuel|ammo|parts> <amount>` ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â give resources (admin)

## Persistence
- If SQL enabled, war snapshot and player factions are stored in MySQL.
- If SQL disabled, JSON files are used in the resource folder.

## Troubleshooting
- **SQL errors**: ensure `oxmysql` is started and Config.UseSQL=true.
- **Vehicles not spawning**: check faction resources and depot config.
- **UI stuck**: UI has explicit open/close with ESC/BACKSPACE; use `/warstatus` to verify server state.

## Notes
- Server is authoritative; client only requests actions.
- No globals for game state; modules are explicit.
