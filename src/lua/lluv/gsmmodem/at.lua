local uv     = require "lluv"
local ut     = require "lluv.utils"
local Error  = require "lluv.gsmmodem.error".error
local utils  = require "lluv.gsmmodem.utils"

local unpack = unpack or table.unpack

local pack_args   = utils.pack_args
local split_args  = utils.split_args
local split_list  = utils.split_list
local decode_list = utils.decode_list

local function dummy()end

local is_async_msg do

local t = {
  RING            = "Ringing",
  BUSY            = "Busy",
  ["NO CARRIER"]  = "No carrier",
  ["NO DIALTONE"] = "No dialtone",
  ["NO ANSWER"]   = "No answer",
}

is_async_msg = function(line)
  local info = t[line]
  if info then return line, info end

  info = line:match('^%+CLIP:%s*(.-)%s*$')
  if info then return "+CLIP", info end

  info = line:match('^%+CMT:%s*(.-)%s*$')
  if info then return "+CMT", info end

  info = line:match('^%+CMTI:%s*(.-)%s*$')
  if info then return "+CMTI", info end

  info = line:match('^%+CDS:%s*(.-)%s*$')
  if info then return "+CDS", info end

  info = line:match('^%+CDSI:%s*(.-)%s*$')
  if info then return "+CDSI", info end
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
  if info then return "+CMS ERROR", err end
end

end

local trim = function(data)
  return data:match('^%s*(.-)%s*$')
end

local unquot = function(data)
  return (trim(data):match('^"?(.-)"?$'))
end

local UD_I      = 0
local CMD_I     = 1
local TIMEOUT_I = 2
local CB_I      = 3
local RES_I     = 4

---------------------------------------------------------------
local ATStream = ut.class() do

local STATE_NONE          = 0
local STATE_WAIT_URC_DATA = 1

function ATStream:__init(_self)
  self._self           = _self or self
  self._eol            = '\r\n'
  self._active_queue   = ut.Queue.new()
  self._command_queue  = ut.List.new()
  self._buffer         = ut.Buffer.new(self._eol)
  self._state          = {STATE_NONE}

  -- we can get final response (OK/ERROR) only after empty line
  -- all responses is ...<EOL><EOL>[RESPONSE]<EOL>
  self._has_empty_line = false

  return self
end

function ATStream:append(data)
  self._buffer:append(data)
  return self
end

function ATStream:on_command(handler)
  self._on_command = handler
  return self
end

function ATStream:on_delay(handler)
  self._on_delay = handler
  return self
end

function ATStream:on_done(handler)
  self._on_done = handler
  return self
end

function ATStream:on_message(handler)
  self._on_message = handler
  return self
end

function ATStream:on_message_(...)
  if self._on_message then
    self._on_message(self._self, ...)
  end
  return self
end

function ATStream:_read_line()
  local data = self._buffer:read_line("\r")
  if not data then return end
  return trim(data)
end

function ATStream:_read_prompt()
  if not self._has_empty_line then return end

  local t = self._active_queue:peek()
  if not(t and t[UD_I]) then return end

  local prompt = t[UD_I][1]

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
  if self._on_done then self:_on_done() end
  self:command() -- proceed next command
  local msg = t[RES_I] and table.concat(t[RES_I],'\n') or ''
  if t[CB_I] then t[CB_I](self._self, err, t[CMD_I], msg, status, info) end
end

