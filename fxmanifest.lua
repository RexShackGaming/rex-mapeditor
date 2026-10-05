fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

name 'rex-mapeditor'
author 'RexShack'
description 'In-game prop placement tool with ymap (CMapData) export for RSG Framework'
version '3.0.1'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua',
    'server/ymap.lua',
    'server/versionchecker.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/props.json',
    'locales/*.json'
}

dependencies {
    'ox_lib'
}

escrow_ignore {
    'shared/config.lua',
    'locales/*',
    'data/*',
    'README.md'
}
