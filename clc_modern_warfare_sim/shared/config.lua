local Utils = MW.require('shared/utils.lua')

local Config = {
  Version = 1,
  Debug = false,
  UseSQL = true,
  SaveInterval = 60,
  War = {
    AutoStart = true,
    ZoneTick = 5,
    ResourceTick = 60,
    VehicleTick = 5,
    CaptureTime = 120,
    CaptureDecay = 30,
    MinPlayersToCapture = 1,
    RequireVehicleForCapture = true,
    AFKSeconds = 45,
    AFKMoveThreshold = 1.5,
    TicketStart = 500,
    TicketLossPerVehicle = 5
  },
  AI = {
    Enabled = true,
    TickSeconds = 6,
    DefaultStrategic = true,
    DefaultIntensity = 1.0,
    PlayerRadius = 200.0,
    HostRadius = 1200.0,
    VisibilityDistance = 800.0,
    BaseDefenders = 2,
    MinDefenders = 2,
    MaxDefenders = 12,
    PerPlayer = 1,
    PerVehicle = 1,
    PerimeterRatio = 0.35,
    ReinforceRatio = 0.25,
    PerimeterBuffer = 60.0,
    ReinforceBuffer = 100.0,
    DefenderBlockCount = 8,
    MaxCaptureBlock = 0.85,
    DespawnNoActivity = 180,
    DespawnStep = 2,
    Accuracy = 28,
    CombatAbility = 1,
    CombatRange = 1,
    CombatMovement = 2,
    Models = { 's_m_y_marine_01', 's_m_y_soldier_01', 's_m_y_blackops_01' },
    Weapons = {
      usa = 'WEAPON_CARBINERIFLE',
      pmc = 'WEAPON_ASSAULTRIFLE',
      rebels = 'WEAPON_ASSAULTRIFLE',
      defense = 'WEAPON_CARBINERIFLE'
    }
  },
  Resources = {
    fuel = { label = 'Fuel' },
    ammo = { label = 'Ammo' },
    parts = { label = 'Parts' }
  },
  Factions = {
    usa = {
      label = 'US Army',
      identifierColor = '#2d7dff',
      color = { 45, 125, 255 },
      xenonId = 1,
      Style = {
        primary = { r = 45, g = 125, b = 255 },
        secondary = { r = 20, g = 70, b = 160 },
        xenonId = 1
      },
      hq = { x = -2355.0, y = 3245.0, z = 32.8 }
    },
    pmc = {
      label = 'PMC / Mercenaries',
      identifierColor = '#e6aa50',
      color = { 255, 180, 60 },
      xenonId = 6,
      Style = {
        primary = { r = 230, g = 170, b = 80 },
        secondary = { r = 140, g = 100, b = 45 },
        xenonId = 6
      },
      hq = { x = 844.0, y = -2976.0, z = 5.9 }
    },
    rebels = {
      label = 'Rebel Forces',
      identifierColor = '#c83c3c',
      color = { 200, 60, 60 },
      xenonId = 8,
      Style = {
        primary = { r = 200, g = 60, b = 60 },
        secondary = { r = 120, g = 40, b = 40 },
        xenonId = 8
      },
      hq = { x = 1744.0, y = 3290.0, z = 41.1 }
    },
    defense = {
      label = 'Defensive Forces',
      identifierColor = '#78c878',
      color = { 120, 200, 120 },
      xenonId = 3,
      Style = {
        primary = { r = 120, g = 200, b = 120 },
        secondary = { r = 70, g = 120, b = 70 },
        xenonId = 3
      },
      hq = { x = -447.0, y = 6013.0, z = 31.7 }
    }
  },
  Vehicles = {
    m1a1 = {
      label = 'M1A1 Abrams',
      model = 'rhino',
      type = 'tank',
      cost = { fuel = 40, ammo = 20, parts = 15 },
      cooldown = 180
    },
    ifv = {
      label = 'Infantry Fighting Vehicle',
      model = 'apc',
      type = 'ifv',
      cost = { fuel = 30, ammo = 15, parts = 10 },
      cooldown = 150
    },
    apc = {
      label = 'Armored Personnel Carrier',
      model = 'insurgent',
      type = 'apc',
      cost = { fuel = 20, ammo = 10, parts = 8 },
      cooldown = 120
    },
    logistics = {
      label = 'Armored Logistics',
      model = 'barracks',
      type = 'support',
      cost = { fuel = 15, ammo = 5, parts = 5 },
      cooldown = 90
    }
  },
  Depots = {
    usa_main = {
      label = 'US Motor Pool',
      faction = 'usa',
      coords = { x = -2358.0, y = 3232.0, z = 32.8 },
      spawns = {
        { x = -2380.470215, y = 3242.927490, z = 33.00366, h = 60.0 },
        { x = -2346.0, y = 3235.0, z = 32.8, h = 60.0 },
        { x = -2352.0, y = 3242.0, z = 32.8, h = 70.0 }
      },
      vehicles = { 'm1a1', 'ifv', 'apc', 'logistics' },
      cooldown = 30
    },
    pmc_main = {
      label = 'PMC Depot',
      faction = 'pmc',
      coords = { x = 820.0, y = -2982.0, z = 5.9 },
      spawns = {
        { x = 808.0, y = -2990.0, z = 5.9, h = 90.0 },
        { x = 816.0, y = -2986.0, z = 5.9, h = 100.0 },
        { x = 800.0, y = -2988.0, z = 5.9, h = 85.0 }
      },
      vehicles = { 'ifv', 'apc', 'logistics' },
      cooldown = 30
    },
    rebels_main = {
      label = 'Rebel Motor Pool',
      faction = 'rebels',
      coords = { x = 1758.0, y = 3274.0, z = 41.1 },
      spawns = {
        { x = 1768.0, y = 3266.0, z = 41.1, h = 270.0 },
        { x = 1762.0, y = 3270.0, z = 41.1, h = 260.0 },
        { x = 1774.0, y = 3262.0, z = 41.1, h = 275.0 }
      },
      vehicles = { 'apc', 'logistics' },
      cooldown = 30
    },
    defense_main = {
      label = 'Defense Depot',
      faction = 'defense',
      coords = { x = -467.0, y = 6016.0, z = 31.7 },
      spawns = {
        { x = -460.0, y = 6002.0, z = 31.7, h = 180.0 },
        { x = -452.0, y = 6006.0, z = 31.7, h = 170.0 },
        { x = -468.0, y = 5998.0, z = 31.7, h = 190.0 }
      },
      vehicles = { 'm1a1', 'ifv', 'apc' },
      cooldown = 30
    }
  },
  RepairStations = {
    usa_repair = {
      label = 'US Repair Bay',
      faction = 'usa',
      coords = { x = -2368.0, y = 3220.0, z = 32.8 },
      radius = 8.0
    },
    pmc_repair = {
      label = 'PMC Repair Bay',
      faction = 'pmc',
      coords = { x = 830.0, y = -2960.0, z = 5.9 },
      radius = 8.0
    },
    rebels_repair = {
      label = 'Rebel Repair Bay',
      faction = 'rebels',
      coords = { x = 1730.0, y = 3280.0, z = 41.1 },
      radius = 8.0
    },
    defense_repair = {
      label = 'Defense Repair Bay',
      faction = 'defense',
      coords = { x = -440.0, y = 6022.0, z = 31.7 },
      radius = 8.0
    }
  },
  Zones = {
    zancudo = {
      label = 'Fort Zancudo',
      type = 'sphere',
      center = { x = -2370.0, y = 3240.0, z = 32.8 },
      radius = 250.0,
      aiEnabled = true,
      aiStrategic = true,
      aiIntensity = 1.2,
      resourceYield = { fuel = 4, ammo = 3, parts = 2 },
      owner = 'usa'
    },
    docks = {
      label = 'LS Docks',
      type = 'sphere',
      center = { x = 880.0, y = -2970.0, z = 5.9 },
      radius = 220.0,
      aiEnabled = true,
      aiStrategic = true,
      aiIntensity = 1.0,
      resourceYield = { fuel = 3, ammo = 4, parts = 3 },
      owner = 'pmc'
    },
    sandy = {
      label = 'Sandy Airfield',
      type = 'sphere',
      center = { x = 1740.0, y = 3280.0, z = 41.1 },
      radius = 220.0,
      aiEnabled = true,
      aiStrategic = true,
      aiIntensity = 1.0,
      resourceYield = { fuel = 3, ammo = 2, parts = 3 },
      owner = 'rebels'
    },
    paleto = {
      label = 'Paleto Bay',
      type = 'sphere',
      center = { x = -440.0, y = 6020.0, z = 31.7 },
      radius = 220.0,
      aiEnabled = true,
      aiStrategic = true,
      aiIntensity = 1.0,
      resourceYield = { fuel = 2, ammo = 3, parts = 4 },
      owner = 'defense'
    },
    observatory = {
      label = 'Galileo Observatory',
      type = 'sphere',
      center = { x = -450.0, y = 1120.0, z = 325.0 },
      radius = 220.0,
      aiEnabled = true,
      aiStrategic = false,
      aiIntensity = 0.8,
      resourceYield = { fuel = 2, ammo = 2, parts = 2 },
      owner = 'neutral'
    },
    oilfield = {
      label = 'San Chianski Oilfield',
      type = 'sphere',
      center = { x = 1370.0, y = 5170.0, z = 30.0 },
      radius = 240.0,
      aiEnabled = true,
      aiStrategic = false,
      aiIntensity = 0.8,
      resourceYield = { fuel = 5, ammo = 1, parts = 2 },
      owner = 'neutral'
    }
  }
}

