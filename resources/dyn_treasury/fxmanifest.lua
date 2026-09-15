fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'dyn_treasury'
description 'Records the NPC spread as tax in a treasury instead of destroying it'
version '0.1.0'

shared_scripts { 'config.lua' }

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/ledger_math.lua',
    'server/db.lua',
    'server/main.lua',
}

files { 'sql/schema.sql' }

dependencies { 'dyn_economy' }
