local Constants = {
  WarPhases = {
    Peace = 0,
    Active = 1,
    Paused = 2,
    Concluded = 3
  },
  ZoneState = {
    Neutral = 0,
    Contested = 1,
    Captured = 2
  },
  VehicleState = {
    Active = 1,
    Disabled = 2,
    Destroyed = 3
  },
  ResourceTypes = {
    Fuel = 'fuel',
    Ammo = 'ammo',
    Parts = 'parts'
  },
  Events = {
    State = 'war:state',
    Zones = 'war:zones',
    Resources = 'war:resources',
    Vehicles = 'war:vehicles',
    PlayerInfo = 'war:playerInfo',
    SpawnResult = 'mw:spawnResult',
    RequestJoin = 'war:requestJoinFaction',
    RequestSpawn = 'war:requestSpawnVehicle',
    RequestRepair = 'war:requestRepairVehicle',
    RequestStatus = 'war:requestStatus'
  },
  UI = {
    Open = 'ui:open',
    Close = 'ui:close',
    Update = 'ui:update',
    SelectFaction = 'ui:selectFaction',
    SpawnVehicle = 'ui:spawnVehicle',
    RequestRepair = 'ui:requestRepair'
  },
  Keybinds = {
    Hud = 'war_hud_toggle',
    Map = 'war_map_toggle',
    Close = 'war_ui_close',
    Depot = 'war_depot_open'
  },
  Commands = {
    JoinFaction = 'joinfaction',
    WarStatus = 'warstatus',
    WarReset = 'war_reset',
    WarSetZone = 'war_setzone',
    WarGiveRes = 'war_giveres',
    AIStatus = 'ai_status',
    AIClear = 'ai_clear'
  }
}

return Constants