local function applyDefaults()
  Config.War.ZoneTick = Utils.safeNumber(Config.War.ZoneTick, 5)
  Config.War.ResourceTick = Utils.safeNumber(Config.War.ResourceTick, 60)
  Config.War.VehicleTick = Utils.safeNumber(Config.War.VehicleTick, 5)
  Config.War.CaptureTime = Utils.safeNumber(Config.War.CaptureTime, 120)
  Config.War.CaptureDecay = Utils.safeNumber(Config.War.CaptureDecay, 30)
  Config.SaveInterval = Utils.safeNumber(Config.SaveInterval, 60)

  for id, zone in pairs(Config.Zones or {}) do
    zone.id = id
    zone.type = zone.type or 'sphere'
    zone.captureTime = zone.captureTime or Config.War.CaptureTime
    zone.resourceYield = zone.resourceYield or { fuel = 0, ammo = 0, parts = 0 }
    zone.owner = zone.owner or 'neutral'
    if zone.aiEnabled == nil then
      zone.aiEnabled = true
    end
    if zone.aiStrategic == nil then
      zone.aiStrategic = Config.AI.DefaultStrategic
    end
    if zone.aiIntensity == nil then
      zone.aiIntensity = Config.AI.DefaultIntensity
    end
  end

  for id, depot in pairs(Config.Depots or {}) do
    depot.id = id
    depot.cooldown = Utils.safeNumber(depot.cooldown, 30)
    if not depot.spawns and depot.spawn then
      depot.spawns = { depot.spawn }
      depot.spawn = nil
    end
  end
