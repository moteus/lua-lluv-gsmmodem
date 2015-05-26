package = "lluv-gsmmodem"
version = "scm-0"

source = {
  url = "https://github.com/moteus/lua-lluv-gsmmodem/archive/master.zip",
  dir = "lua-lluv-gsmmodem-master",
}

description = {
  summary    = "Lua module to control GSM modem",
  homepage   = "https://github.com/moteus/lua-lluv-gsmmodem",
  license    = "MIT/X11",
  maintainer = "Alexey Melnichuk",
  detailed   = [[
  ]],
}

dependencies = {
  "lua >= 5.1, < 5.4",
  "lluv",
  "lluv-rs232",
  "tpdu",
  "date",
  "lpeg",
  "lua-iconv",
}

build = {
  copy_directories = {'test', 'examples'},

  type = "builtin",

  modules = {
    [ 'lluv.gsmmodem'       ] = 'src/lua/lluv/gsmmodem.lua',
    [ 'lluv.gsmmodem.at'    ] = 'src/lua/lluv/gsmmodem/at.lua',
    [ 'lluv.gsmmodem.error' ] = 'src/lua/lluv/gsmmodem/error.lua',
    [ 'lluv.gsmmodem.utils' ] = 'src/lua/lluv/gsmmodem/utils.lua',
  }
}

