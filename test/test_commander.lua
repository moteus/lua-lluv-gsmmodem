package.path = "..\\src\\lua\\?.lua;" .. package.path

pcall(require, "luacov")

local ut        = require "lluv.utils"
local at        = require "lluv.gsmmodem.at"
local utils     = require "utils"
local TEST_CASE = require "lunit".TEST_CASE

local split_args  = require "lluv.gsmmodem.utils".split_args
local split_list  = require "lluv.gsmmodem.utils".split_list
local decode_list = require "lluv.gsmmodem.utils".decode_list

local pcall, error, type, table, ipairs, print, tonumber = pcall, error, type, table, ipairs, print, tonumber
local tostring, string = tostring, string
local RUN = utils.RUN
local IT, CMD, PASS = utils.IT, utils.CMD, utils.PASS
local nreturn, is_equal = utils.nreturn, utils.is_equal
local EOL   = '\r\n'
local OK    = EOL ..  'OK'   ..EOL
local ERROR = EOL .. 'ERROR' ..EOL

local trim = function(data)
  return data:match('^%s*(.-)%s*$')
end

local unquot = function(data)
  return (trim(data):match('^"?(.-)"?$'))
end

local function Counter()
  return setmetatable({{}}, {__call=function(self, name)
    local fn = self[1][name]
    if not fn then
      self[name] = self[name] or 0
      fn = function(inc)
        self[name] = self[name] + 1
        return self[name]
      end
      self[1][name] = fn
    end
    return fn
  end; __index = function() return 0 end})
end

local ENABLE = true

local SELF, call_count = {}

local function called(n)
  call_count = call_count + (n or 1)
  return call_count
end

local _ENV = TEST_CASE'command encoder/decoder' if ENABLE then

local it = IT(_ENV or _M)

local stream, command

function setup()
  stream  = assert(at.Stream(SELF))
  command = assert(at.Commander(stream))
  call_count = 0
end

