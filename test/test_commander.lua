package.path = "..\\src\\lua\\?.lua;" .. package.path

-- pcall(require, "luacov")

local ut        = require "lluv.utils"
local at        = require "lluv.gsmmodem.at"
local utils     = require "utils"
local TEST_CASE = require "lunit".TEST_CASE

local split_args  = require "lluv.gsmmodem.utils".split_args
local split_list  = require "lluv.gsmmodem.utils".split_list
local decode_list = require "lluv.gsmmodem.utils".decode_list

local pcall, error, type, table, ipairs, print, tonumber = pcall, error, type, table, ipairs, print, tonumber
local RUN = utils.RUN
local IT, CMD, PASS = utils.IT, utils.CMD, utils.PASS
local nreturn, is_equal = utils.nreturn, utils.is_equal
local EOL = '\r\n'
local OK = EOL..'OK'..EOL
local ERROR = EOL..'ERROR'..EOL

local trim = function(data)
  return data:match('^%s*(.-)%s*$')
end

local unquot = function(data)
  return (trim(data):match('^"?(.-)"?$'))
end

local ENABLE = true

local _ENV = TEST_CASE'command encoder/decoder' if ENABLE then

local it = IT(_ENV or _M)

local stream, command, call_count
local SELF = {}

local function called(n)
  call_count = call_count + (n or 1)
  return call_count
end

function setup()
  stream  = assert(at.Stream(SELF))
  command = assert(at.Commander(stream))
  call_count = 0
end

it("pass command", function()
  stream:on_command(function(self, cmd)
    assert_equal(1, called())
    assert_equal(stream, self)
    assert_equal('ATZ\r\n', cmd)
  end)

  assert_true(command:ATZ(function(self, err, res)
    assert_equal(2, called())
    assert_equal(SELF, self)
    assert_nil(err)
    assert_equal('OK', res)
  end))

  assert_equal(stream, stream:append(OK))
  assert_equal(stream, stream:execute())

  assert_equal(3, called())
end)

it("error command", function()
  stream:on_command(function(self, cmd)
    assert_equal(1, called())
    assert_equal(stream, self)
    assert_equal('ATZ\r\n', cmd)
  end)

  assert_true(command:ATZ(function(self, err, res)
    assert_equal(2, called())
    assert_equal(SELF, self)
    assert(err)
    assert_equal('GSM-AT', err:cat())
    assert_equal('ERROR',  err:name())
    assert_number(err:no())
  end))

  assert_equal(stream, stream:append(ERROR))
  assert_equal(stream, stream:execute())

  assert_equal(3, called())
end)

do -- CMGR PASS tests

