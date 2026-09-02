fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gain_core'
author 'gain774'
description 'gain framework core - player, money, permission, locale, compat'
version '0.1.0'

shared_scripts {
    'shared/config.lua',
    'shared/locale.lua',
    'shared/locale/ja.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/log.lua',
    'server/safe_event.lua',
    'server/permission.lua',
    'server/money.lua',
    'server/player.lua',
    'server/api.lua',
    'server/compat.lua',
}

client_scripts {
    'client/main.lua',
    'client/compat.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependency 'oxmysql'
