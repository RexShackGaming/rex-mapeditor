fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

lua54 'yes'

name 'rex-mapeditor'
author 'RexShack'
description 'In-game prop placement tool with ymap (CMapData) export for RSG Framework'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@rsg-core/shared/locale.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

dependencies {
    'ox_lib'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/ymap.lua',
    'server/versionchecker.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/spooni_props.json',
    'data/*.json'
}

escrow_ignore {
    'data/*',
    'config.lua',
    'README.md'
}

