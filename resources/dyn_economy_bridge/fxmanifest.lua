fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'dyn_economy_bridge'
description 'VORP adapter and guarded NPC trade flow for dyn_economy'
version '0.1.0'

shared_scripts {
    'config.lua',
}

server_scripts {
    'server/txflow.lua',
    'server/vorp.lua',
    'server/compat.lua',
    'server/bridge.lua',
}

dependencies {
    'dyn_economy',
    'vorp_core',
    'vorp_inventory',
}
