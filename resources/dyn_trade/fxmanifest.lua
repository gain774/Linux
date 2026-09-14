fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'dyn_trade'
description 'Player-to-player trading: use an item near someone to negotiate a free-form trade (dyn_economy prices shown as reference, small fee on cash)'
version '0.1.0'

shared_scripts { 'config.lua' }

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/vorp.lua',
    'server/trade_math.lua',
    'server/trade_flow.lua',
    'server/main.lua',
}

client_scripts { 'client/main.lua' }

files { 'sql/schema.sql' }

dependencies {
    'vorp_core',
    'vorp_inventory',
    'vorp_menu',
}
