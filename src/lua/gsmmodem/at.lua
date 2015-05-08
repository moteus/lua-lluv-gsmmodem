local uv     = require "lluv"
local ut     = require "lluv.utils"
local Error  = require "gsmmodem.error".error
local ok, pp = pcall(require, "pp")
if not ok then pp = print end

local t = {
  RING            = "Ringing",
  BUSY            = "Busy",
  ["NO CARRIER"]  = "No carrier",
  ["NO DIALTONE"] = "No dialtone",
  ["NO ANSWER"]   = "No answer",
}

local function is_async_msg(line)
  if t[line] then return line, t[line] end

  local info = line:match('^%+CLIP:%s*(.-)%s*$')
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

local t = {
  OK                      = "Success",
  ERROR                   = "Error",
  ["COMMAND NOT SUPPORT"] = "Command is not supported",
  ["TOO MANY PARAMETERS"] = "Too many parameters",
}

local function is_final_msg(line)
  if t[line] then return line, t[line] end

  local err = line:match('^%+CME ERROR:%s*(.-)%s*$')
  if err then return "+CME ERROR", err end

  local err = line:match('^%+CMS ERROR:%s*(.-)%s*$')
  if err then return "+CMS ERROR", err end
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

function ATStream:__init(_self)
  self._self           = _self or self
  self._eol            = '\r\n'
  self._active_queue   = ut.Queue.new()
  self._command_queue  = ut.Queue.new()
  self._buffer         = ut.Buffer.new(self._eol)

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

function ATStream:execute()
  while true do
    local line = self:_read_line() or self:_read_prompt()
    if not line then return end

    if #line > 0 then
      if self._state == 'async_info' then
        self:on_message_(self._async_type, self._async_info, line)
        self._state, self._async_type, self._async_type = nil
      else
        local async, async_info = is_async_msg(line)
        if async then
          if async == '+CMT' or async == '+CDS' then
            self._async_type = async
            self._async_info = async_info
            self._state = 'async_info'
          else
            self:on_message_(async, async_info)
          end
        else
          local t = self._active_queue:peek()
          if t then

            local status, info = is_final_msg(line)

            if status then
              self:_command_done(status, info)
            else
              if t[UD_I] and t[UD_I][1] == line then
                self:_on_command(t[UD_I][2], t[UD_I][3])
                t[UD_I] = nil
              else
                local r = t[RES_I] or {}
                r[#r + 1] = line
                t[RES_I] = r
              end
            end

          else
            pp('unexpected message: ', line)
            -- assert(t, 'unexpected message: ', line)
          end
        end
      end
    end

    self._has_empty_line = (#line == 0)
  end
end

function ATStream:command(cmd, timeout, cb)
  if timeout and not cb then
    if type(timeout) == 'function' then
      cb, timeout = timeout
    end
  end

  if cmd then
    local t = {cmd, timeout, cb}
    self._command_queue:push(t)
  end

  if self._on_delay then
    return self:_on_delay()
  end

  return self:next_command()
end

function ATStream:command_ex(cmd, timeout1, prompt, timeout2, data, cb)
  if timeout1 and type(timeout1) ~= 'number' then
    timeout1, prompt, timeout2, data, cb = nil, timeout1, prompt, timeout2, data
  end

  if timeout2 and type(timeout2) ~= 'number' then
    timeout2, data, cb = nil, timeout2, data
  end

  if cmd then
    local t = {cmd, timeout1, cb,
      [UD_I] = {prompt, data, timeout2}
    }
    self._command_queue:push(t)
  end

  if self._on_delay then
    return self:_on_delay()
  end

  return self:next_command()
end

function ATStream:next_command()
  if self._active_queue:size() == 0 then
    local t = self._command_queue:pop()
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
    local task = self._command_queue:pop()
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

function ATCommander:_basic_cmd(cmd, timeout, cb)
  if timeout and not cb then
    if type(timeout) == 'function' then
      cb, timeout = timeout
    end
  end

  self._stream:command(cmd, timeout, function(this, err, cmd, res, status, info)
    if err then return cb(this, err) end
    if status ~= 'OK' then return cb(this, E(status, info)) end

    res = remove_echo(res)

    cb(this, nil, #res == 0 and status or res)
  end)
end

function ATCommander:_basic_cmd_ex(cmd, timeout1, prompt, timeout2, data, cb)
  if timeout1 and type(timeout1) ~= 'number' then
    timeout1, prompt, timeout2, data, cb = nil, timeout1, prompt, timeout2, data
  end

  if timeout2 and type(timeout2) ~= 'number' then
    timeout2, data, cb = nil, timeout2, data
  end

  self._stream:command_ex(cmd, timeout1, prompt, timeout2, data, function(this, err, cmd, res, status, info)
    if err then return cb(this, err) end
    if status ~= 'OK' then return cb(this, E(status, info)) end
    res = remove_echo(res)

    cb(this, nil, #res == 0 and status or res)
  end)
end

function ATCommander:ATZ(cb)
  return self:_basic_cmd('ATZ', cb)
end

function ATCommander:OperatorName(cb)
  return self:_basic_cmd('AT+COPS?', function(this, err, info)
    if err then return cb(this, err, info) end

    local str = info:match("^%+COPS: (.+)$")
    if not str then return cb(this, E('EPROTO', nil, res)) end

    str = ut.split(str, ',',  true)[3]

    -- SIM is not init
    if not str then return cb(this, nil, nil) end

    str = unquot(str)
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
  return self:_basic_cmd('AT+CPIN?', function(this, err, info)
    if err then return cb(this, err, info) end

    local code = info:match("^%+CPIN:%s*(.-)%s*$")
    cb(this, nil, code or info)
  end)
end

function ATCommander:CNMI(mode, mt, bm, ds, bfr, cb)
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

    local stat, alpha, len, pdu = info:match("^%+CMGR:%s*(%d+),(.-),(%d+)%s-\n([^\n]+)$")

    -- no PDU mode
    if not stat then return cb(this, nil, info) end

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
  local cmd = string.format("AT+CMGS=%d", len)
  return self:_basic_cmd_ex(cmd, '>', pdu .. '\26', function(this, err, info)
    if err then return cb(this, err, info) end

    local ref, status_pdu = info:match("%+CMGS:%s*(%d+),?(.-)$")
    ref = tonumber(ref)
    if not ref then return cb(this, E('EPROTO', nil, info)) end

    if #status_pdu == 0 then status_pdu = nil
    else status_pdu = unquot(status_pdu) end

    cb(this, nil, ref, status_pdu)
  end)
end

function ATCommander:raw(...)
  return self:_basic_cmd(...)
end

function ATCommander:USSD(cmd, cb)
  local cmd = string.format('AT+CUSD=1,"%s",15', cmd)
  return self:_basic_cmd(cmd, function(this, err, info)
    if err then return cb(this, err, info) end

    local msg = info:match("%+CUSD:%s*(.-)%s*$")
    if not msg then return cb(this, E('EPROTO', nil, info)) end

    local ref, msg, dcs = ut.usplit(msg, ',', true)
    if msg then msg = unquot(msg) end
    ref   = tonumber(ref)
    codec = tonumber(codec)

    cb(this, nil, ref, msg, codec)
  end)
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