it("pass command", function()
  stream:on_command(function(self, cmd)
    assert_equal(1, called())
    assert_equal(SELF, self)
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

it("echo command", function()
  stream:on_command(function(self, cmd)
    assert_equal(1, called())
    assert_equal(SELF, self)
    assert_equal('AT+COPS?\r\n', cmd)
  end)

  assert_true(command:OperatorName(function(self, err, res)
    assert_equal(2, called())
    assert_equal(SELF, self)
    assert_nil(err)
    assert_equal('MTS', res)
  end))

  assert_equal(stream, stream
    :append('\r\n+CMTI: 1\r\n')
    :append('AT+COPS?\r\r\n+COPS: 0,0,"MTS"\r\n\r\nOK\r\n')
  )
  assert_equal(stream, stream:execute())

  assert_equal(3, called())
end)

it("no echo command", function()
  stream:on_command(function(self, cmd)
    assert_equal(1, called())
    assert_equal(SELF, self)
    assert_equal('AT+COPS?\r\n', cmd)
  end)

  assert_true(command:OperatorName(function(self, err, res)
    assert_equal(2, called())
    assert_equal(SELF, self)
    assert_nil(err)
    assert_equal('MTS', res)
  end))

  assert_equal(stream, stream
    :append('\r\n+CMTI: 1\r\n')
    :append('\r\n+COPS: 0,0,"MTS"\r\n\r\nOK\r\n')
  )
  assert_equal(stream, stream:execute())

  assert_equal(3, called())
end)

it("error command", function()
  stream:on_command(function(self, cmd)
    assert_equal(1, called())
    assert_equal(SELF, self)
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
    {3, 29, ''},
  };
  {
    'AT+CMGR=1',
    '+CMGR: 1,,25',
    '0791198948004544040C9119894882006200007050307040042206CF35689E9603',
    {1, 25, ''},
  };
  {
    'AT+CMGR=0',
    '+CMGR: 0,23',
    '0791534850020200040C9153486507895500006090608164138004D4F29C0E',
    {0, 23},
  };
  {
    'AT+CMGR=4',
    '+CMGR: 4,1,,151',
    '0791539111161616640C9153916161755000F54020310164450084831281000615FFFFE7F6E003E193CC0B0000E793D1460000E193D2A00000E793D1400000E1C7D0900000FFFFD2A00000F88FD1400000F047E8806003F007F700D3E6F82C79D06413FC5C7EE809C8FE3FFF7012E4FFFFFFA823E2E0867FB021C2F99E7FA8208289867FB42082899FFF9A2492F9867FDD13E4FFFFFFEE8808FFFFFFED4808',
    {1, 151, ''},
  };
  {
    'AT+CMGR=1',
    '+CMGR: 3,,29',
    '079124602009999002AB098106845688F8907080517375809070805183018000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
    {3, 29, ''},
  };
  {
    'AT+CMGR=1',
    '+CMGR: 24',
    '079124602009999006B4098106326906F2212041015554402120410155054000',
    {nil, 24},
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

  assert_true(command:CMGR(index, function(self, err, pdu, len, stat, alpha)
    assert_equal(2, called())
    assert_nil(err)
    assert_equal(T[3],     pdu   )
    assert_equal(T[4][1],  len   )
    assert_equal(T[4][2],  stat  )
    assert_equal(T[4][3],  alpha )
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

  local on_command = function(self, cmd)
    if 0 == called(0) then
      called()
      assert_equal(request, cmd)
    else
      assert_equal(2, called())
      assert_equal(sms_body, cmd)
    end
  end

  local on_cmgs = function(self, err, ref, data)
    assert_equal(3, called())
    assert_nil(err)
    assert_equal(T[4][1],  ref  )
    assert_equal(T[4][2],  data )
  end

it(("CMGS#%.3d command"):format(i), function()
  stream:on_command(on_command)

  assert_true(command:CMGS(len, T[2], on_cmgs))

  assert_equal(1, called(0))

  assert_equal(stream, stream:append(request))
  assert_equal(stream, stream:append(EOL .. '> '))
  assert_equal(stream, stream:execute())

  assert_equal(2, called(0))

  assert_equal(stream, stream:append(response))
  assert_equal(stream, stream:execute())
end)

it(("CMGS#%.3d command no echo"):format(i), function()
  stream:on_command(on_command)

  assert_true(command:CMGS(len, T[2], on_cmgs))

  assert_equal(1, called(0))

  assert_equal(stream, stream:append(EOL .. '> '))
  assert_equal(stream, stream:execute())

  assert_equal(2, called(0))

  assert_equal(stream, stream:append(response))
  assert_equal(stream, stream:execute())
end)

end

end

do -- MemoryStatus

local COMMAND = {
  {
    'AT+CPMS?',
    '+CPMS: "SM",8,20,"SM",8,20,"SM",8,20',
    {
      {"SM", 8, 20},
      {"SM", 8, 20},
      {"SM", 8, 20},
    },
  };
  {
    'AT+CPMS?',
    '+CPMS: ,,,,,,,,',
    {},
  };
  {
    'AT+CPMS?',
    '+CPMS: ME,0,,"SM",,255,SR,,',
    {
      {"ME", 0,   nil},
      {"SM", nil, 255},
      {"SR", nil, nil},
    },
  };
  {
    'AT+CPMS?',
    '+CPMS: ME,0,15,"SM",1,20,SR,2,22',
    {
      {"ME", 0, 15},
      {"SM", 1, 20},
      {"SR", 2, 22},
    },
  };
}

for i, T in ipairs(COMMAND) do
  local request  = T[1] .. EOL
  local response = T[2] .. EOL .. OK
  local MEM1, MEM2, MEM3 = T[3][1], T[3][2], T[3][3]

it(("MemoryStatus#%.3d command"):format(i), function()
  stream:on_command(function(self, cmd)
    assert_equal(1, called())
    assert_equal(request, cmd)
  end)

  assert_true(command:MemoryStatus(function(self, err, mem1, mem2, mem3)
    assert_equal(2, called())
    assert_nil(err)

    if not MEM1 then assert_nil(mem1) else
      assert_equal(MEM1[1], mem1[1])
      assert_equal(MEM1[2], mem1[2])
      assert_equal(MEM1[3], mem1[3])
    end

    if not MEM2 then assert_nil(mem2) else
      assert_equal(MEM2[1], mem2[1])
      assert_equal(MEM2[2], mem2[2])
      assert_equal(MEM2[3], mem2[3])
    end

    if not MEM3 then assert_nil(mem3) else
      assert_equal(MEM3[1], mem3[1])
      assert_equal(MEM3[2], mem3[2])
      assert_equal(MEM3[3], mem3[3])
    end
  end))

  assert_equal(1, called(0))

  assert_equal(stream, stream:append(response))
  assert_equal(stream, stream:execute())

  assert_equal(2, called(0))
end)

end

end

it('CMGL should read truncated pdus',function()
  stream:on_command(function(self, cmd)
    assert_equal(1, called())
    assert_equal('AT+CMGL=4\r\n', cmd)
  end)

  assert_true(command:CMGL(4, function(self, err, messages)
    assert_equal(2, called())
    assert_nil(err)
    assert_table(messages)
    assert_equal(3, #messages)

    local msg = messages[1] do
      local index, pdu, stat, len = msg[1], msg[2], msg[3], msg[4]
      assert_equal(1,  index)
      assert_equal(1,  stat)
      assert_equal(26, len)
      assert_equal('07919761989901F0240B917777777777F70000514042314545210720A83C6D2FD301', pdu)
    end

    local msg = messages[2] do
      local index, pdu, stat, len = msg[1], msg[2], msg[3], msg[4]
      assert_equal(3,  index)
      assert_equal(1,  stat)
      assert_equal(26, len)
      assert_equal('07919761989901F0240B917777777777F70000514042314545210720A8', pdu)
    end

    local msg = messages[3] do
      local index, pdu, stat, len = msg[1], msg[2], msg[3], msg[4]
      assert_equal(6,  index)
      assert_equal(1,  stat)
      assert_equal(26, len)
      assert_equal('07919761989901F0240B917777777777F70000514042314545210720A83C6D2FD301', pdu)
    end

  end))

  stream
    :append'+CMGL: 1,1,,26'
    :append(EOL)
    :append'07919761989901F0240B917777777777F70000514042314545210720A83C6D2FD301'
    :append(EOL)
    :append'+CMGL: 3,1,,26'
    :append(EOL)
    :append'07919761989901F0240B917777777777F70000514042314545210720A8'
     -- NO EOL
    :append'+CMGL: 6,1,,26'
    :append(EOL)
    :append'07919761989901F0240B917777777777F70000514042314545210720A83C6D2FD301'
    :append(OK)
  :execute()

  assert_equal(2, called(0))
end)

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

it('decode_list flat',function()
  local lst = '("SM","BM","SR"),("SM"),(SM),(0-1,2,3),(0,1-3),(0-3),(0,1),(0,1),(3),4'
  local t = assert_table(decode_list(lst, true))
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

it('decode_list range',function()
  local lst = '("SM","BM","SR"),(0-256),(0,1-3),(0,1),(3),4'
  local t = assert_table(decode_list(lst, false))
  do local t = assert_table(t[1])
    assert_equal('SM', t[1])
    assert_equal('BM', t[2])
    assert_equal('SR', t[3])
    assert_nil  (      t[4])
  end

  do local t = assert_table(t[2])
    assert_table(t[1])
    assert_equal(0,   t[1][1])
    assert_equal(256, t[1][2])
  end

  do local t = assert_table(t[3])
    assert_equal(0, t[1])
    assert_table(t[2])
    assert_equal(1, t[2][1])
    assert_equal(3, t[2][2])
  end

  do local t = assert_table(t[4])
    assert_equal(0, t[1])
    assert_equal(1, t[2])
    assert_nil  (   t[3])
  end

  assert_equal(3, t[5])
  assert_equal(4, t[6])
end)

end

local _ENV = TEST_CASE'URC decoder' if ENABLE then

local it = IT(_ENV or _M)

it('Guess CMT text mode', function()
  local typ, mode, text, number = at.DecodeUrc(nil, '+CMT', '"+77777777777",,"15/05/22,11:00:58+12"', '1234567890')
  assert_equal('+CMT', typ)
  assert_true(mode)
  assert_equal('1234567890',   text)
  assert_equal('+77777777777', number)
end)

it('Guess CMT pdu mode', function()
  local typ, mode, pdu, len = at.DecodeUrc(nil, '+CMT', ',28', '07919761989901F0040B919791699674F20000515022114032210A31D98C56B3DD703918')
  assert_equal('+CMT', typ)
  assert_false(mode)
  assert_equal(28, len)
  assert_equal('07919761989901F0040B919791699674F20000515022114032210A31D98C56B3DD703918', pdu)
end)

end

local _ENV = TEST_CASE'chain/front commands' if ENABLE then

local it = IT(_ENV or _M)

local stream, command

function setup()
  stream  = assert(at.Stream())
  command = assert(at.Commander(stream))
  call_count = 0
end

it("no front command", function()
  local no = 0

  stream:on_command(function(self, cmd)
    assert_equal('AT#' .. tostring(called()) .. '\r\n', cmd)
  end)

  command:mode():at("#1")
  command:mode():at("#2")
  command:mode():at("#3")

  assert_equal(stream, stream:append(OK:rep(3)))
  assert_equal(stream, stream:execute())

  assert_equal(3, called(0))
end)

it("front command", function()
  local no = 0

  stream:on_command(function(self, cmd)
    assert_equal('AT#' .. tostring(called()) .. '\r\n', cmd)
  end)

  command:mode(true):at("#1")
  command:mode(true):at("#3")
  command:mode(true):at("#2")

  assert_equal(stream, stream:append(OK:rep(3)))
  assert_equal(stream, stream:execute())

  assert_equal(3, called(0))
end)

it("no chain command", function()
  local no = 0

  stream:on_command(function(self, cmd)
    assert_equal('AT#' .. tostring(called()) .. '\r\n', cmd)
  end)

  command:mode():at("#1", function(self, err, status)
    command:mode(true):at("#3")
  end)
  command:mode():at("#2")

  assert_equal(stream, stream:append(OK:rep(3)))
  assert_equal(stream, stream:execute())

  assert_equal(3, called(0))
end)

it("chain command", function()
  local no = 0

  stream:on_command(function(self, cmd)
    assert_equal('AT#' .. tostring(called()) .. '\r\n', cmd)
  end)

  command:mode(false, true):at("#1", function(self, err, status)
    command:mode(true):at("#2")
  end)
  command:mode():at("#3")

  assert_equal(stream, stream:append(OK:rep(3)))
  assert_equal(stream, stream:execute())

  assert_equal(3, called(0))
end)

end

local _ENV = TEST_CASE'chain commands' if ENABLE then

local it = IT(_ENV or _M)

local stream, command

function setup()
  stream  = assert(at.Stream(SELF))
  command = assert(at.Commander(stream))
  call_count = 0
end

it('should run chain in proper order', function()
  local cb_called_ = 0
  local function cb_called(n)
    cb_called_ = cb_called_ + (n or 1)
    return cb_called_
  end

  stream:on_command(function(self, cmd)
    assert_equal(SELF, self)
    local e = string.format('AT#%d\r\n', called())
    assert_equal(e, cmd)
  end)

  command:at('#1', function(self, err, res)
    assert_equal(1, cb_called())
  end)

  command:at('#2', function(self, err, res)
    assert_equal(2, cb_called())
  end)

  command:chain{
    function(command, cont)
      command:at('#3', function(self, err, res)
        assert_equal(3, cb_called())
        cont()
      end)
    end;

    function(command, cont)
      command:at('#4', function(self, err, res)
        assert_equal(4, cb_called())
        cont()
      end)
    end;
  }

  command:mode():at('#5', function(self, err, res)
    assert_equal(5, cb_called())
  end)

  stream
    :append(OK):execute()
    :append(OK):execute()
    :append(OK):execute()
    :append(OK):execute()
    :append(OK):execute()

  assert_equal(5, called(0))
  assert_equal(5, cb_called(0))
end)

end

local _ENV = TEST_CASE'prompt eol' if ENABLE then

local it = IT(_ENV or _M)

local stream, command, counter

function setup()
  stream   = assert(at.Stream(SELF))
  command  = assert(at.Commander(stream))
  counters = Counter()
end

local len      = 42
local request  = 'AT+CMGS=' .. tostring(len)
local sms_body = '0791361907001003B17A0C913619397750320000AD11CD701E340FB3C3F23CC81D0689C3BF'
local sms_ref  = 5
local response = '+CMGS: ' .. tostring(sms_ref) .. EOL .. OK

local function on_command(self, cmd)
  if 1 == counters'on_command'() then
    assert_equal(request .. EOL, cmd)
  else
    assert_equal(2, counters.on_command)
    assert_equal(sms_body .. '\26', cmd)
  end
end

local function on_cmgs(self, err, ref)
  counters'cmgs'()
  assert_nil(err)
  assert_equal(sms_ref, ref)
end

it('should ignore prompt without EOL',function()
  stream:on_command(on_command)

  assert_true(command:CMGS(len, sms_body, on_cmgs))

  assert_equal(stream, stream:append(request):append(EOL)) -- echo

  assert_equal(stream, stream:execute())
  assert_equal(1, counters.on_command)
  assert_equal(0, counters.cmgs)

  assert_equal(stream, stream:append(''):append('> '))    -- prompt

  assert_equal(stream, stream:execute())
  assert_equal(1, counters.on_command)
  assert_equal(0, counters.cmgs)
end)

it('should ignore second prompt without EOL',function()
  stream:on_command(on_command)

  assert_true(command:CMGS(len, sms_body, on_cmgs))

  assert_equal(stream, stream:append(request):append(EOL)) -- echo

  assert_equal(stream, stream:execute())
  assert_equal(1, counters.on_command)
  assert_equal(0, counters.cmgs)

  assert_equal(stream, stream:append(EOL):append('> '))    -- prompt

  assert_equal(stream, stream:execute())
  assert_equal(2, counters.on_command)
  assert_equal(0, counters.cmgs)

  assert_equal(stream, stream:append(response))

  assert_equal(stream, stream:execute())
  assert_equal(2, counters.on_command)
  assert_equal(1, counters.cmgs)

  counters.cmgs = 0
  counters.on_command = 0

  assert_true(command:CMGS(len, sms_body, on_cmgs))

  assert_equal(stream, stream:append(request):append(EOL)) -- echo

  assert_equal(stream, stream:execute())
  assert_equal(1, counters.on_command)
  assert_equal(0, counters.cmgs)

  assert_equal(stream, stream:append(''):append('> '))    -- prompt

  assert_equal(stream, stream:execute())
  assert_equal(1, counters.on_command)
  assert_equal(0, counters.cmgs)

end)

it('should interrupt by final response without prompt',function()
  stream:on_command(on_command)

  assert_true(command:CMGS(len, sms_body, on_cmgs))

  assert_equal(stream, stream:append(request):append(EOL)) -- echo
  assert_equal(stream, stream:append(response)) -- final response
  assert_equal(stream, stream:execute())
  assert_equal(1, counters.on_command)
  assert_equal(1, counters.cmgs)
end)

it('should interrupt by final response without prompt without echo',function()
  stream:on_command(on_command)

  assert_true(command:CMGS(len, sms_body, on_cmgs))

  assert_equal(stream, stream:append(response)) -- final response
  assert_equal(stream, stream:execute())
  assert_equal(1, counters.on_command)
  assert_equal(1, counters.cmgs)
end)

end

local _ENV = TEST_CASE'commands' if ENABLE then

local it = IT(_ENV or _M)

local stream, command, counter

function setup()
  stream   = assert(at.Stream(SELF))
  command  = assert(at.Commander(stream))
  counters = Counter()
end

it('ATZ', function()
  local request  = 'ATZ'..EOL
  local response = OK

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal(request, command)
  end)

  assert_true(command:ATZ(function(self, err, status)
    counters'callback'()
    assert_equal('OK', status)
  end))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(request)) -- echo

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(response))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(1, counters.callback)
end)

it('Echo', function()
  local request  = 'ATE1'..EOL
  local response = OK

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal(request, command)
  end)

  assert_true(command:Echo(true, function(self, err, status)
    counters'callback'()
    assert_equal('OK', status)
  end))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(request)) -- echo

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(response))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(1, counters.callback)
end)

it('CUSD response status 0', function()
  local request  = 'AT+CUSD=1,"*100#",15'..EOL
  local msg      = '\004\018\0040\004H\000 \0047\0040\004?\004@\004>\004A\000 \004?\004@\0048\004=\004O\004B\000,\000 \004>\0046\0048\0044\0040\0049\004B\0045\000 \004>\004B\0042\0045\004B\000 \004?\004>\000 \000S\000M\000S\000.'
  local response = '+CUSD: 0,"' .. msg .. '",72' .. '\r\n\r\nOK\r\n'

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal(request, command)
  end)

  assert_true(command:CUSD("*100#", function(self, err, status, message, dcs)
    counters'callback'()
    assert_equal(0,    status)
    assert_equal(msg,  message)
    assert_equal(72,   dcs)
  end))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(request)) -- echo

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(response))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(1, counters.callback)
end)

