------------------------------------------------------------------
--
--  Author: Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Copyright (C) 2015 Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Licensed according to the included 'LICENSE' document
--
--  This file is part of lua-lluv-gsmmodem library.
--
------------------------------------------------------------------

local ut     = require "lluv.utils"
local Error  = require "lluv.gsmmodem.error".error
local utils  = require "lluv.gsmmodem.utils"

local unpack = unpack or table.unpack -- luacheck: ignore unpack

local pack_args   = utils.pack_args
local split_args  = utils.split_args

local function dummy()end

local DummyLogger = {} do
  local lvl = {'emerg','alert','fatal','error','warning','notice','info','debug','trace'}
  for _, l in ipairs(lvl) do
    DummyLogger[l] = dummy;
    DummyLogger[l..'_dump'] = dummy;
  end
end

local is_async_msg do

-- URC without args
local t = {
  RING                  = "Ringing",
  BUSY                  = "Busy",
  RDY                   = "Ready", -- ready to accept AT command
  ["Call Ready"]        = "Call Ready",
  ["GPS Ready"]         = "GPS Ready",
  ["NO CARRIER"]        = "No carrier",
  ["NO DIALTONE"]       = "No dialtone",
  ["NO ANSWER"]         = "No answer",
  ["NORMAL POWER DOWN"] = "Power off",
}

-- URC with args
local tt = {
  [ "+CRING" ] = true;
  [ "+CLIP"  ] = true;
  [ "+CMT"   ] = true;
  [ "+CMTI"  ] = true;
  [ "+CDS"   ] = true;
  [ "+CDSI"  ] = true;
  [ "+CBM"   ] = true;
}

-- This can be URC or Response to command
local ttt = {
  [ "+CPIN" ] = true;
  [ "+CFUN" ] = true;
}

is_async_msg = function(line)
  local info, typ = t[line]
  if info then return line, info end

  typ, info = string.match(line, "^(%+[^:]+):%s*(.-)%s*$")

  if typ then
    if tt[typ]  then return typ, info, false end
    if ttt[typ] then return typ, info, true  end
  end
end

end

local is_final_msg do

local t = {
  OK                      = "Success",
  ERROR                   = "Error",
  ["COMMAND NOT SUPPORT"] = "Command is not supported",
  ["TOO MANY PARAMETERS"] = "Too many parameters",
}

is_final_msg = function (line)
  local info = t[line]
  if info then return line, info end

  info = line:match('^%+CME ERROR:%s*(.-)%s*$')
  if info then return "+CME ERROR", info end

  info = line:match('^%+CMS ERROR:%s*(.-)%s*$')
  if info then return "+CMS ERROR", info end
end

end

local trim = function(data)
  return data:match('^%s*(.-)%s*$')
end

local unquot = function(data)
  return (trim(data):match('^"?(.-)"?$'))
end

local PROMPT_I  = 0
local CMD_I     = 1
local TIMEOUT_I = 2
local CB_I      = 3
local CHAIN_I   = 4
local RES_I     = 5

---------------------------------------------------------------
local ATStream = ut.class() do

local STATE_NONE          = 0
local STATE_WAIT_URC_DATA = 1

function ATStream:__init(_self, logger)
  self._self           = _self or self
  self._eol            = '\r\n'
  self._active_queue   = ut.Queue.new()
  self._command_queue  = ut.List.new()
  self._buffer         = ut.Buffer.new(self._eol)
  self._state          = {STATE_NONE}
  self._logger         = logger or DummyLogger

  -- we can get final response (OK/ERROR) only after empty line
  -- all responses is ...<EOL><EOL>[RESPONSE]<EOL>
  self._has_empty_line = false

  return self
end

function ATStream:append(data)
  self._buffer:append(data)
  return self
end

--- Register handler to write to serial port.
--
function ATStream:on_command(handler)
  self._on_command = handler
  return self
end

--- Register handler that make delay before send next command.
--
function ATStream:on_delay(handler)
  self._on_delay = handler
  return self
end

--- Register handler to handle command execute done.
--
-- You can start timer in `on_command` handler and stop it here
--
function ATStream:on_done(handler)
  self._on_done = handler
  return self
end

-- Register handler for URC messages.
--
function ATStream:on_message(handler)
  self._on_message = handler
  return self
end

-- Register handler for URC candidate messages.
--
function ATStream:on_maybe_message(handler)
  self._on_maybe_message = handler
  return self
