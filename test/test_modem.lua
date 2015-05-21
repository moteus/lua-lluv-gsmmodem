package.path = "..\\src\\lua\\?.lua;" .. package.path

local utils     = require "utils"
local TEST_CASE = require "lunit".TEST_CASE

local RUN               = utils.RUN
local IT, CMD, PASS     = utils.IT, utils.CMD, utils.PASS
local nreturn, is_equal = utils.nreturn, utils.is_equal

local uv       = require "lluv"
local ut       = require "lluv.utils"
local GsmModem = require "lluv.gsmmodem"
local gutils   = require "lluv.gsmmodem.utils"

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

return Stream

end

end

local call_count

local function called(n)
  call_count = call_count + (n or 1)
  return call_count
end

local ENABLE = true

local _ENV = TEST_CASE'send_sms' if ENABLE then

local it = IT(_ENV or _M)

function setup()
  gutils.reset_reference()
  call_count = 0
end

function teardown()
  uv.close(true)
end

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

end


RUN()