it('CUSD response status 2', function()
  local request  = 'AT+CUSD=1,"*100#",15'..EOL
  local msg      = '\004\018\0040\004H\000 \0047\0040\004?\004@\004>\004A\000 \004?\004@\0048\004=\004O\004B\000,\000 \004>\0046\0048\0044\0040\0049\004B\0045\000 \004>\004B\0042\0045\004B\000 \004?\004>\000 \000S\000M\000S\000.'
  local response = '+CUSD: 2' .. '\r\n\r\nOK\r\n'

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal(request, command)
  end)

  assert_true(command:CUSD("*100#", function(self, err, status, message, dcs)
    counters'callback'()
    assert_equal(2, status)
    assert_nil(     message)
    assert_nil(     dcs)
  end))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(request)) -- echo

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(response))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(1, counters.callback)
end)

it('Charsets list', function()
  local request  = 'AT+CSCS=?'..EOL
  local response = '+CSCS: ("GSM","HEX","IRA","PCCP","PCDN","UCS2","8859-1")' .. OK

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal(request, command)
  end)

  assert_true(command:Charsets(function(self, err, charset)
    counters'callback'()
    assert_table(charset)
    assert_equal( "GSM",    charset[1])
    assert_equal( "HEX",    charset[2])
    assert_equal( "IRA",    charset[3])
    assert_equal( "PCCP",   charset[4])
    assert_equal( "PCDN",   charset[5])
    assert_equal( "UCS2",   charset[6])
    assert_equal( "8859-1", charset[7])
  end))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(request)) -- echo

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(response))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(1, counters.callback)
end)

