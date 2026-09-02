fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gain_anticheat'
author 'gain774'
description 'gain framework server-side cheat detection'
version '0.1.0'

shared_scripts {
    '@gain_core/shared/config.lua',
    '@gain_core/shared/locale.lua',
    '@gain_core/shared/locale/ja.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@gain_core/server/safe_event.lua',
    'server/strikes.lua',
    'server/checks.lua',
    'server/events.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies {
    'gain_core',
    'oxmysql',
}
