fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'dyn_guild'
description 'Player-founded guilds funded by state/weekly NPC tax revenue (§9.3-9.5)'
version '0.1.0'

shared_scripts { 'config.lua' }

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/guild_math.lua',
    'server/db.lua',
    'server/vorp.lua',
    'server/main.lua',
}

files { 'sql/schema.sql' }

dependencies { 'dyn_economy', 'dyn_treasury', 'vorp_core' }