it('Charset get', function()
  local request  = 'AT+CSCS?'..EOL
  local response = '+CSCS: "8859-1"' .. OK

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal(request, command)
  end)

  assert_true(command:Charset(function(self, err, charset)
    counters'callback'()
    assert_equal( "8859-1", charset)
  end))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(request)) -- echo

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(response))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(1, counters.callback)
end)

it('Charset set', function()
  local request  = 'AT+CSCS="8859-1"'..EOL
  local response = OK

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal(request, command)
  end)

  assert_true(command:Charset("8859-1", function(self, err, status)
    counters'callback'()
    assert_equal( "OK", status)
  end))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(request)) -- echo

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(0, counters.callback)

  assert_equal(stream, stream:append(response))

  assert_equal(stream, stream:execute())

  assert_equal(1, counters.on_command)
  assert_equal(1, counters.callback)
end)

end

local _ENV = TEST_CASE'URC detect' if ENABLE then

local it = IT(_ENV or _M)

local stream, command, counter

function setup()
  stream   = assert(at.Stream(SELF))
  command  = assert(at.Commander(stream))
  counters = Counter()
end

it('CFUN without commands', function()
  local request  = 'ATZ'..EOL
  local response = OK

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal(request, command)
  end)

  stream:on_message(function()
    counters'on_message'()
  end)

  stream:on_unexpected(function(self, urc, info)
    counters'on_unexpected'()
    assert_equal('+CFUN', urc)
    assert_equal('1', info)
  end)

  assert_equal(stream, stream:append('+CFUN: 1'..EOL))

  assert_equal(stream, stream:execute())

  assert_equal(0, counters.on_command   )
  assert_equal(1, counters.on_message   )
  assert_equal(0, counters.on_unexpected)
