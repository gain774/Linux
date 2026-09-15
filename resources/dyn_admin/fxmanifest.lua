fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'dyn_admin'
description 'Admin NUI dashboard: prices/stock, state-week treasury, guild approvals, fixed-price toggle'
version '0.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
}

client_scripts { 'client/main.lua' }

server_scripts {
    'server/dashboard.lua',
    'server/main.lua',
}

-- dyn_economy が無いと表示するものが無いので必須依存にする。
-- dyn_treasury / dyn_guild は無くてもその欄が空になるだけで動く（任意）
dependencies { 'dyn_economy' }
