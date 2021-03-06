package.path = "..\\src\\lua\\?.lua;" .. package.path

pcall(require, "luacov")

local utils     = require "utils"
local TEST_CASE = require "lunit".TEST_CASE

local debug, print = debug, print

local RUN               = utils.RUN
local IT, CMD, PASS     = utils.IT, utils.CMD, utils.PASS
local nreturn, is_equal = utils.nreturn, utils.is_equal

local uv       = require "lluv"
local ut       = require "lluv.utils"
local GsmModem = require "lluv.gsmmodem"
local gutils   = require "lluv.gsmmodem.utils"

print("------------------------------------")
print("Module    name: " .. GsmModem._NAME);
print("Module version: " .. GsmModem._VERSION);
print("Lua    version: " .. (_G.jit and _G.jit.version or _G._VERSION))
print("------------------------------------")
print("")

local function bin2hex(str)
  local t = {string.byte(str, 1, #str)}
  for i = 1, #t do t[i] = string.format('%.2X', t[i]) end
  return table.concat(t)
end

---------------------------------------------------------------
local MocStream = ut.class() do

function MocStream:__init(port_name, opt)
  self._i_buffer  = ut.Buffer.new()
  self._o_buffer  = ut.Buffer.new()

  self._read_timer = uv.timer():start(0, 100, function()
    local cb = self._read_cb
    while self._read_cb and cb == self._read_cb do
      local chunk = self._o_buffer:read_some()
      if not chunk then break end
      if type(chunk) == 'string' then cb(self, nil, chunk) else cb(self, chunk) end
    end
  end):stop()

  return self
end

function MocStream:close(cb)
  self._read_timer:close(function()
    if cb then cb(self) end
  end)
  return self
end

function MocStream:open(cb)
  uv.defer(cb, self)
  return self
end

function MocStream:start_read(cb)
  self._read_cb = assert(cb)
  self._read_timer:again()
  return self
end

function MocStream:stop_read()
  self._read_cb = nil
  self._read_timer:stop()
  return self
end

function MocStream:write(data, cb)
  self._i_buffer:append(data)
  if self._on_write then
    uv.defer(self._on_write, self, data)
  end
  if cb then
    uv.defer(cb, self)
  end
  return self
end

function MocStream:moc_write(data)
  self._o_buffer:append(data)
  return self
end

function MocStream:moc_on_input(handler)
  self._on_write = handler
  return self
end

end
---------------------------------------------------------------

local function MakeStream(t)

local Stream = MocStream.new() do
local buffer = ut.Buffer.new()
local iqueue = ut.Queue.new()

Stream:moc_on_input(function(self, data)
  buffer:append(data)

  while not buffer:empty() do
    local t = iqueue:peek()

    if not t then
      error('Unexpected: `' .. buffer:read_all() .. '`')
    end

    if type(t) == 'function' then
      iqueue:pop()
      t(self)
    else

      local expected = type(t) == 'table' and t[1] or t

      local chunk = buffer:read_n(#expected)
      if not chunk then break end

      if expected ~= chunk then
        error('Expected: `' .. expected .. '` but got: `' .. chunk .. '`')
      end

      local response = type(t) == 'table' and t[2]
      if response then
        self:moc_write(response)
      end

      iqueue:pop()
    end
  end

  while not iqueue:empty() do
    local t = iqueue:peek()
    if type(t) == 'function' then
      iqueue:pop()
      t(self)
    else
      break
    end
  end

end)

for _, v in ipairs(t) do
  iqueue:push(v)
end

return Stream, iqueue

end

end

local call_count

local function called(n)
  call_count = call_count + (n or 1)
  return call_count
end

local TEST_TIMEOUT = 5000
local ENABLE = true

local _ENV = TEST_CASE'send_sms' if ENABLE then

local it = IT(_ENV or _M)

function setup()
  gutils.reset_reference()
  call_count = 0
  uv.timer():start(TEST_TIMEOUT, function() uv.stop() end):unref()
end

function teardown()
  uv.close(true)
end

local hello_utf8   = '\208\191\209\128\208\184\208\178\208\181\209\130'

it('send sms with unknown charset', function()
  local Stream = MakeStream{}

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:send_sms('+77777777777', hello_utf8, {charset = 'some-crazy-charset'}, function(self, err, res)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_not_nil(err )
      assert_equal('ICONV', err:cat())
      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
end)

it('send utf8 sms', function()
  local Stream = MakeStream{
    {
      'AT+CMGS=25\r\n',
      '\r> ',
    };
    {
      '0021010B917777777777F700080C043F04400438043204350442\026',
      'AT+CMGS=25\r\n+CMGS: 1,\r\n\r\nOK\r\n'
    };
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:send_sms('+77777777777', hello_utf8, {charset = 'utf-8'}, function(self, err, res)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_equal(1, res)
      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
end)

it('multipart sms', function()
  local Stream = MakeStream{
    {
      'AT+CMGS=153\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70000A0050003010301D06536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9\026',
      'AT+CMGS=153\r\n+CMGS: 1,\r\n\r\nOK\r\n'
    };

    {
      'AT+CMGS=153\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70000A0050003010302D86F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD1\026',
      'AT+CMGS=153\r\n+CMGS: 2,\r\n\r\nOK\r\n'
    };

    {
      'AT+CMGS=58\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F7000033050003010303CA6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B\026',
      'AT+CMGS=58\r\n+CMGS: 3,\r\n\r\nOK\r\n'
    };
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:send_sms('+77777777777', ('hello'):rep(70), function(self, err, res)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_table(res      )
      assert_equal(1, res[1])
      assert_equal(2, res[2])
      assert_equal(3, res[3])

      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
end)

it('multipart utf8 sms', function()
  local Stream = MakeStream{
    {
      'AT+CMGS=149\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F7000888050003010201043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F0440043804320435\026',
      'AT+CMGS=149\r\n+CMGS: 1,\r\n\r\nOK\r\n'
    };

    {
      'AT+CMGS=129\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70008740500030102020442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442043F04400438043204350442\026',
      'AT+CMGS=129\r\n+CMGS: 2,\r\n\r\nOK\r\n'
    };

  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:send_sms('+77777777777', hello_utf8:rep(20), {charset = 'utf-8'}, function(self, err, res)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_table(res      )
      assert_equal(1, res[1])
      assert_equal(2, res[2])

      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
end)

it('multipart sms with delivery report #1', function()
  local Stream = MakeStream{
    {
      'AT+CMGS=153\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70000A0050003010301D06536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9\026',
      'AT+CMGS=153\r\n+CMGS: 1,\r\n\r\nOK\r\n'
    };

    {
      'AT+CMGS=153\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70000A0050003010302D86F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD1\026',
      'AT+CMGS=153\r\n+CMGS: 2,\r\n\r\nOK\r\n'
    };

    {
      'AT+CMGS=58\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F7000033050003010303CA6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B\026',
      'AT+CMGS=58\r\n+CMGS: 3,\r\n\r\nOK\r\n'
    };

    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006' .. '01' .. '0B917777777777F75150121183832151501211346521' .. '46' .. '\r\n')
    end;

    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006' .. '02' .. '0B917777777777F75150121183832151501211346521' .. '46' .. '\r\n')
    end;

    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006' .. '03' .. '0B917777777777F75150121183832151501211346521' .. '46' .. '\r\n')
    end;
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:send_sms('+77777777777', ('hello'):rep(70), {waitReport = true}, function(self, err, ref, res)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_table(ref      )
      assert_table(res      )

      for i = 1, 3 do
        assert_equal(i, ref[i])
        local status = assert_table(res[ref[i]])
        assert_false(status.success)
        assert_equal(70, status.status)
        assert_false(status.temporary)
        assert_false(status.recovered)
        assert_string(status.info)
      end

      self:close()
    end)
  end)

  uv.run(debug.traceback)

  assert_equal(1, called(0))
end)

it('multipart sms with delivery report #2', function()
  local Stream = MakeStream{
    {
      'AT+CMGS=153\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70000A0050003010301D06536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9\026',
      'AT+CMGS=153\r\n+CMGS: 1,\r\n\r\nOK\r\n'
    };

    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006' .. '01' .. '0B917777777777F75150121183832151501211346521' .. '46' .. '\r\n')
    end;

    {
      'AT+CMGS=153\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70000A0050003010302D86F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD1\026',
      'AT+CMGS=153\r\n+CMGS: 2,\r\n\r\nOK\r\n'
    };

    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006' .. '02' .. '0B917777777777F75150121183832151501211346521' .. '46' .. '\r\n')
    end;

    {
      'AT+CMGS=58\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F7000033050003010303CA6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B\026',
      'AT+CMGS=58\r\n+CMGS: 3,\r\n\r\nOK\r\n'
    };

    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006' .. '03' .. '0B917777777777F75150121183832151501211346521' .. '46' .. '\r\n')
    end;
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:send_sms('+77777777777', ('hello'):rep(70), {waitReport = true}, function(self, err, ref, res)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_table(ref      )
      assert_table(res      )

      for i = 1, 3 do
        assert_equal(i, ref[i])
        local status = assert_table(res[ref[i]])
        assert_false(status.success)
        assert_equal(70, status.status)
        assert_false(status.temporary)
        assert_false(status.recovered)
        assert_string(status.info)
      end

      self:close()
    end)
  end)

  uv.run(debug.traceback)

  assert_equal(1, called(0))
end)

it('multipart sms with delivery report #3', function()
  local Stream = MakeStream{
    {
      'AT+CMGS=153\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70000A0050003010301D06536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9\026',
      'AT+CMGS=153\r\n+CMGS: 1,\r\n\r\nOK\r\n'
    };

    {
      'AT+CMGS=153\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70000A0050003010302D86F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD1\026',
      'AT+CMGS=153\r\n+CMGS: 2,\r\n\r\nOK\r\n'
    };

    {
      'AT+CMGS=58\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F7000033050003010303CA6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B\026',
      'AT+CMGS=58\r\n+CMGS: 3,\r\n\r\nOK\r\n'
    };

    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006' .. '02' .. '0B917777777777F75150121183832151501211346521' .. '46' .. '\r\n')
    end;

    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006' .. '03' .. '0B917777777777F75150121183832151501211346521' .. '46' .. '\r\n')
    end;

    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006' .. '01' .. '0B917777777777F75150121183832151501211346521' .. '46' .. '\r\n')
    end;
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:send_sms('+77777777777', ('hello'):rep(70), {waitReport = true}, function(self, err, ref, res)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_table(ref      )
      assert_table(res      )

      for i = 1, 3 do
        assert_equal(i, ref[i])
        local status = assert_table(res[ref[i]])
        assert_false(status.success)
        assert_equal(70, status.status)
        assert_false(status.temporary)
        assert_false(status.recovered)
        assert_string(status.info)
      end

      self:close()
    end)
  end)

  uv.run(debug.traceback)

  assert_equal(1, called(0))
end)

end

local _ENV = TEST_CASE'read_sms' if ENABLE then

local it = IT(_ENV or _M)

function setup()
  gutils.reset_reference()
  call_count = 0
  uv.timer():start(TEST_TIMEOUT, function() uv.stop() end):unref()
end

function teardown()
  uv.close(true)
end

it('read not existed sms', function()
  local Stream, q = MakeStream{
    {
      'AT+CMGR=11\r\n',
      '\r\nOK\r\n'
    },
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:read_sms(11, function(self, err, sms, del)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_nil  (sms      )

      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
  assert_true(q:empty())
end)

it('read invalid memory index', function()
  local Stream, q = MakeStream{
    {
      'AT+CMGR=11\r\n',
      '\r\n+CMS ERROR: 321\r\n'
    },
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:read_sms(11, function(self, err, sms, del)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_not_nil(err      )
      assert_equal('GSM-AT', err:cat())
      assert_equal('CMS',    err:name())
      assert_equal(321,      err:no())
      assert_nil(sms      )

      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
  assert_true(q:empty())
end)

it('read sms with delete', function()
  local Stream, q = MakeStream{
    {
      'AT+CMGR=11\r\n',
      '\r\n+CMGR: 0,,26\r\n07919761989901F0240B917777777777F700005150225163642108AE30F9AC6EDFE1\r\n\r\nOK\r\n'
    },
    {
      'AT+CMGD=11\r\n',
      '\r\nOK\r\n'
    },
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:read_sms(11, {delete = true}, function(self, err, sms, del)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_nil  (del      )

      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
  assert_true(q:empty())
end)

it('read sms from memory with delete', function()
  local Stream, q = MakeStream{
    {
      'AT+CPMS="SM"\r\n',
      '\r\n+CPMS: 1,20,1,20,1,20\r\n\r\nOK\r\n'
    },
    {
      'AT+CMGR=11\r\n',
      '\r\n+CMGR: 0,,26\r\n07919761989901F0240B918888888888F800005150225163642108AE30F9AC6EDFE1\r\n\r\nOK\r\n'
    },
    {
      'AT+CMGD=11\r\n',
      '\r\nOK\r\n'
    },

    {
      'AT+CPMS="ME"\r\n',
      '\r\n+CPMS: 1,20,1,20,1,20\r\n\r\nOK\r\n'
    },
    {
      'AT+CMGR=12\r\n',
      '\r\n+CMGR: 0,,26\r\n07919761989901F0240B917777777777F700005150225163642108AE30F9AC6EDFE1\r\n\r\nOK\r\n'
    },
    {
      'AT+CMGD=12\r\n',
      '\r\nOK\r\n'
    },
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:read_sms(11, {memory = "SM", delete = true}, function(self, err, sms, del)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_nil  (del      )
      assert_equal("+88888888888", sms:number())
    end)

    self:read_sms(12, {memory = "ME", delete = true}, function(self, err, sms, del)
      assert_equal(2, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_nil  (del      )
      assert_equal("+77777777777", sms:number())

      self:close()
    end)
  end)

  uv.run()

  assert_equal(2, called(0))
  assert_true(q:empty())
end)

it('read sms with delete fail', function()
  local Stream, q = MakeStream{
    {
      'AT+CMGR=11\r\n',
      '\r\n+CMGR: 0,,26\r\n07919761989901F0240B917777777777F700005150225163642108AE30F9AC6EDFE1\r\n\r\nOK\r\n'
    },
    {
      'AT+CMGD=11\r\n',
      '\r\nERROR\r\n'
    },
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:read_sms(11, {delete = true}, function(self, err, sms, del)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_not_nil(del      )

      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
  assert_true(q:empty())
end)

it('read sms in text mode', function()
  local Stream, q = MakeStream{
    {
      'AT+CMGR=11\r\n',
      '\r\n+CMGR: "REC READ","+77777777777",,"15/04/24,13:54:54+12"\r\nPrivet\r\n\r\nOK\r\n'
    },
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:read_sms(11, function(self, err, sms)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_equal('DELIVER',      sms:type())
      assert_equal('+77777777777', sms:number())
      assert_equal('Privet',       sms:text())

      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
  assert_true(q:empty())
end)

it('read truncated sms ', function()
  local Stream, q = MakeStream{
    {
      'AT+CMGR=11\r\n',
      '\r\n+CMGR: 0,,26\r\n07919761989901F0240B917777777777F700005150225163642108AE30F9AC\r\n\r\nOK\r\n'
    },
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:read_sms(11, {delete = true}, function(self, err, sms, del)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert      (err)
      assert_nil  (sms)

      self:close()
    end)
  end)

  uv.run(debug.traceback)

  assert_equal(1, called(0))
  assert_true(q:empty())
end)

it('iterare over all sms', function()
  local Stream, q = MakeStream{
    {
      'AT+CMGL=4\r\n',
      '+CMGL: 1,1,,26'
      .. '\r\n' ..
      '07919761989901F0240B917777777777F70000514042314545210720A83C6D2FD301'
      .. '\r\n' .. 
      '+CMGL: 3,1,,26'
      .. '\r\n' .. 
      '07919761989901F0240B917777777777F70000514042314545210720A8'
      .. -- NO EOL
      '+CMGL: 6,1,,26'
      .. '\r\n' .. 
      '07919761989901F0240B917777777777F70000514042314545210720A83C6D2FD301'
       .. '\r\nOK\r\n'
    },
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:each_sms(function(self, err, index, sms, total, last)
      assert_equal(self, modem)
      assert_equal(3, total)
      assert_boolean(last)

      if index == 1 then
        assert_equal(1, called())
        assert_nil  (err)
        assert_false(last)
        assert_not_nil(sms)
        assert_nil(sms_err)
        assert_equal('+77777777777', sms:number())
        assert_equal(' Privet',      sms:text())
        assert_equal(index, sms:index())
      end

      if index == 3 then
        assert_equal(2, called())
        assert_not_nil(err)
        assert_false(last)
        assert_nil(sms)
        assert_equal('TPDU',    err:cat())
        assert_equal('EFORMAT', err:name())
      end

      if index == 6 then
        assert_equal(3, called())
        assert_nil  (err)
        assert_true(last)
        assert_not_nil(sms)
        assert_nil(sms_err)
        assert_equal('+77777777777', sms:number())
        assert_equal(' Privet',      sms:text())
        assert_equal(index, sms:index())
        self:close()
      end

    end)
  end)

  uv.run(debug.traceback)

  assert_equal(3, called(0))
  assert_true(q:empty())
end)

end

local _ENV = TEST_CASE'send_sms/wait_delivery_report' if ENABLE then

local it = IT(_ENV or _M)

local Stream

function setup()
  gutils.reset_reference()
  call_count = 0

  Stream = MakeStream{
    {
      'AT+CMGS=18\r\n',
      '\r> ',
    };
    {
      '0021010B917777777777F7000005E8329BFD06\26',
      'AT+CMGS=18\r\n+CMGS: 40,\r\n\r\nOK\r\n'
    };
    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006270B917777777777F7515012113320215150121133402100\r\n')
    end;
    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006280B917777777777F7515012118383215150121183752130\r\n')
    end;
    function(stream)
      stream:moc_write('\r\n+CDS: 25\r\n')
      stream:moc_write('07919761989901F006280B917777777777F7515012118383215150121134652146\r\n')
    end;
  }

  uv.timer():start(TEST_TIMEOUT, function() uv.stop() end):unref()
end

function teardown()
  uv.close(true)
end

it('wait temporary response', function()
  local modem = GsmModem.new(Stream)

  modem:open(function()
    modem:send_sms('+77777777777', 'hello', {waitReport = 'any'}, function(self, err, ref, rep)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_equal(ref, 40  )
      assert_table(rep)
      assert_true(rep.temporary)
      assert_false(rep.success)
      assert_equal(48, rep.status)
      assert_false(rep.recovered)
      assert_string(rep.info)
      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
end)

it('wait final response', function()
  local modem = GsmModem.new(Stream)

  modem:open(function()
    modem:send_sms('+77777777777', 'hello', {waitReport = 'final'}, function(self, err, ref, rep)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      assert_equal(ref, 40  )
      assert_table(rep)
      assert_false(rep.temporary)
      assert_false(rep.success)
      assert_equal(70, rep.status)
      assert_false(rep.recovered)
      assert_string(rep.info)
      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))
end)

it('wait timeout', function()
  Stream = MakeStream{
    {
      'AT+CMGS=18\r\n',
      '\r> ',
    };
    {
      '0021010B917777777777F7000005E8329BFD06\26',
      'AT+CMGS=18\r\n+CMGS: 38,\r\n\r\nOK\r\n'
    };
  }

  local modem = GsmModem.new(Stream)

  local timeout1 = uv.timer():start(1000, function()
    assert_equal(1, called())
  end)

  modem:open(function()
    modem:send_sms('+77777777777', 'hello', {waitReport = 'any', timeout = 2000}, function(self, err, ref)
      assert_equal(2, called())
      assert_equal(self, modem)
      assert(err)
      assert_equal('TIMEOUT', err:name())
      assert_equal(38, ref)
      self:close()
    end)
  end)

  uv.run()

  assert_equal(2, called(0))
end)

it('wait timeout on multipart sms', function()
  local Stream = MakeStream{
    {
      'AT+CMGS=153\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70000A0050003010301D06536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9\026',
      'AT+CMGS=153\r\n+CMGS: 1,\r\n\r\nOK\r\n'
    };

    {
      'AT+CMGS=153\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F70000A0050003010302D86F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD1\026',
      'AT+CMGS=153\r\n+CMGS: 2,\r\n\r\nOK\r\n'
    };

    {
      'AT+CMGS=58\r\n',
      '\r> ',
    };
    {
      '0061010B917777777777F7000033050003010303CA6CF61B5D66B3DFE8329BFD4697D9EC37BACC66BFD16536FB8D2EB3D96F7499CD7EA3CB6CF61B\026',
      'AT+CMGS=58\r\n+CMGS: 3,\r\n\r\nOK\r\n'
    };
  }

  local modem = GsmModem.new(Stream)

  local timeout1 = uv.timer():start(1000, function()
    assert_equal(1, called())
  end)

  modem:open(function(self, ...)
    self:send_sms('+77777777777', ('hello'):rep(70), {waitReport = 'any', timeout = 2000}, function(self, err, res)
      assert_equal(2, called())
      assert_equal(self, modem)
      assert(err)
      assert_equal('TIMEOUT', err:name())
      assert_table(   res)
      assert_equal(1, res[1])
      assert_equal(2, res[2])
      assert_equal(3, res[3])

      self:close()
    end)
  end)

  uv.run()

  assert_equal(2, called(0))
end)

end

local _ENV = TEST_CASE'urc data' if ENABLE then

local it = IT(_ENV or _M)

local Stream

function setup()
  gutils.reset_reference()
  call_count = 0
  uv.timer():start(TEST_TIMEOUT, function() uv.stop() end):unref()
end

function teardown()
  uv.close(true)
end

it('CMT in Text mode', function()
  Stream = MakeStream{}

  local modem = GsmModem.new(Stream)

  local sms
  modem:on('sms::recv', function(self, event, data)
    sms = data
    self:close()
    called()
  end)

  modem:open(function()
    Stream:moc_write('+CMT: "+77777777777",,"15/05/22,11:00:58+12"' .. '\r\n')
    Stream:moc_write('1234567890' .. '\r\n')
  end)

  uv.timer():start(2000, function()
    modem:close()
  end):unref()

  uv.run()

  assert_equal(1, called(0))
  assert(sms)
  assert_equal('+77777777777', sms:number())
  assert_equal('1234567890', sms:text())
end)

it('CMT in PDU mode', function()
  Stream = MakeStream{}

  local modem = GsmModem.new(Stream)

  local sms
  modem:on('sms::recv', function(self, event, data)
    sms = data
    self:close()
    called()
  end)

  modem:open(function()
    Stream:moc_write('+CMT: ,28' .. '\r\n')
    Stream:moc_write('07919761989901F0040B917777777777F70000515022114032210A31D98C56B3DD703918' .. '\r\n')
  end)

  uv.timer():start(2000, function()
    modem:close()
  end):unref()

  uv.run()

  assert_equal(1, called(0))
  assert(sms)
  assert_equal('+77777777777', sms:number())
  assert_equal('1234567890', sms:text())
end)

it('CDS in PDU mode', function()
  Stream = MakeStream{}

  local modem = GsmModem.new(Stream)

  local sms
  modem:on('report::recv', function(self, event, data)
    self:close()
    sms = data
    called()
  end)

  modem:open(function()
    Stream:moc_write('\r\n+CDS: 25\r\n')
    Stream:moc_write('07919761989901F006280B917777777777F7515012118383215150121183752130\r\n')
  end)

  uv.timer():start(2000, function()
    modem:close()
  end):unref()

  uv.run()

  assert_equal(1, called(0))
  assert(sms)
  assert_equal('+77777777777', sms:number())
  assert_equal(40, sms:reference())
  local _, status = assert_false(sms:delivery_status())
  assert_table(status)
  assert_equal(48, status.status)
  assert_false(status.success)
  assert_true(status.temporary)
  assert_false(status.recovered)
  assert_string(status.info)
end)

it('CDS in Text mode (single line)', function()
  Stream = MakeStream{}

  local modem = GsmModem.new(Stream)

  local sms
  modem:on('report::recv', function(self, event, data)
    sms = data
    self:close()
    called()
  end)

  modem:open(function()
    Stream:moc_write('\r\n+CDS: 6,46,"+77777777777",145,"15/05/22,14:14:13+12","15/05/22,14:14:13+12",48\r\n')
  end)

  uv.timer():start(2000, function()
    modem:close()
  end):unref()

  uv.run()

  assert_equal(1, called(0))

  assert(sms)
  assert_equal('+77777777777', sms:number())
  assert_equal(46, sms:reference())
  local _, status = assert_false(sms:delivery_status())
  assert_table(status)
  assert_equal(48, status.status)
  assert_false(status.success)
  assert_true(status.temporary)
  assert_false(status.recovered)
  assert_string(status.info)
end)

it('CDS in Text mode (multi line)', function()
  Stream = MakeStream{}

  local modem = GsmModem.new(Stream)

  modem:on('report::recv', function(self, event, data)
    sms = data
    self:close()
    called()
  end)

  modem:open(function()
    Stream:moc_write('\r\n+CDS: \r\n6,46,"+77777777777",145,"15/05/22,14:14:13+12","15/05/22,14:14:13+12",48\r\n')
  end)

  uv.timer():start(2000, function()
    modem:close()
  end):unref()

  uv.run(debug.traceback)

  assert_equal(1, called(0))
  assert(sms)
  assert_equal('+77777777777', sms:number())
  assert_equal(46, sms:reference())
  local _, status = assert_false(sms:delivery_status())
  assert_table(status)
  assert_equal(48, status.status)
  assert_false(status.success)
  assert_true(status.temporary)
  assert_false(status.recovered)
  assert_string(status.info)
end)

it('CMTI', function()
  Stream = MakeStream{}

  local modem = GsmModem.new(Stream)

  modem:on('sms::save', function(self, event, index, mem)
    assert_equal(1, called())
    assert_equal(9, index)
    assert_equal('SM', mem)
    self:close()
  end)

  modem:open(function()
    Stream:moc_write('\r\n+CMTI: "SM",9\r\n')
  end)

  uv.timer():start(2000, function()
    modem:close()
  end):unref()

  uv.run()

  assert_equal(1, called(0))
end)

it('CLIP', function()
  Stream = MakeStream{}

  local modem = GsmModem.new(Stream)

  modem:on('call', function(self, event, ani, ton)
    assert_equal(1, called())
    assert_equal('+77777777777', ani)
    assert_equal(145, ton)
    self:close()
  end)

  modem:open(function()
    Stream:moc_write('\r\n+CLIP: "+77777777777",145,"",,"",0\r\n')
  end)

  uv.timer():start(2000, function()
    modem:close()
  end):unref()

  uv.run()

  assert_equal(1, called(0))
end)

it('Unexpected', function()
  Stream = MakeStream{}

  local modem = GsmModem.new(Stream)

  modem:on('unexpected', function(self, event, line)
    assert_equal(1, called())
    assert_equal('OK', line)
    self:close()
  end)

  modem:open(function()
    Stream:moc_write('\r\n\r\nOK\r\n')
  end)

  uv.timer():start(2000, function()
    modem:close()
  end):unref()

  uv.run()

  assert_equal(1, called(0))
end)

end

local _ENV = TEST_CASE'delete_sms' if ENABLE then

local it = IT(_ENV or _M)

function setup()
  gutils.reset_reference()
  call_count = 0
  uv.timer():start(TEST_TIMEOUT, function() uv.stop() end):unref()
end

function teardown()
  uv.close(true)
end

it('delete sms from memory', function()
  local Stream, q = MakeStream{
    {
      'AT+CPMS="SM"\r\n',
      '\r\n+CPMS: 1,20,1,20,1,20\r\n\r\nOK\r\n'
    },
    {
      'AT+CMGD=11\r\n',
      '\r\nOK\r\n'
    },

    {
      'AT+CPMS="ME"\r\n',
      '\r\n+CPMS: 1,20,1,20,1,20\r\n\r\nOK\r\n'
    },
    {
      'AT+CMGD=12\r\n',
      '\r\nOK\r\n'
    },

    {
      'AT+CPMS="IM"\r\n',
      '\r\nERROR\r\n'
    },
  }

  local modem = GsmModem.new(Stream)

  modem:open(function(self, ...)
    self:delete_sms(11, {memory = 'SM'}, function(self, err)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil(err)
    end)

    self:delete_sms(12, {memory = 'ME'}, function(self, err)
      assert_equal(2, called())
      assert_equal(self, modem)
      assert_nil(err)
    end)

    self:delete_sms(13, {memory = 'IM'}, function(self, err)
      assert_equal(3, called())
      assert_equal(self, modem)
      assert_not_nil(err)

      self:close()
    end)
  end)

  uv.run(debug.traceback)

  assert_equal(3, called(0))
  assert_true(q:empty())
end)

end

local _ENV = TEST_CASE'send_ussd' if ENABLE then

local it = IT(_ENV or _M)

function setup()
  gutils.reset_reference()
  call_count = 0
  uv.timer():start(TEST_TIMEOUT, function() uv.stop() end):unref()
end

function teardown()
  uv.close(true)
end

it('should returns ussd message', function()
  local msg_ucs2 = '\0008\0001\000.\0006\0000\000 \004@\000.\000\n\004"\004>\004G\004=\004K\0049\000 \004?\004@\004>\0043\004=\004>\0047\000 \004?\004>\0043\004>\0044\004K\000 \0042\000 \0042\0040\004H\0045\004<\000 \0043\004>\004@\004>\0044\0045\000!\000 \0007\0044\004=\000.\000 \0041\0045\004A\004?\004;\0040\004B\004=\004>\000!\000 \004\031\004>\0044\004:\004;\000.\000:\000 \000*\0003\0000\0009\000#'
  local msg_utf8 = '81.60 \209\128.\n\208\162\208\190\209\135\208\189\209\139\208\185 \208\191\209\128\208\190\208\179\208\189\208\190\208\183 \208\191\208\190\208\179\208\190\208\180\209\139 \208\178 \208\178\208\176\209\136\208\181\208\188 \208\179\208\190\209\128\208\190\208\180\208\181! 7\208\180\208\189. \208\177\208\181\209\129\208\191\208\187\208\176\209\130\208\189\208\190! \208\159\208\190\208\180\208\186\208\187.: *309#'

  local status, dcs = 0, 72
  local Stream = MakeStream{
    {
      'AT+CUSD=1,"*102#",15\r\n',
      ('+CUSD: %d,"%s",%d\r\n\r\nOK\r\n'):format(status, msg_ucs2, dcs)
    };
  }

  local modem = GsmModem.new(Stream)

  local ussd
  modem:open(function(self, ...)
    self:send_ussd('*102#', function(self, err, res)
      assert_equal(1, called())
      assert_equal(self, modem)
      assert_nil  (err      )
      ussd = assert_table(res)
      self:close()
    end)
  end)

  uv.run()

  assert_equal(1, called(0))

  assert_equal(dcs, ussd:dcs())
  local t = assert_table(ussd:dcs(true))
  assert_equal('UCS2', t.codec)
  assert_false(t.compressed)
  assert_equal(4, t.group)
  assert_equal(0, t.reserved)
  assert_equal(msg_ucs2, ussd:text('UCS-2BE'))
  assert_equal(status, ussd:status())
  assert_equal(msg_utf8, ussd:text('utf-8'))
end)

end

local _ENV = TEST_CASE'gutils' if ENABLE then

local it = IT(_ENV or _M)

local BOM_LE        = '\255\254'
local BOM_BE        = '\254\255'
local hello_utf8    = '\208\191\209\128\208\184\208\178\208\181\209\130'
local hello_ucs2_le = BOM_LE .. '?\4@\0048\0042\0045\4B\4'
local hello_ucs2_be = BOM_BE .. '\4?\4@\0048\0042\0045\4B'
local hello_ucs2    = '\4?\4@\0048\0042\0045\4B'

it('should decode uusd palin', function()
  local msg = "*100#"
  local dcs = 15
  assert_equal(msg, gutils.DecodeUssd(msg, dcs))
end)

it('should decode uusd IRA', function()
  -- 'Ваш запрос принят, ожидайте ответ по SMS.' in UCS-2
  local result = "041204300448002004370430043F0440043E04410020043F04400438043D044F0442002C0020043E04360438043404300439044204350020043E04420432043504420020043F043E00200053004D0053002E"
  local msg = "\004\018\0040\004H\000 \0047\0040\004?\004@\004>\004A\000 "
    .. "\004?\004@\0048\004=\004O\004B\000,\000 \004>\0046\0048\0044"
    .. "\0040\0049\004B\0045\000 \004>\004B\0042\0045\004B\000 \004?"
    .. "\004>\000 \000S\000M\000S\000."
  local dcs = 72

  local s = assert_string(gutils.DecodeUssd(msg, dcs, 'UCS-2BE'))
  assert_equal(result, bin2hex(s))
end)

it('should decode uusd HEX', function()
  -- 'Ваш запрос принят, ожидайте ответ по SMS.' in UCS-2
  local result = "041204300448002004370430043F0440043E04410020043F04400438043D044F0442002C0020043E04360438043404300439044204350020043E04420432043504420020043F043E00200053004D0053002E"
  local dcs = 72
  local msg = "041204300448002004370430043F0440043E04410020043F044004" ..
        "38043D044F0442002C0020043E0436043804340430043904420435" ..
        "0020043E04420432043504420020043F043E00200053004D0053002E"

  local s = assert_string(gutils.DecodeUssd(msg, dcs, 'UCS-2BE'))
  assert_equal(result, bin2hex(s))
end)

it('should decode ucs2 as big endian by default', function()
  local s = assert_string(gutils.DecodeUcs2(hello_ucs2, 'utf-8'))
  assert_equal(bin2hex(hello_utf8), bin2hex(s))
end)

it('should decode ucs2 with big endian BOM', function()
  local s = assert_string(gutils.DecodeUcs2(hello_ucs2_be, 'utf-8'))
  assert_equal(bin2hex(hello_utf8), bin2hex(s))
end)

it('should decode ucs2 with little endian BOM', function()
  local s = assert_string(gutils.DecodeUcs2(hello_ucs2_le, 'utf-8'))
  assert_equal(bin2hex(hello_utf8), bin2hex(s))
end)

end

RUN()
