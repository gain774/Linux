fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'dyn_economy'
description 'Supply-and-demand price engine for RedM (framework independent core)'
version '0.1.0'

shared_scripts {
    'shared/pricing_math.lua',
    'shared/census_math.lua',
    'config/config.lua',
    'config/categories.lua',
    'config/items.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/state.lua',
    'server/recipes_core.lua',
    'server/recipes_import.lua',
    'server/recipes.lua',
    'server/census.lua',
    'server/pricing.lua',
    'server/ledger.lua',
    'server/exports.lua',
    'server/commands.lua',
    'server/main.lua',
}

files {
    'sql/schema.sql',
}
