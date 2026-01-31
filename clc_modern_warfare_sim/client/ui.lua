local Constants = MW.require('shared/constants.lua')

local UI = {}
local isOpen = false
local currentPanel = nil
local handlers = {}
local lastSent = 0
local pendingPayload = nil
local flushScheduled = false
local throttleMs = 150

function UI.Open(panel)
  if isOpen then
    currentPanel = panel or currentPanel or 'hud'
    print(('[MW:UI] Switch panel=%s'):format(currentPanel))
    SendNUIMessage({ action = 'open', panel = currentPanel })
    return
  end
  isOpen = true
  currentPanel = panel or 'hud'
  SetNuiFocus(true, true)
  print(('[MW:UI] Open panel=%s'):format(currentPanel))
  SendNUIMessage({ action = 'open', panel = currentPanel })
end

function UI.Close()
  if not isOpen then return end
  isOpen = false
  currentPanel = nil
  SetNuiFocus(false, false)
  print('[MW:UI] Close')
  SendNUIMessage({ action = 'close' })
end

function UI.Toggle(panel)
  if isOpen then
    UI.Close()
  else
    UI.Open(panel)
  end
end

function UI.IsOpen()
  return isOpen
end

function UI.GetPanel()
  return currentPanel
end

function UI.Update(payload)
  local now = GetGameTimer()
  local delta = now - lastSent
  if delta >= throttleMs then
    lastSent = now
    SendNUIMessage({ action = 'update', payload = payload })
    return
  end

  pendingPayload = payload
  if flushScheduled then return end
  flushScheduled = true

  CreateThread(function()
    local waitMs = throttleMs - delta
    if waitMs > 0 then
      Wait(waitMs)
    end
    if pendingPayload then
      lastSent = GetGameTimer()
      SendNUIMessage({ action = 'update', payload = pendingPayload })
      pendingPayload = nil
    end
    flushScheduled = false
  end)
end

function UI.Toast(tone, message)
  SendNUIMessage({ action = 'toast', tone = tone or 'info', message = message or '' })
end

function UI.Init(callbacks)
  handlers = callbacks or {}

  RegisterNUICallback(Constants.UI.Close, function(_, cb)
    print('[MW:UI] NUI close callback')
    if handlers.onClose then handlers.onClose() end
    cb('ok')
  end)

  RegisterNUICallback(Constants.UI.SelectFaction, function(data, cb)
    print(('[MW:UI] NUI select faction: %s'):format(data and data.faction or 'nil'))
    if handlers.onSelectFaction then handlers.onSelectFaction(data) end
    cb('ok')
  end)

  RegisterNUICallback(Constants.UI.SpawnVehicle, function(data, cb)
    print(('[MW:UI] NUI spawn request: depot=%s vehicle=%s requestId=%s'):format(data and data.depotId or 'nil', data and data.vehicleId or 'nil', data and data.requestId or 'nil'))
    if handlers.onSpawnVehicle then handlers.onSpawnVehicle(data) end
    cb('ok')
  end)

  RegisterNUICallback(Constants.UI.RequestRepair, function(data, cb)
    print(('[MW:UI] NUI repair request: netId=%s'):format(data and data.netId or 'nil'))
    if handlers.onRequestRepair then handlers.onRequestRepair(data) end
    cb('ok')
  end)
end

return UI