end

-- Register handler for unexpected responses.
--
-- This can be
--  * URC that library can not handle
--  * Bug in Library
--  * Bug in device
function ATStream:on_unexpected(handler)
  self._on_unexpected = handler
  return self
end

function ATStream:_emit_command(...)
  if self._on_command then
    self._on_command(self._self, ...)
  end
  return self
end

function ATStream:_emit_done(...)
  if self._on_done then
    self._on_done(self._self, ...)
  end
  return self
end

function ATStream:_emit_unexpected(...)
  if self._on_unexpected then
    self._on_unexpected(self._self, ...)
  end
  return self
end

function ATStream:_emit_message(...)
  if self._on_message then
    self._on_message(self._self, ...)
  end
  return self
end

function ATStream:_emit_maybe_message(typ, info)
  if typ == true then
    if self._state.maybe_urc_typ then
      typ, info = self._state.maybe_urc_typ, self._state.maybe_urc_info
      self._state.maybe_urc_typ, self._state.maybe_urc_info = nil -- luacheck: ignore 532
      if self._on_maybe_message then
        self._on_maybe_message(self._self, typ, info, false)
      end
      self:_emit_message(typ, info)
      return true
    end
  elseif typ == false then
    if self._state.maybe_urc_typ then
      self._state.maybe_urc_typ, self._state.maybe_urc_info = nil -- luacheck: ignore 532
      if self._on_maybe_message then
        self._on_maybe_message(self._self)
      end
      return true
    end
  else
    self._state.maybe_urc_typ, self._state.maybe_urc_info = typ, info
    if self._on_maybe_message then
      self._on_maybe_message(self._self, typ, info, true)
    end
  end
end

function ATStream:_read_line()
  local data = self._buffer:read_line("\r")
  if not data then return end
  return trim(data)
end

function ATStream:_read_prompt()
  if not self._has_empty_line then return end

  local t = self._active_queue:peek()
  if not(t and t[PROMPT_I]) then return end

  local prompt = t[PROMPT_I][1]

  while true do
    local ch = self._buffer:read_n(1)
    if not ch then return end
    if ch == prompt then return ch end
    if ch ~= '\n' then
      self._buffer:prepend(ch)
      return
    end
  end
end

function ATStream:_command_done(status, info)
  local t = self._active_queue:pop()
  self:_emit_done()

  if not t[CHAIN_I] then self:_command() end

  if t[CB_I] then
    local msg = t[RES_I] and table.concat(t[RES_I],'\n') or ''
    t[CB_I](self._self, nil, t[CMD_I], msg, status, info)
  end

  if t[CHAIN_I] then self:_command() end
end