end)

it('CFUN with another command', function()

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal('ATZ'..EOL, command)
  end)

  assert_true(command:ATZ(function(self, err, res)
    counters'callback'()
    assert_nil(err)
    assert_equal('OK', res)
  end))

  stream:on_message(function(self, urc, info)
    counters'on_message'()
    assert_equal('+CFUN', urc)
    assert_equal('1', info)
  end)

  stream:on_unexpected(function(self, urc, info)
    counters'on_unexpected'()
  end)

  assert_equal(stream, stream:append('+CFUN: 1'..EOL))
  assert_equal(stream, stream:execute())

  assert_equal(0, counters.callback   )
  assert_equal(1, counters.on_command   )
  assert_equal(1, counters.on_message   )
  assert_equal(0, counters.on_unexpected)

  assert_equal(stream, stream:append(OK))
  assert_equal(stream, stream:execute())

  assert_equal(1, counters.callback   )
  assert_equal(1, counters.on_command   )
  assert_equal(1, counters.on_message   )
  assert_equal(0, counters.on_unexpected)
end)

it('CFUN with same command', function()

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal('AT+CFUN=?'..EOL, command)
  end)

  assert_true(command:at('+CFUN=?', function(self, err, res)
    counters'callback'()
    assert_nil(err)
    assert_equal('+CFUN: 1', res)
  end))

  stream:on_message(function(self, urc, info)
    counters'on_message'()
    assert_equal('+CFUN', urc)
    assert_equal('2', info)
  end)

  stream:on_unexpected(function(self, urc, info)
    counters'on_unexpected'()
  end)

  assert_equal(stream, stream:append('+CFUN: 2'..EOL)) -- URC
  assert_equal(stream, stream:execute())

  assert_equal(0, counters.callback     )
  assert_equal(1, counters.on_command   )
  assert_equal(0, counters.on_message   )
  assert_equal(0, counters.on_unexpected)

  assert_equal(stream, stream:append('+CFUN: 1'..EOL)) -- response
  assert_equal(stream, stream:execute())

  assert_equal(0, counters.callback     )
  assert_equal(1, counters.on_command   )
  assert_equal(1, counters.on_message   )
  assert_equal(0, counters.on_unexpected)

  assert_equal(stream, stream:append(OK))
  assert_equal(stream, stream:execute())

  assert_equal(1, counters.callback     )
  assert_equal(1, counters.on_command   )
  assert_equal(1, counters.on_message   )
  assert_equal(0, counters.on_unexpected)
