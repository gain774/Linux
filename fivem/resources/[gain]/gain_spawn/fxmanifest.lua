fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gain_spawn'
author 'gain774'
description 'gain framework spawn control - first spawn, position restore, death respawn'
version '0.1.0'

shared_scripts {
    '@gain_core/shared/config.lua',
    '@gain_core/shared/locale.lua',
    '@gain_core/shared/locale/ja.lua',
    'shared/config.lua',
}

server_scripts {
    '@gain_core/server/safe_event.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies {
    'gain_core',
}