local function execute_step(self, line)
  self._has_empty_line = (#line == 0)
  if self._has_empty_line then
    return
  end

  if self._state[1] == STATE_WAIT_URC_DATA then
    local typ, info = self._state.typ, self._state.info
    self._state[1], self._state.typ, self._state.info = STATE_NONE -- luacheck: ignore 532
    return self:_emit_message(typ, info, line)
  end

  local urc_typ, urc_info, maybe_urc = is_async_msg(line)

  if urc_typ and (not maybe_urc) then
      -- in text mode CDS can be
      --  * '+CDS: 6,46,"+77777777777", ... \r\n'
      --  * '+CDS: \r\n 6,46,"+77777777777", ... \r\n'
      -- in PDU mode it can be only '+CDS 25\r\n<PDU>\r\n'
    if (urc_typ == '+CMT') or (
      urc_typ == '+CDS' and (tonumber(urc_info) or #urc_info == 0)
    ) then
      self._state[1]   = STATE_WAIT_URC_DATA
      self._state.typ  = urc_typ
      self._state.info = urc_info
    else
      self:_emit_message(urc_typ, urc_info)
    end
    return
  end

  local t = self._active_queue:peek()
  if t then

    -- We have to check command first. E.g we send command `ate0`.
    -- and we read from port `+CFUN: 1<EOL>OK<EOL>`.
    -- We can not determinte that this is URC + OK instead off
    -- response to AT+CFUN=?. At least without echo I think.
    if maybe_urc then
      local cmd = ut.split_first(t[CMD_I], '[=?]')
      if string.upper(cmd) ~= ('AT' .. string.upper(urc_typ)) then
        self:_emit_message(urc_typ, urc_info)
        return
      end
    end

    local status, info = is_final_msg(line)

    if status then -- command done
      self:_emit_maybe_message(false)
      return self:_command_done(status, info)
    end

    -- Assume URC can be only single line like +CFUN: ....
    -- So if preview line was maybe_urc then this was URC message
    if self:_emit_maybe_message(true) then
      -- that means that preview read line mark as mabe URC and that means it was URC
      -- so we have to remove this line from result.
      -- Output from port e.g. `+CFUN: 1<EOL>+CFUN: 1<EOL>+CFUN: 1<EOL>OK<EOL>`
      -- Resultset have to be exists alread

      local r = assert(t[RES_I])
      assert(r[#r])
      r[#r] = nil
    end

    local prompt = t[PROMPT_I]
    if prompt and prompt[1] == line then
      t[PROMPT_I] = nil
      return self:_emit_command(prompt[2], prompt[3])
    end

    if maybe_urc then
      -- this can be if we get `maybe URC` as first before response to same command
      -- e.g. we send `AT+CFUN=1` and read from port `+CFUN: 1<EOL>+CFUN: 1<EOL>OK<EOL>`
      -- When we read `+CFUN: 1` we can not be sure is it URC or not so just mark it
      -- as suspisios
      self:_emit_maybe_message(urc_typ, urc_info)
    end

    local r = t[RES_I] or {}
    r[#r + 1] = line
    t[RES_I] = r

    return
  end

  if maybe_urc then
    self:_emit_message(urc_typ, urc_info)
    return
  end

  self:_emit_unexpected(line)
end

function ATStream:execute()
  while true do
    local line = self:_read_line() or self:_read_prompt()
    if not line then break end

    execute_step(self, line)
  end

  return self
end

function ATStream:_busy()
  return self._active_queue:size() ~= 0
end

function ATStream:_command(front, t)
  if t then
    if front then
      self._command_queue:push_front(t)
    else
      self._command_queue:push_back(t)
    end
  end

  if self._on_delay then
    if not self:_busy() then
      self._on_delay(self._self)
    end
    return
  end

  return self:next_command()
end

function ATStream:_command_impl(front, chain, ...)
  local cb, cmd, timeout = pack_args(...)

  local t = cmd and {cmd, timeout, cb, chain}

  return self:_command(front, t)
end

function ATStream:_command_ex_impl(front, chain, ...)
  local cb, cmd, timeout1, prompt, timeout2, data = pack_args(...)

  if timeout1 and type(timeout1) ~= 'number' then
    timeout1, prompt, timeout2, data = nil, timeout1, prompt, timeout2
  end

  if timeout2 and type(timeout2) ~= 'number' then
    timeout2, data = nil, timeout2
  end

  local t = cmd and {cmd, timeout1, cb, chain,
    [PROMPT_I] = {prompt, data, timeout2}
  }

  return self:_command(front, t)
end

function ATStream:command(...)
  return self:_command_impl(false, false, ...)
end

function ATStream:command_ex(...)
  return self:_command_ex_impl(false, false, ...)
end

function ATStream:next_command()
  if not self:_busy() then
    local t = self._command_queue:pop_front()
    if t then
      self:_emit_command(t[CMD_I] .. self._eol, t[TIMEOUT_I])
      self._active_queue:push(t)
    end
  end
end

function ATStream:reset(err)
  while true do
    local task = self._active_queue:pop()
    if not task then break end
    task[CB_I](self._self, err, task[CMD_I])
  end

  while true do
    local task = self._command_queue:pop_front()
    if not task then break end
    task[CB_I](self._self, err, task[CMD_I])
  end

  self._buffer:reset()
  self._has_empty_line = false

  return
end

end
---------------------------------------------------------------

local function Decode_CMT_text(typ, msg, text)
  local args = split_args(msg)

  local number, alpha, scts = unpack(args)  -- luacheck: ignore alpha
  return typ, true, text, number, scts
end

local function Decode_CDS_text(typ, msg, text)
  local args = split_args(text or msg)
  local ref, number, status = args[2], args[3], args[#args]
  ref, status = tonumber(ref), tonumber(status)

  return typ, true, ref, status, number
end

local function Decode_CMT_CDS_pdu(typ, msg, pdu)
  local alpha, len = ut.split_first(msg, ',', true)
  if not len then len, alpha = alpha, '' end
  alpha, len = unquot(alpha), tonumber(len)
  return typ, false, pdu, len, alpha
end

local function Decode_URC(mode, ...)
  local typ, msg, info = ...
  if typ == '+CMTI' or typ == "+CDSI" then
    local mem, n = ut.usplit(msg, ',', true)
    mem, n = unquot(mem), tonumber(n)
    return typ, n, mem
  end

  if typ == '+CDS' and #msg == 0 then
    msg, info = info or msg -- luacheck: ignore 532 info
  end

  if typ == '+CMT' or typ == '+CDS' then
    if mode == nil then -- Guess mode by content
      local args = split_args(msg)
      mode = (#args >= 3) -- text mode
    end

    if mode then
      if typ == '+CMT' then return Decode_CMT_text(...) end
      return Decode_CDS_text(...)
    end

    return Decode_CMT_CDS_pdu(...)
  end

  if typ == '+CLIP' then
    local ani, ton, _unknow_, valid, alpha = ut.usplit(msg, ',', true)
    ani      = unquot(ani)
    ton      = tonumber(ton)
    valid    = tonumber(valid)
    _unknow_ = unquot(_unknow_)
    alpha    = unquot(alpha)
    return typ, ani, ton, _unknow_, valid, alpha
  end

  return ...
end

---------------------------------------------------------------
local ATCommander = ut.class() do

local MESSAGE_STATUS = {
  ['REC UNREAD'] = 0,
  ['REC READ']   = 1,
  ['STO UNSENT'] = 2,
  ['STO SENT']   = 3,
}

local E = Error

function ATCommander:__init(stream, front, chain)
  self._stream = stream
  self._front  = front
  self._chain  = chain
  return self
end

function ATCommander:mode(front, chain)
  self._front  = front
  self._chain  = chain
  return self
end

local function remove_echo(res, cmd)
  if #res == 0 or res:sub(1,1) == '+' then
    return res
  end

  local echo, tail = ut.split_first(res, '\n')
  if cmd:upper() == echo then
    return tail or '', echo
  end

  return res
end

function ATCommander:_basic_cmd(...)
  local cb, cmd, timeout = pack_args(...)

  -- luacheck: push ignore 431
  self._stream:_command_impl(self._front, self._chain, cmd, timeout, function(this, err, cmd, res, status, info)
    if err then return cb(this, err) end

    if status ~= 'OK' then
      info = (status == 'ERROR') and (info == 'Error') and cmd or info
      return cb(this, E(status, info))
    end

    res = remove_echo(res, cmd)

    cb(this, nil, #res == 0 and status or res)
  end)
  -- luacheck: pop

  return true
end

function ATCommander:_basic_cmd_ex(...)
  local cb, cmd, timeout1, prompt, timeout2, data = pack_args(...)

  if timeout1 and type(timeout1) ~= 'number' then
    timeout1, prompt, timeout2, data = nil, timeout1, prompt, timeout2
  end

  if timeout2 and type(timeout2) ~= 'number' then
    timeout2, data = nil, timeout2
  end

  self._stream:_command_ex_impl(self._front, self._chain, cmd, timeout1, prompt, timeout2, data,
  function(this, err, cmd, res, status, info) -- luacheck: ignore cmd
    if err then return cb(this, err) end

    if status ~= 'OK' then
      info = (status == 'ERROR') and (info == 'Error') and cmd or info
      return cb(this, E(status, info))
    end

    res = remove_echo(res, cmd)

    cb(this, nil, #res == 0 and status or res)
  end)

  return true
end

function ATCommander:chain(t)
  local i = 1

  local function cont()
    local f = t[i]
    i = i + 1
    if f then f(self:mode(i > 2 or self._front, true), cont) end
  end

  cont()

  return self
end

function ATCommander:ATZ(...)
  return self:_basic_cmd('ATZ', ...)
end

function ATCommander:Echo(mode, ...)
  local cmd = string.format("ATE%d", mode and 1 or 0)
  return self:_basic_cmd(cmd, ...)
end

function ATCommander:OperatorName(...)
  local cb, timeout = pack_args(...)
  return self:_basic_cmd('AT+COPS?', timeout, function(this, err, info)
    if err then return cb(this, err, info) end

    local str = info:match("^%+COPS: (.+)$")
    if not str then return cb(this, E('EPROTO', nil, info)) end

    str = split_args(str)
    str = str and str[3]

    -- SIM is not init
    if not str then return cb(this, nil, nil) end

    cb(this, nil, str)
  end)
end

function ATCommander:ModelName(...)
  return self:_basic_cmd('AT+GMM', ...)
end

function ATCommander:ManufacturerName(...)
  return self:_basic_cmd('AT+CGMI', ...)
end

function ATCommander:RevisionVersion(...)
  return self:_basic_cmd('AT+CGMR', ...)
end

function ATCommander:MemoryStatus(...)
  -- mem1 - to read and write (cmgr/cmgl)
  -- mem2 - to write and send (cmgw/cmss)
  -- mem3 - to store new sms  (cmti/cdsi)
  --
  -- SM - SIM memory
  -- ME - Device memory
  -- MT - SIM+Device memory

  local cb, timeout = pack_args(...)
  return self:_basic_cmd('AT+CPMS?', timeout, function(this, err, info)
    if err then return cb(this, err, info) end

    local str = info:match("^%+CPMS: (.+)$")
    if not str then return cb(this, E('EPROTO', nil, info)) end

    str = split_args(str)
    if not str then return cb(this, E('EPROTO', nil, info)) end

    local mem1 = str[1] and #str[1] > 0 and {str[1], tonumber(str[2]), tonumber(str[3])} or nil
    local mem2 = str[1] and #str[1] > 0 and {str[4], tonumber(str[5]), tonumber(str[6])} or nil
    local mem3 = str[1] and #str[1] > 0 and {str[7], tonumber(str[8]), tonumber(str[9])} or nil

    cb(this, nil, mem1, mem2, mem3)
  end)
end

function ATCommander:SetSmsMemory(...)
  -- luacheck: push ignore 532
  local cb, mem1, mem2, mem3, timeout = pack_args(...)
  if type(mem3) == 'number' then timeout, mem3 = mem3
  elseif type(mem2) == 'number' then timeout, mem3, mem2 = mem2 end
  -- luacheck: pop

  local cmd
  if mem3 then     cmd = string.format('AT+CPMS="%s","%s","%s"', mem1, mem2, mem3)
  elseif mem2 then cmd = string.format('AT+CPMS="%s","%s"', mem1, mem2)
  else             cmd = string.format('AT+CPMS="%s"', mem1) end

  return self:_basic_cmd(cmd, timeout, function(this, err, info)
    if err then return cb(this, err, info) end

    local str = info:match("^%+CPMS: (.+)$")
    if not str then return cb(this, E('EPROTO', nil, info)) end

    str = split_args(str)
    if not str then return cb(this, E('EPROTO', nil, info)) end

    for i = 1, #str do str[i] = tonumber(str[i]) end

    cb(this, nil, unpack(str, 1, 6))
  end)
end

function ATCommander:IMEI(...)
  return self:_basic_cmd('AT+GSN', ...)
end

function ATCommander:IMSI(...)
  return self:_basic_cmd('AT+CIMI', ...)
end

function ATCommander:ErrorMode(mode, ...)
  -- 0 - 'ERROR'
  -- 1 - '+CME ERROR: 772'
  -- 2 - '+CME ERROR: SIM powered down'
  -------------------------------------------------
  local cmd = string.format('AT+CMEE=%d', mode)
  return self:_basic_cmd(cmd, ...)
end

function ATCommander:Charsets(...)
  local cb = pack_args(...)
  return self:_basic_cmd('AT+CSCS=?', function(this, err, info)
    if err then return cb(this, err, info) end

    local msg = info:match("%+CSCS:%s*(.-)%s*$")
    if not msg then return cb(this, E('EPROTO', nil, info)) end

    if not msg:match('^%b()$') then
      return cb(this, E('EPROTO', nil, info))
    end

    cb(this, nil, split_args(msg:sub(2, -2)))
  end)
end

function ATCommander:Charset(...)
  local cb, cp = pack_args(...)
  local cmd = cp and string.format('AT+CSCS="%s"', cp) or 'AT+CSCS?'
  return self:_basic_cmd(cmd, function(this, err, info)
    if err then return cb(this, err, info) end
    if not cp then
      local msg = info:match("%+CSCS:%s*(.-)%s*$")
      if not msg then return cb(this, E('EPROTO', nil, info)) end
      info = unquot(msg)
    end

    cb(this, nil, info)
  end)
end

function ATCommander:SimReady(...)
  local cb, timeout = pack_args(...)
  return self:_basic_cmd('AT+CPIN?', timeout, function(this, err, info)
    if err then return cb(this, err, info) end

    local code = info:match("^%+CPIN:%s*(.-)%s*$")
    cb(this, nil, code or info)
  end)
end

function ATCommander:SmsTextMode(...)
  local cb, mode, timeout = pack_args(...)
  if type(mode) == 'number' then
    timeout, mode = mode -- luacheck: ignore 532
  end

  if mode == nil then
    self:_basic_cmd('AT+CMGF?', timeout, function(this, err, info)
      if err then return cb(this, err, info) end

      local code = info:match("^%+CMGF:%s*(%d+)%s*$")
      if not code then return cb(this, E('EPROTO', nil, info)) end

      cb(this, nil, tonumber(code) == 1)
    end)
  else
    local cmd = string.format("AT+CMGF=%d", mode and 1 or 0)
    self:_basic_cmd(cmd, timeout, function(this, err, info)
      if err then return cb(this, err, info) end

      cb(this, nil, mode)
    end)
  end
  return self
end

function ATCommander:CNMI(...)
  local cb, mode, mt, bm, ds, bfr = pack_args(...)
  local cmd = string.format("AT+CNMI=%d,%d,%d,%d,%d", mode or 0, mt or 0, bm or 0, ds or 0, bfr or 0)
  return self:_basic_cmd(cmd, cb)
end

function ATCommander:CLIP(mode, ...)
  local cmd = string.format("AT+CLIP=%d", mode)
  return self:_basic_cmd(cmd, ...)
end

function ATCommander:CMGF(fmt, ...)
  -- 0 - PDU
  -- 1 - Text
  local cmd = string.format("AT+CMGF=%d", fmt)
  return self:_basic_cmd(cmd, ...)
end

-- Read SMS
function ATCommander:CMGR(i, ...)
  -- stat
  --  0 - received unread
  --  1 - received read
  --  2 - stored unsent
  --  3 - stored sent
  -- alpha
  --  Name from phone book
  -- len
  --   PDU length in chars (without SMSC)
  local cmd = string.format("AT+CMGR=%d", i)
  local cb, timeout = pack_args(...)

  return self:_basic_cmd(cmd, timeout, function(this, err, info)
    if err then return cb(this, err, info) end

    -- no SMS
    if info == 'OK' then return cb(this, nil, nil) end
    local data, pdu = info:match("^%+CMGR:%s*(.-)%s-\n(.-)\r?\n?$")
    if not data then return cb(this, E('EPROTO', nil, info)) end

    data = split_args(data)
    if not data then return cb(this, E('EPROTO', nil, info)) end

    -- Text mode
    if MESSAGE_STATUS[ data[1] ] then
      --! @todo decode Text mode sms
      -- luacheck: push ignore 631
      -- message_status,address,[address_text],service_center_time_stamp[,address_type,TPDU_first_octet,protocol_identifier,data_coding_scheme,service_center_address,service_center_address_type,sms_message_body_length]<CR><LF>sms_message_body
      -- luacheck: pop

      local stat, address, scts = data[1], data[2]
      if stat:sub(1, 3) == 'REC' then
        if #data <= 3 then scts = data[3] else scts = data[4] end
      end

      return cb(this, nil, pdu, stat, address, scts)
    end

    -- PDU Mode
    local index, stat, alpha, len -- luacheck: ignore index
    if #data >= 4 then index, stat, alpha, len = unpack(data)
    elseif #data == 3 then stat, alpha, len = unpack(data)
    elseif #data == 2 then stat, len = unpack(data)
    elseif #data == 1 then len = unpack(data) end

    if (not tonumber(len)) or (stat and not tonumber(stat)) then
      return cb(this, E('EPROTO', nil, info))
    end

    stat, len = tonumber(stat), tonumber(len)

    --! @check pass `index` value
    cb(this, nil, pdu, stat, len, alpha)
  end)
end

-- Delete SMS
function ATCommander:CMGD(i, ...)
  local cmd = string.format("AT+CMGD=%d", i)
  return self:_basic_cmd(cmd, ...)
end

-- Send SMS
function ATCommander:CMGS(len, pdu, cb)
  local cmd
  if type(len) == 'number' then -- PDU mode
    cmd = string.format("AT+CMGS=%d", len)
  else -- Text mode
    cmd = string.format('AT+CMGS="%s"', len)
  end
  cb = cb or dummy
  return self:_basic_cmd_ex(cmd, 5000, '>', 70000, pdu .. '\26', function(this, err, info)
    if err then return cb(this, err, info) end

    -- Text mode: message_reference[,service_center_time_stamp]
    -- PDU  mode: message_reference[,SMS-SUBMIT-REPORT_TPDU]

    local data = info:match("%+CMGS:%s*(.-)%s-$")
    if not data then return cb(this, E('EPROTO', nil, info)) end

    data = split_args(data)
    if not data then return cb(this, E('EPROTO', nil, info)) end

    local ref = tonumber(data[1])
    if not ref then return cb(this, E('EPROTO', nil, info)) end

    cb(this, nil, ref, data[2])
  end)
end

-- List SMS
function ATCommander:CMGL(...)
  -- stat
  --  0 - received unread
  --  1 - received read
  --  2 - stored unsent
  --  3 - stored sent
  --  4 - ANY

  -- on my modem I get trancated pdu for long sms (len = 160)
  -- Response looks like `+CMGL: 5,1,,160\r\n<TRANCATED PDU>+CMGL: 6,1,,88\r\n<PDU>`
  -- Note there no EOL after trancated pdu. So this method just return trancated PDU.

  local cb, stat, timeout = pack_args(...)
  stat = stat or 4

  assert(type(stat) == 'number', 'Support only PDU mode')

  local cmd = string.format("AT+CMGL=%d", stat)

  return self:_basic_cmd(cmd, timeout, function(this, err, info)
    if err then return cb(this, err, info) end

    -- no SMS
    if info == 'OK' then return cb(this, nil, nil) end

    local res = {}

    for opt, pdu in info:gmatch("%+CMGL:%s*(.-)%s-\n(%x*)") do

      local args = split_args(opt)
      if not args then
        return cb(this, Error('EPROTO', nil, info))
      end

      local index, stat, alpha, len = unpack(args) -- luacheck: ignore stat
      index, stat, len = tonumber(index), tonumber(stat), tonumber(len)

      if (not index) or (not len) or (not stat) then
        return cb(this, E('EPROTO', nil, info))
      end

      res[#res + 1] = {index, pdu, stat, len, alpha}
    end

    cb(this, nil, res)
  end)
end

-- Send USSD request
function ATCommander:CUSD(...)
  local cb, n, cmd, codec = pack_args(...)
  if type(n) == 'string' then
    n, cmd, codec = 1, n, cmd
  elseif type(n) == 'boolen' then
    n = n and 1 or 0
  elseif n == nil then n = 1 end

  cmd = string.format('AT+CUSD=%d,"%s",%d', n, cmd, codec or 15)
  cb = cb or dummy
  return self:_basic_cmd(cmd, function(this, err, info)
    if err then return cb(this, err, info) end

    local msg = info:match("%+CUSD:%s*(.-)%s*$")
    if not msg then return cb(this, E('EPROTO', nil, info)) end

    local data, m, dcs = split_args(msg) -- luacheck: ignore 311
    if not data then
      -- some modems returns UCS2 directly so it really fail to split
      m, msg, dcs = msg:match('^(%d-),"(.-)",(%d+)$')
      if not m then return cb(this, E('EPROTO', nil, info)) end
    else
      m, msg, dcs = unpack(data)
    end

    m, dcs = tonumber(m), tonumber(dcs)

    cb(this, nil, m, msg, dcs)
  end)
end

function ATCommander:raw(...)
  return self:_basic_cmd(...)
end

function ATCommander:at(...)
  local cb, cmd, timeout = pack_args(...)
  if type(cmd) == 'number' then
    timeout, cmd = cmd -- luacheck: ignore 532
  end

  cmd = 'AT' .. (cmd or '')

  return self:_basic_cmd(cmd, timeout, cb)
end

function ATCommander:on_urc(fn)
  if not fn then self._stream:on_message() else
    self._stream:on_message(function(this, ...)
      return fn(this, Decode_URC(nil, ...))
    end)
  end
end

end
---------------------------------------------------------------

return {
  Stream    = ATStream.new;
  Commander = ATCommander.new;
  DecodeUrc = Decode_URC;
}