local CMGR = {
  {
    'AT+CMGR=1',
    '+CMGR: 3,,29',
    '0791361907001003B17A0C913619397750320000AD11CD701E340FB3C3F23CC81D0689C3BF',
    {3, '', 29},
  };
  {
    'AT+CMGR=1',
    '+CMGR: 1,,25',
    '0791198948004544040C9119894882006200007050307040042206CF35689E9603',
    {1, '', 25},
  };
  {
    'AT+CMGR=0',
    '+CMGR: 0,23',
    '0791534850020200040C9153486507895500006090608164138004D4F29C0E',
    {0, nil, 23},
  };
  {
    'AT+CMGR=4',
    '+CMGR: 4,1,,151',
    '0791539111161616640C9153916161755000F54020310164450084831281000615FFFFE7F6E003E193CC0B0000E793D1460000E193D2A00000E793D1400000E1C7D0900000FFFFD2A00000F88FD1400000F047E8806003F007F700D3E6F82C79D06413FC5C7EE809C8FE3FFF7012E4FFFFFFA823E2E0867FB021C2F99E7FA8208289867FB42082899FFF9A2492F9867FDD13E4FFFFFFEE8808FFFFFFED4808',
    {1, '', 151},
  };
  {
    'AT+CMGR=1',
    '+CMGR: 3,,29',
    '079124602009999002AB098106845688F8907080517375809070805183018000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
    {3, '', 29},
  };
  {
    'AT+CMGR=1',
    '+CMGR: 24',
    '079124602009999006B4098106326906F2212041015554402120410155054000',
    {nil, nil, 24},
  };
  {
    'AT+CMGR=3864',
    '+CMGR: "REC READ", "+4123456789132", "2009/8/18,19:11:45"',
    'Hoewfliepl jookfotu oediutocou noabd fjumuywuncuzx lqutyehw. Joifdykojgdh pyigypaslp jomxuauxosiau arhi ludiqigitoda rivwitumaxy jyokigebxeqir zxeuluhp isluqlinushceg Styonwy jy uhu ibwypejkenobuo zitkizaruamim jbis dytiuiryuzil jeisviz zuoyrs. Leay agjyicify dojip-yfucqoguwx soxujdeh qyg R ginyea jpae ryk huywxeqyraeo enyvkymyscepae jeweimqizp afu fiysy noytaj.',
    {'REC READ', '+4123456789132', '2009/8/18,19:11:45'},
  };
  {
    'AT+CMGR=3787',
    '+CMGR: "REC READ", "+6667776667744", "2009/8/18,19:11:45"',
    'Hoewfliepl jookfotu oediutocou noabd fjumuywuncuzx lqutyehw. Joifdykojgdh pyigypaslp jomxuauxosiau arhi ludiqigitoda rivwitumaxy jyokigebxeqir.'
    .. '\n' .. 'Zxeuluhp isluqlinushceg Styonwy jy uhu ibwypejkenobuo zitkizaruamim jbis dytiuiryuzil jeisviz zuoyrs. Leay agjyicify dojip-yfucqoguwx soxujdeh qyg R.'
    .. '\n' .. '.ginyea jpae ryk huywxeqyraeo enyvkymyscepae jeweimqizp afu fiysy.'
    .. '\n' .. 'Noytaj.',
    {'REC READ', '+6667776667744', '2009/8/18,19:11:45'},
  };
  {
    'AT+CMGR=3',
    '+CMGR: "REC READ","+31625044454",,"07/07/05,09:56:03+08"',
    'Test message 2',
    {'REC READ', '+31625044454', '07/07/05,09:56:03+08'},
  };
  {
    'AT+CMGR=1',
    '+CMGR: "REC READ","3473065111",,"06/05/28,18:15:41+80",129,17,0,18,"+393492001157",145,6 ',
    'hello.',
    {'REC READ', '3473065111', '06/05/28,18:15:41+80'},
  };
  {
    'AT+CMGR=303',
    '+CMGR:"REC READ","+393488535999",,"07/04/05,18:02:28+08",145,4,0,0,"+393492000466",145,93',
    'You have a missed called. Freeinformation provided by your operator.',
    {'REC READ', '+393488535999', '07/04/05,18:02:28+08'},
  };
  {
    'AT+CMGR=1',
    '+CMGR: "STO UNSENT","+10011",,145,17,0,0,167,"+8613800100500",145,4 ',
    'Hello World',
    {'STO UNSENT', '+10011', nil},
  };
}

for i, T in ipairs(CMGR) do
  local _, index = ut.split_first(T[1], '=', true)
  index = tonumber(index)
  local request  = T[1] .. EOL
  local response = T[2] .. EOL .. T[3] .. EOL .. OK

it(("CMGR#%.3d command no echo"):format(i), function()
  stream:on_command(function(self, cmd)
    assert_equal(1, called())
    assert_equal(request, cmd)
  end)

  assert_true(command:CMGR(index, function(self, err, pdu, stat, alpha, len)
    assert_equal(2, called())
    assert_nil(err)
    assert_equal(T[3],     pdu   )
    assert_equal(T[4][1],  stat  )
    assert_equal(T[4][2],  alpha )
    assert_equal(T[4][3],  len   )
  end))

  assert_equal(stream, stream:append(response))
  assert_equal(stream, stream:execute())

  assert_equal(3, called())
end)