end

local function validate()
  local errors = {}
  local function add(msg) errors[#errors + 1] = msg end

  if type(Config.Factions) ~= 'table' or Utils.tableSize(Config.Factions) == 0 then
    add('Config.Factions is missing or empty')
  end
  if type(Config.Zones) ~= 'table' or Utils.tableSize(Config.Zones) == 0 then
    add('Config.Zones is missing or empty')
  end
  if type(Config.Depots) ~= 'table' or Utils.tableSize(Config.Depots) == 0 then
    add('Config.Depots is missing or empty')
  end
  if type(Config.Vehicles) ~= 'table' or Utils.tableSize(Config.Vehicles) == 0 then
    add('Config.Vehicles is missing or empty')
  end

  for id, zone in pairs(Config.Zones or {}) do
    if not zone.center then add(('Zone %s missing center'):format(id)) end
    if zone.type == 'sphere' and not zone.radius then add(('Zone %s missing radius'):format(id)) end
  end

  for id, depot in pairs(Config.Depots or {}) do
    if type(depot.spawns) ~= 'table' or not depot.spawns[1] then
      add(('Depot %s missing spawns array'):format(id))
    end
  end

  return #errors == 0, errors
end

Config.ApplyDefaults = applyDefaults
Config.Validate = validate

applyDefaults()

return Config
