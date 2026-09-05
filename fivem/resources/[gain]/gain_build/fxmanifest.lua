fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gain_build'
author 'gain774'
description 'gain framework building system - blueprint, materials, labour'
version '0.0.1'

shared_scripts {
    '@gain_core/shared/config.lua',
    '@gain_core/shared/locale.lua',
    '@gain_core/shared/locale/ja.lua',
    'shared/config.lua',
}

client_scripts {
    'client/probe.lua',
}

dependencies {
    'gain_core',
}