it(("CMGR#%.3d command echo"):format(i), function()
  stream:on_command(function(self, cmd)
    assert_equal(1, called())
    assert_equal(request, cmd)
  end)

  assert_true(command:CMGR(index, function(self, err, pdu, stat, alpha, len)
    assert_equal(2, called())
    assert_nil(err)
    assert_equal(T[3],     pdu   )
    assert_equal(T[4][1],  stat  )
    assert_equal(T[4][2],  alpha )
    assert_equal(T[4][3],  len   )
  end))

  assert_equal(stream, stream:append(request))
  assert_equal(stream, stream:append(response))
  assert_equal(stream, stream:execute())

  assert_equal(3, called())
end)

end

end

do -- CMGS PASS tests

local CMGS = {
  {
    'AT+CMGS=42',
    '0791361907001003B17A0C913619397750320000AD11CD701E340FB3C3F23CC81D0689C3BF',
    '+CMGS: 5',
    {5, nil},
  };
  {
    'AT+CMGS="+85291234567"',
    'This is an example for illustrating the syntax of the +CMGS AT command in SMS text mode.',
    '+CMGS: 5,"07/02/05,08:30:45+32"',
    {5, '07/02/05,08:30:45+32'},
  };
}

for i, T in ipairs(CMGS) do
  local _, len = ut.split_first(T[1], '=', true)
  len = tonumber(len) or unquot(len)

  local request  = T[1] .. EOL
  local sms_body = T[2] .. '\26'
  local response = T[3] .. EOL .. OK

it(("CMGS#%.3d command"):format(i), function()
  stream:on_command(function(self, cmd)
    if 0 == called(0) then
      called()
      assert_equal(request, cmd)
    else
      assert_equal(2, called())
      assert_equal(sms_body, cmd)
    end
  end)

  assert_true(command:CMGS(len, T[2], function(self, err, ref, data)
    assert_equal(3, called())
    assert_nil(err)
    assert_equal(T[4][1],  ref  )
    assert_equal(T[4][2],  data )
  end))

  assert_equal(1, called(0))

  assert_equal(stream, stream:append(request))
  assert_equal(stream, stream:append(EOL .. '> '))
  assert_equal(stream, stream:execute())

  assert_equal(2, called(0))

  assert_equal(stream, stream:append(response))
  assert_equal(stream, stream:execute())
end)

end

end

end

local _ENV = TEST_CASE'split args/list' if ENABLE then

local it = IT(_ENV or _M)

it('split_args',function()
  local t = assert_table(split_args('1, "hello", 2,," aaa ",'))
  assert_equal('1'    , t[1])
  assert_equal('hello', t[2])
  assert_equal(' 2'   , t[3])
  assert_equal(''     , t[4])
  assert_equal(' aaa ', t[5])
  assert_equal(''     , t[6])
  assert_nil  (t[7])
end)

it('decode_list',function()
  local lst = '("SM","BM","SR"),("SM"),(SM),(0-1,2,3),(0,1-3),(0-3),(0,1),(0,1),(3),4'
  local t = assert_table(decode_list(lst))
  do local t = assert_table(t[1])
    assert_equal('SM', t[1])
    assert_equal('BM', t[2])
    assert_equal('SR', t[3])
    assert_nil  (      t[4])
  end

  assert_equal('SM', t[2])

  assert_equal('SM', t[3])

  do local t = assert_table(t[4])
    assert_equal(0, t[1])
    assert_equal(1, t[2])
    assert_equal(2, t[3])
    assert_equal(3, t[4])
    assert_nil  (   t[5])
  end

  do local t = assert_table(t[5])
    assert_equal(0, t[1])
    assert_equal(1, t[2])
    assert_equal(2, t[3])
    assert_equal(3, t[4])
    assert_nil  (   t[5])
  end

  do local t = assert_table(t[6])
    assert_equal(0, t[1])
    assert_equal(1, t[2])
    assert_equal(2, t[3])
    assert_equal(3, t[4])
    assert_nil  (   t[5])
  end

  do local t = assert_table(t[7])
    assert_equal(0, t[1])
    assert_equal(1, t[2])
    assert_nil  (   t[3])
  end

  do local t = assert_table(t[8])
    assert_equal(0, t[1])
    assert_equal(1, t[2])
    assert_nil  (   t[3])
  end

  assert_equal(3, t[9])
  assert_equal(4, t[10])
end)

end

RUN()
