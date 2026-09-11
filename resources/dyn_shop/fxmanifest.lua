fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'dyn_shop'
description 'NPC shops priced by dyn_economy'
version '0.1.0'

shared_scripts { 'config.lua' }
server_scripts {
    'server/guard.lua',
    'server/main.lua',
}
client_scripts { 'client/main.lua' }

dependencies {
    'dyn_economy',
    'dyn_economy_bridge',
    'vorp_core',
    'vorp_menu',
}