local function execute_step(self, line)
  if #line == 0 then
    self._has_empty_line = true
    return
  end

  if self._state[1] == STATE_WAIT_URC_DATA then
    local typ, info = self._state.typ, self._state.info
    self._state[1], self._state.typ, self._state.info = STATE_NONE
    return self:on_message_(typ, info, line)
  end

  local urc_typ, urc_info = is_async_msg(line)
  if urc_typ then
    if urc_typ == '+CMT' or urc_typ == '+CDS' then
      self._state[1]   = STATE_WAIT_URC_DATA
      self._state.typ  = urc_typ
      self._state.info = urc_info
    else
      self:on_message_(urc_typ, urc_info)
    end
    return
  end

  local t = self._active_queue:peek()
  if t then
    local status, info = is_final_msg(line)

    if status then -- command done
      return self:_command_done(status, info)
    end

    local prompt = t[UD_I]
    if prompt and prompt[1] == line then
      t[UD_I] = nil
      return self:_on_command(prompt[2], prompt[3])
    end

    local r = t[RES_I] or {}
    r[#r + 1] = line
    t[RES_I] = r

    return
  end

  if self._unexpected then
    self:_unexpected(line)
  end
end

function ATStream:execute()
  while true do
    local line = self:_read_line() or self:_read_prompt()
    if not line then break end

    execute_step(self, line)
  end

  return self
end

function ATStream:_command(push, t)
  if t then push(self._command_queue, t) end

  if self._on_delay then
    return self:_on_delay()
  end

  return self:next_command()
end

function ATStream:command(...)
  local cb, cmd, timeout = pack_args(...)

  local t = cmd and {cmd, timeout, cb}

  return self:_command(
    self._command_queue.push_back, t
  )
end

function ATStream:command_ex(...)
  local cb, cmd, timeout1, prompt, timeout2, data = pack_args(...)

  if timeout1 and type(timeout1) ~= 'number' then
    timeout1, prompt, timeout2, data = nil, timeout1, prompt, timeout2
  end

  if timeout2 and type(timeout2) ~= 'number' then
    timeout2, data = nil, timeout2
  end

  local t = cmd and {cmd, timeout1, cb,
    [UD_I] = {prompt, data, timeout2}
  }

  return self:_command(
    self._command_queue.push_back, t
  )
end

function ATStream:next_command()
  if self._active_queue:size() == 0 then
    local t = self._command_queue:pop_front()
    if t then
      self:_on_command(t[CMD_I] .. self._eol, t[TIMEOUT_I])
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

local function Decode_URC(...)
  local typ, msg, info = ...
  if typ == '+CMTI' or typ == "+CDSI" then
    local mem, n = ut.usplit(msg, ',', true)
    mem, n = unquot(mem), tonumber(n)
    return typ, mem, n
  end

  if typ == '+CMT' or typ == '+CDS' then
    local alpha, len = ut.split_first(msg, ',', true)
    if not len then len, alpha = alpha, '' end
    alpha, len = unquot(alpha), tonumber(len)
    return typ, info, len, alpha
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

function ATCommander:__init(stream)
  self._stream = stream
  return self
end

local function remove_echo(res)
  if #res > 0 and res:sub(1,1) ~= '+' then
    local echo, tail = ut.split_first(res, '\n')
    return tail or '', echo
  end
  return res
end

function ATCommander:_basic_cmd(...)
  local cb, cmd, timeout = pack_args(...)

  self._stream:command(cmd, timeout, function(this, err, cmd, res, status, info)
    if err then return cb(this, err) end
    if status ~= 'OK' then return cb(this, E(status, info)) end

    res = remove_echo(res)

    cb(this, nil, #res == 0 and status or res)
  end)

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

  self._stream:command_ex(cmd, timeout1, prompt, timeout2, data, function(this, err, cmd, res, status, info)
    if err then return cb(this, err) end
    if status ~= 'OK' then return cb(this, E(status, info)) end
    res = remove_echo(res)

    cb(this, nil, #res == 0 and status or res)
  end)

  return true
end

function ATCommander:ATZ(cb)
  return self:_basic_cmd('ATZ', cb)
end

function ATCommander:OperatorName(cb)
  cb = cb or dummy
  return self:_basic_cmd('AT+COPS?', function(this, err, info)
    if err then return cb(this, err, info) end

    local str = info:match("^%+COPS: (.+)$")
    if not str then return cb(this, E('EPROTO', nil, res)) end

    str = split_args(str)
    str = str and str[3]

    -- SIM is not init
    if not str then return cb(this, nil, nil) end

    cb(this, nil, str)
  end)
end

function ATCommander:ModelName(cb)
  return self:_basic_cmd('AT+GMM', cb)
end

function ATCommander:ManufacturerName(cb)
  return self:_basic_cmd('AT+CGMI', cb)
end

function ATCommander:RevisionVersion(cb)
  return self:_basic_cmd('AT+CGMR', cb)
end

function ATCommander:IMEI(cb)
  return self:_basic_cmd('AT+GSN', cb)
end

function ATCommander:IMSI(cb)
  return self:_basic_cmd('AT+CIMI', cb)
end

function ATCommander:ErrorMode(mode, cb)
  -- 0 - 'ERROR'
  -- 1 - '+CME ERROR: 772'
  -- 2 - '+CME ERROR: SIM powered down'
  -------------------------------------------------
  local cmd = string.format('AT+CMEE=%d', mode)
  return self:_basic_cmd(cmd, cb)
end

function ATCommander:SimReady(cb)
  cb = cb or dummy
  return self:_basic_cmd('AT+CPIN?', function(this, err, info)
    if err then return cb(this, err, info) end

    local code = info:match("^%+CPIN:%s*(.-)%s*$")
    cb(this, nil, code or info)
  end)
end

function ATCommander:CNMI(...)
  local cb, mode, mt, bm, ds, bfr = pack_args(...)
  local cmd = string.format("AT+CNMI=%d,%d,%d,%d,%d", mode or 0, mt or 0, bm or 0, ds or 0, bfr or 0)
  return self:_basic_cmd(cmd, cb)
end

function ATCommander:CLIP(mode, cb)
  local cmd = string.format("AT+CLIP=%d", mode)
  return self:_basic_cmd(cmd, cb)
end

function ATCommander:CMGF(fmt, cb)
  -- 0 - PDU
  -- 1 - Text
  local cmd = string.format("AT+CMGF=%d", fmt)
  return self:_basic_cmd(cmd, cb)
end

-- Read SMS
function ATCommander:CMGR(i, cb)
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
  return self:_basic_cmd(cmd, function(this, err, info)
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
      -- message_status,address,[address_text],service_center_time_stamp[,address_type,TPDU_first_octet,protocol_identifier,data_coding_scheme,service_center_address,service_center_address_type,sms_message_body_length]<CR><LF>sms_message_body

      local stat, address, scts = data[1], data[2]
      if stat:sub(1, 3) == 'REC' then
        if #data <= 3 then scts = data[3] else scts = data[4] end
      end

      return cb(this, nil, pdu, stat, address, scts)
    end

    -- PDU Mode
    local index, stat, alpha, len
    if #data >= 4 then index, stat, alpha, len = unpack(data)
    elseif #data == 3 then stat, alpha, len = unpack(data)
    elseif #data == 2 then stat, len = unpack(data)
    elseif #data == 1 then len = unpack(data) end

    if (not tonumber(len)) or (stat and not tonumber(stat)) then
      return cb(this, E('EPROTO', nil, info))
    end

    stat, len = tonumber(stat), tonumber(len)

    cb(this, nil, pdu, stat, alpha, len)
  end)
end

-- Delete SMS
function ATCommander:CMGD(i, cb)
  local cmd = string.format("AT+CMGD=%d", i)
  return self:_basic_cmd(cmd, cb)
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

    ref = tonumber(data[1])
    if not ref then return cb(this, E('EPROTO', nil, info)) end

    cb(this, nil, ref, data[2])
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

  cmd = string.format('AT+CUSD=%d,"%s",%d', n, cmd, codc or 15)
  cb = cb or dummy
  return self:_basic_cmd(cmd, function(this, err, info)
    if err then return cb(this, err, info) end

    local msg = info:match("%+CUSD:%s*(.-)%s*$")
    if not msg then return cb(this, E('EPROTO', nil, info)) end

    local data = split_args(msg)
    if not data then return cb(this, E('EPROTO', nil, info)) end

    local m, msg, dcs = unpack(data)
    m, dcs = tonumber(m), tonumber(dcs)

    cb(this, nil, m, msg, dcs)
  end)
end

function ATCommander:raw(...)
  return self:_basic_cmd(...)
end

function ATCommander:at(...)
  local cb, cmd, timeout = pack_args(...)
  cmd = 'AT' .. (cmd or '')

  return self:_basic_cmd(cmd, timeout, cb)
end

function ATCommander:on_urc(fn)
  if not fn then self._stream:on_message() else
    self._stream:on_message(function(this, ...)
      return fn(this, Decode_URC(...))
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