end)

it('double CFUN with same command', function()

  stream:on_command(function(self, command)
    counters'on_command'()
    assert_equal('AT+CFUN=?'..EOL, command)
  end)

  assert_true(command:at('+CFUN=?', function(self, err, res)
    counters'callback'()
    assert_nil(err)
    assert_equal('+CFUN: 1', res)
  end))

  stream:on_message(function(self, urc, info)
    counters'on_message'()
    assert_equal('+CFUN', urc)
    assert_equal('2', info)
  end)

  stream:on_unexpected(function(self, urc, info)
    counters'on_unexpected'()
  end)

  assert_equal(stream, stream:append('+CFUN: 2'..EOL)) -- URC
  assert_equal(stream, stream:execute())

  assert_equal(0, counters.callback     )
  assert_equal(1, counters.on_command   )
  assert_equal(0, counters.on_message   )
  assert_equal(0, counters.on_unexpected)

  assert_equal(stream, stream:append('+CFUN: 2'..EOL)) -- URC
  assert_equal(stream, stream:execute())

  assert_equal(0, counters.callback     )
  assert_equal(1, counters.on_command   )
  assert_equal(1, counters.on_message   )
  assert_equal(0, counters.on_unexpected)

  assert_equal(stream, stream:append('+CFUN: 1'..EOL)) -- response
  assert_equal(stream, stream:execute())

  assert_equal(0, counters.callback     )
  assert_equal(1, counters.on_command   )
  assert_equal(2, counters.on_message   )
  assert_equal(0, counters.on_unexpected)

  assert_equal(stream, stream:append(OK))
  assert_equal(stream, stream:execute())

  assert_equal(1, counters.callback     )
  assert_equal(1, counters.on_command   )
  assert_equal(2, counters.on_message   )
  assert_equal(0, counters.on_unexpected)
end)

end

local _ENV = TEST_CASE'--tmp--' if true then

local it = IT(_ENV or _M)

local stream, command, counter

function setup()
  stream   = assert(at.Stream(SELF))
  command  = assert(at.Commander(stream))
  counters = Counter()
end

end

RUN()
