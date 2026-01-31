fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'clc_modern_warfare_sim'
author 'clc'
description 'Modern warfare simulation with factions, zones, vehicles, logistics, and NUI.'
version '1.0.0'

shared_scripts {
  'shared/loader.lua'
}

client_scripts {
  'client/main.lua'
}

server_scripts {
  'server/main.lua'
}

ui_page 'html/index.html'

files {
  'shared/*.lua',
  'client/*.lua',
  'server/*.lua',
  'html/index.html',
  'html/style.css',
  'html/app.js'
}
