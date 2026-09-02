fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gain_jobs'
author 'gain774'
description 'gain framework jobs, duty and paycheck'
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
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'gain_core',
    'oxmysql',
}
