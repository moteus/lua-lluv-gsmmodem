local at    = require "lluv.gsmmodem.at"
local utils = require "lluv.gsmmodem.utils"
local Error = require "lluv.gsmmodem.error".error
local uv    = require "lluv"
local ut    = require "lluv.utils"
local tpdu  = require "tpdu"
uv.rs232    = require "lluv.rs232"

local pack_args = utils.pack_args
local ts2date   = utils.ts2date
local date2ts   = utils.date2ts

local DEFAULT_COMMAND_TIMEOUT = 60000
local DEFAULT_COMMAND_DELAY   = 200

local SMSMessage

local REC_UNREAD    = 0
local REC_READ      = 1
local STORED_UNSENT = 2
local STORED_SENT   = 3
local STAT_ANY      = 4

local MESSAGE_STATUS = {
  ['REC UNREAD'] = 'DELIVER',
  ['REC READ']   = 'DELIVER',
  ['STO UNSENT'] = 'SUBMIT',
  ['STO SENT']   = 'SUBMIT',
}

local function DecodeSms(pdu, stat, ...)
  if type(stat) == 'string' then
    local address = ...
    sms = SMSMessage.new(address, pdu)
    sms:set_type(MESSAGE_STATUS[stat])
    return sms
  end

  local len = ...
  local t, e = tpdu.Decode(pdu,
    (stat == REC_UNREAD or stat == REC_READ) and 'input' or 'output',
    len
  )

  -- we have no idea about direction so try guess
  if (not t) and ((stat == nil) or (stat == STAT_ANY)) then
    t, e = tpdu.Decode(pdu, 'input', len)
  end

  if not t then
    local info = string.format("SMS Decode fail: %s (len=%d data=%q)", e, len, pdu)
    return nil, Error('EPROTO', nil, info)
  end

  local sms = SMSMessage.new():decode_pdu(t)
  return sms
end

---------------------------------------------------------------
local GsmModem = ut.class() do

local URC_TYPS = {
  [ '+CMT'  ] = 'on_recv_sms';
  [ '+CMTI' ] = 'on_save_sms';
  [ '+CDS'  ] = 'on_recv_status';
  [ '+CDSI' ] = 'on_save_status';
  [ '+CLIP' ] = 'on_call';
}
local URC_TYPS_INVERT = {}
for k, v in pairs(URC_TYPS) do URC_TYPS_INVERT[v] = k end

function GsmModem:__init(...)
  local device
  if type(...) == 'string' then
    device  = uv.rs232(...)
  else
    device = ...
  end

  local stream  = at.Stream(self)
  local command = at.Commander(stream)

  -- Время для ответо от модема
  local cmdTimeout = uv.timer():start(0, DEFAULT_COMMAND_TIMEOUT, function(timer)
    stream:_command_done('TIMEOUT')
  end):stop()

  -- Посылать команды не чаще чем ...
  -- Некоторые модемы могут вести себя неадекватно если посылать команды слишком быстро
  local cmdSendTimer = uv.timer():start(0, DEFAULT_COMMAND_DELAY, function(timer)
    timer:stop()
    stream:next_command()
  end):stop()

  stream:on_command(function(stream, cmd, timeout)
    if self._device then
      self._device:write(cmd)
      self._cmd_timer:again(timeout or DEFAULT_COMMAND_TIMEOUT)
    end
  end)

  -- Stop timeout timer
  stream:on_done(function()
    if self._cmd_timer then
      self._cmd_timer:stop()
    end
  end)

  -- Wait before send out command
  stream:on_delay(function()
    if self._snd_timer then
      self._snd_timer:again()
    end
  end)

  self._device    = device
  self._stream    = stream
  self._command   = command
  self._cmd_timer = cmdTimeout
  self._snd_timer = cmdSendTimer
  self._urc       = {}
  self._cds_wait  = {}
  self._reference = 0

  stream:on_message(function(this, typ, msg, info)
    local fn = self._urc['*']
    if fn then fn(this, typ, msg, info) end

    if typ == '+CDS' then
      self:_on_cds_check(at.DecodeUrc(nil, typ, msg, info))
    end

    fn = self._urc[typ]
    if fn then fn(this, at.DecodeUrc(nil, typ, msg, info)) end
  end)

  return self
end

function GsmModem:cmd(front, chain)
  return self._command:mode(front, chain)
end

function GsmModem:configure(cb)
  local command = self:cmd()
  local chain

  local function next_fn()
    local f = table.remove(chain, 1)
    if f then return f() end
    cb(self)
  end

  chain = {
    function() command:raw("\26", 5000, next_fn) end;

    function() self:at_wait(30, function(self, err, data)
      if err then return cb(this, err, 'AT', data) end
      next_fn()
    end) end;

    function() command:Echo(false, function(this, err, data)
      if err then return cb(this, err, 'Echo', data) end
      next_fn()
    end) end;

    function() command:ErrorMode(1, function(this, err, data)
      if err then return cb(this, err, 'ErrorMode', data) end
      next_fn()
    end) end;

    function() command:SmsTextMode(false, function(this, err, mode)
      if err then return cb(this, err, 'CMGF', data) end
      next_fn()
    end) end;

    function() command:CNMI(2, 2, nil, 1, nil, function(this, err, data)
      if err then return cb(this, err, 'CNMI', data) end
      next_fn()
    end) end;

    function() command:CLIP(1, function(this, err, data)
      if err then return cb(this, err, 'CLIP', data) end
      next_fn()
    end) end;

    function() command:at('+CSCS="IRA"', function(this, err, data)
      if err then return cb(this, err, 'CSCS', data) end
      next_fn()
    end) end;
  }

  next_fn()

  return self
end

function GsmModem:open(cb)
  return self._device:open(function(dev, err, ...)
    if not err then
      self._device:start_read(function(dev, err, data)
        if err then
          return print('Read from port fail:', err, data)
        end

        if data:sub(-1) == '\255' then
          self._stream:reset(Error('REBOOT'))
          self._cmd_timer:stop()
          self._snd_timer:stop()

          if self._on_boot then
            self:_on_boot()
          end

          return
        end

        self._stream:append(data)
        self._stream:execute()
      end)
    end
    return cb(self, err, ...)
  end)
end

function GsmModem:close(cb)
  if self._device then
    self._stream:reset(Error'EINTER')
    self._cmd_timer:close()
    self._snd_timer:close()
    self._device:close(cb)
    self._device, self._cmd_timer, self._snd_timer = nil
  end
end

function GsmModem:set_delay(ms)
  ms = ms or DEFAULT_COMMAND_DELAY
  if ms <= 1 then ms = 1 end
  self._snd_timer:set_repeat(ms)
  return self
end

function GsmModem:on_boot(handler)
  self._on_boot = handler
end

function GsmModem:on_urc(handler)
  self._urc['*'] = handler
  return self
end

function GsmModem:on_recv_sms(handler)
  local typ = URC_TYPS_INVERT['on_recv_sms']
  if not handler then self._urc[typ] = nil else
    self._urc[typ] = function(self, typ, mode, ...)
      local sms, err
      if mode then
        local text, number = ...
        sms, err = SMSMessage.new(number, text)
      else
        local pdu, len = ...
        sms, err = SMSMessage.new():decode_pdu(pdu, REC_UNREAD, len)
      end
      --! @todo handle error
      if sms then handler(self, sms) end
    end
  end

  return self
end

function GsmModem:on_save_sms(handler)
  local typ = URC_TYPS_INVERT['on_save_sms']
  if not handler then self._urc[typ] = nil else
    self._urc[typ] = function(self, typ, ...)
      handler(self, ...)
    end
  end
  return self
end

function GsmModem:on_sms(handler)
  return self
    :on_recv_sms(handler)
    :on_save_sms(handler)
end

function GsmModem:on_recv_status(handler)
  local typ = URC_TYPS_INVERT['on_recv_status']
  if not handler then self._urc[typ] = nil else
    self._urc[typ] = function(self, typ, mode, ...)
      local sms, err
      if mode then
        local ref, status, number = ...
        sms = SMSMessage.new()
          :set_type('DELIVER-REPORT')
          :set_reference(ref)
          :set_delivery_status(status)
          :set_number(number)
      else
        local pdu, len = ...
        sms, err = SMSMessage.new():decode_pdu(pdu, REC_UNREAD, len)
      end
      --! @todo handle error
      if sms then handler(self, sms) end
    end
  end

  return self
end

function GsmModem:on_save_status(handler)
  local typ = URC_TYPS_INVERT['on_save_status']
  if not handler then self._urc[typ] = nil else
    self._urc[typ] = function(self, typ, ...)
      handler(self, ...)
    end
  end
  return self
end

function GsmModem:on_status(handler)
  return self
    :on_recv_status(handler)
    :on_save_status(handler)
end

function GsmModem:on_call(handler)
  local typ = URC_TYPS_INVERT['on_call']
  if not handler then self._urc[typ] = nil else
    self._urc[typ] = function(self, typ, ...)
      handler(self, ...)
    end
  end
  return self
end

function GsmModem:next_reference()
  self._reference = (self._reference + 1) % 0xFFFF
  if self._reference == 0 then self._reference = 1 end
  return self._reference
end

local function remove_wait_ref(self, ref, status)
  local ctx = self._cds_wait[ref]
  if not ctx then return end

  if ctx.set[ref] then
    if not status or ctx.wait_any or not status.temporary then
      self._cds_wait[ref]   = nil
      ctx.set[ref] = nil
      ctx.ret[ref] = status
    end
  end

  if not (ctx.progress  or next(ctx.set)) then
    if ctx.timer then ctx.timer:close() end
    local ref, ret = ctx.ref, ctx.ret
    return ctx.cb(self, nil, ref, ret[ref] or ret)
  end
end

local function register_wait_ref(self, ref, ctx)
  --! @todo use address:ref as key

  local prev = self._cds_wait[ref]
  if prev then remove_wait_ref(prev, ref) end

  self._cds_wait[ref] = ctx
  ctx.set[ref]        = true
end

local function wait_timeout(self, ctx)
  ctx.timer:close()

  for ref in pairs(ctx.set) do
    self._cds_wait[ref] = nil
  end

  return ctx.cb(self, Error'TIMEOUT', ref)
end

function GsmModem:_on_cds_check(typ, mode, ...)
  local ref, status, number
  if mode then
    ref, status, number = ...
    status = tpdu._DecodeStatus(status)
  else
    local pdu, len = ...
    pdu = tpdu.Decode(pdu, 'input', len)
    --! @todo handle error
    if not (pdu or pdu.mr or pdu.status) then return end
    ref, status, number = pdu.mr, pdu.status, pdu.addr
  end

  remove_wait_ref(self, ref, status, number)
end

function GsmModem:send_sms(...)
  local cb, number, text, opt = pack_args(...)
  text = text or ''
  local pdus = utils.EncodeSmsSubmit(number, text, {
    reference           = self:next_reference();
    requestStatusReport = true;
    validity            = opt and opt.validity;
    smsc                = opt and opt.smsc;
    rejectDuplicates    = opt and opt.rejectDuplicates;
    replayPath          = opt and opt.replayPath;
    flash               = opt and opt.flash;
  })
  local cmd  = self:cmd()

  local waitCds = opt and opt.waitReport

  local wait_ctx wait_ctx = waitCds and {
    set      = {};
    ret      = {};
    cb       = cb;
    ref      = nil;
    progress = true;
    number   = number;
    wait_any = waitCds == 'any';
  }

  if #pdus == 1 then
    cmd:CMGS(pdus[1][2], pdus[1][1], function(self, err, ref)
      if err then return cb(self, err) end

      if not waitCds then return cb(self, nil, ref) end

      register_wait_ref(self, ref, wait_ctx)
      wait_ctx.timer    = opt and opt.timeout and uv.timer():start(opt.timeout, function()
        wait_timeout(self, wait_ctx)
      end)
      wait_ctx.ref      = ref
      wait_ctx.progress = nil
    end)
  else
    local count, res, send_err = #pdus, {}
    for i, pdu in ipairs(pdus) do
      cmd:CMGS(pdu[2], pdu[1], function(self, err, ref)
        if err then send_err = err end

        if waitCds and not err then
          register_wait_ref(self, ref, wait_ctx)
        end

        res[i] = err or ref
        count = count - 1

        if count == 0 then
          if not waitCds then return cb(self, send_err, res) end

          wait_ctx.ref      = res
          wait_ctx.progress = nil

          if send_err then -- do not wait if at least one error
            for _, ref in ipairs(res) do
              self._cds_wait[ref] = nil
            end
            return cb(self, send_err, res)
          end

          wait_ctx.timer    = opt and opt.timeout and uv.timer():start(opt.timeout, function()
            wait_timeout(self, wait_ctx)
          end)
        end
      end)
    end
  end

  return self
end

function GsmModem:send_ussd(...)
  return self:cmd():CUSD(...)
end

function GsmModem:at_wait(...)
  local cb, cmd, sec = pack_args(...)
  if type(cmd) == 'number' then
    cmd, sec = '', cmd
  end

  local counter, poll_timeout = 0, 1000
  sec = sec or 60

  local function on_wait(self, err, data)
    if err then
      counter = counter + 1
      if counter > sec then
        return cb(this, err, 'AT', data)
      end
      return self:cmd():at(cmd, poll_timeout, on_wait)
    end
    cb(self)
  end

  self:cmd():at(cmd, poll_timeout, on_wait)

  return self
end

function GsmModem:set_rs232_trace(lvl)
  if lvl == false then lvl = 'none' end
  if lvl == true or lvl == nil then lvl = 'trace' end
  self._device:set_log_level(lvl)
end

function GsmModem:read_sms(...)
  local cb, index, opt = pack_args(...)
  local mem, del
  if type(opt) == 'string' then mem = opt else
    mem = opt and opt.memory
    del = opt and opt.delete
  end

  local function do_read(self, err)
    if err then return cb(self, err) end

    local front, chain = not not mem, not not del

    self:cmd(front, chain):CMGR(index, function(self, err, pdu, stat, ...)
      if err then return cb(self, err) end

      local sms, err = DecodeSms(pdu, stat, ...)
      if not sms then return cb(self, err) end

      sms:set_index(index)
      if mem then
        sms:set_storage(mem)
      end

      if del then
        return self:cmd(true):CMGD(index, function(self, err)
          cb(self, nil, sms, err)
        end)
      end

      cb(self, nil, sms)
    end)
  end

  if mem then
    self:cmd(false, true):at('+CPMS="' .. mem .. '"', do_read)
  else
    do_read(self)
  end
end

function GsmModem:delete_sms(...)
  local cb, sms, opt = pack_args(...)

  local index, mem
  if getmetatable(sms) == SMSMessage then
    index = sms:index()
    mem   = sms:location()
  else
    index = sms
    if type(opt) == 'string' then mem = opt else
      mem = opt and opt.memory
    end
  end

  if mem then
    self:cmd(false, true):at('+CPMS="' .. mem .. '"', function(self, err)
      if err then return cb(self, err) end
      self:cmd(true):CMGD(index, cb)
    end)
  else
    self:cmd():CMGD(index, cb)
  end
end

function GsmModem:each_sms(...)
  local cb, status, opt = pack_args(...)
  if type(status) == 'table' then
    opt, status = status
  end

  local mem = opt and opt.memory

  local function do_each(self, err, pdus)
    if err then return cb(self, err) end
    local total = #pdus
    for i = 1, total do
      local t = pdus[i]
      local index, pdu, stat, len = t[1], t[2], t[3], t[4]
      local sms, err = DecodeSms(pdu, stat, len)
      cb(self, err, index, sms, total, i == total)
    end
  end

  if mem then
    self:cmd(false, true):at('+CPMS="' .. mem .. '"', function(self, err)
      if err then return cb(self, err) end
      self:cmd(true):CMGL(status, do_each)
    end)
  else
    self:cmd():CMGL(status, do_each)
  end

end

end
---------------------------------------------------------------

---------------------------------------------------------------
SMSMessage = ut.class() do

function SMSMessage:__init(address, text, flash)
  self._type   = 'SUBMIT'
  self:set_number(address)
  if text then self:set_text(text) end
  self:set_flash(flash)
  return self
end

local function find_udh(udh, ...)
  if not udh then return end

  for i = 1, select('#', ...) do
    local iei = select(i, ...)
    for j = 1, #udh do
      if udh[j].iei == iei then
        return udh[j]
      end
    end
  end
end

function SMSMessage:decode_pdu(pdu, state)
  if type(pdu) == 'string' then
    local err
    pdu, err = tpdu.Decode(pdu,
      (state == REC_UNREAD or state == REC_READ) and 'input' or 'output'
    )
    if not pdu then return nil, err end
  end

  self._smsc              = pdu.sc.number       -- SMS Center
  self._validity          = pdu.vp              -- Validity of SMS messages
  self._reject_duplicates = pdu.tp.rd           -- Whether to reject duplicates
  self._udh               = pdu.udh             -- User Data Header
  self._number            = pdu.addr.number     -- Sender or recipient number
  self._text              = pdu.ud              -- Text for SMS
  self._type              = pdu.tp.mti          -- Type of message
  self._delivery_status   = pdu.status          -- In delivery reports: status
  self._replay_path       = pdu.tp.rp           -- Indicates whether "Reply via same center" is set.
  self._reference         = pdu.mr              -- Message reference.
  if pdu.dcs then
    self._class           = pdu.dcs.class       -- SMS class (0 is flash SMS, 1 is normal one).
    self._codec           = pdu.dcs.codec       -- Type of coding. (pdu.dcs.codec, pdu.dcs.compressed)
  end

  if type(self._validity) == 'table' then
    self._validity = ts2date(self._validity)
  end

  if pdu.dts then
    self._date            = ts2date(pdu.dts)    -- Date and time, when SMS was saved or sent (pdu.dts)
  end

  if pdu.scts then
    self._smsc_date       = ts2date(pdu.scts)    -- Date of SMSC response in DeliveryReport messages (pdu.scts)
  end

  self._storage           = nil                -- For saved SMS: where exactly it's saved (SIM/phone)
  self._index             = nil                -- For saved SMS: location of SMS in memory.
  self._state             = nil                -- For saved SMS: Status (read/unread/...) of SMS message.

  local concatUdh = find_udh(pdu.udh, 0x00, 0x80)
  if concatUdh and concatUdh.cnt > 1 then
    self._concat_number    = concatUdh.no
    self._concat_reference = concatUdh.ref
    self._concat_count     = concatUdh.cnt
  end

  return self
end

function SMSMessage:pdu()
  local pdu = {}

  pdu.tp = {
    mti = self._type;
    rd  = self._reject_duplicates;
    rp  = self._replay_path;
  }

  pdu.dcs = {
    class = self._class;
    codec = self._codec;
  }

  if self._smsc then
    pdu.sc = {
      number = self._smsc
    }
  end

  if self._number then
    pdu.addr = {
      number = self._number
    }
  end

  if self._validity then
    local vp = self._validity
    if type(vp) ~= 'number' then
      vp = date2ts(vp)
    end
    pdu.vp = vp
  end

  if self._reference then
    pdu.mr = self._reference % 0xFF
  end

  if self._text then
    pdu.ud = self._text
  end

  return tpdu.Encode(pdu)
end

function SMSMessage:set_memory(mem, loc)
  self._memory   = mem
  self._location = location
  return self
end

function SMSMessage:memory()
  return self._memory, self._location
end

function SMSMessage:set_text(text, encode)
  local codec

  assert(text)

  if not encode and utils.IsGsm7Compat(text) then
    text  = utils.EncodeGsm7(text)
    codec = 'BIT7'
  else
    text = utils.EncodeUcs2(text, nil, encode)
    codec = 'UCS2'
  end

  self._text  = text
  self._codec = codec

  return self
end

function SMSMessage:text(encode)
  local text, codec = self._text, self._codec

  if codec == 'BIT7' then
    text  = utils.DecodeGsm7(text, encode)
    codec = encode or 'ASCII'
  elseif codec == 'UCS2' then
    if encode then
      text  = utils.DecodeUcs2(text, encode)
      codec = encode
    end
  end

  return text, codec
end

function SMSMessage:set_number(v)
  self._number = v
  return self
end

function SMSMessage:number()
  return self._number
end

function SMSMessage:set_reject_duplicates(v)
  self._reject_duplicates = not not v
  return self
end

function SMSMessage:reject_duplicates()
  return not not self._reject_duplicates
end

function SMSMessage:set_reference(v)
  self._reference = v
  return self
end

function SMSMessage:reference()
  return self._reference
end

function SMSMessage:delivery_status()
  local state = self._delivery_status
  if not state then return end

  return state.success, state
end

function SMSMessage:set_delivery_status(v)
  if type(v) == 'number' then
    self._delivery_status = tpdu._DecodeStatus(v)
  else
    self._delivery_status = v
  end

  return self
end

function SMSMessage:flash()
  return self._class == 1
end

function SMSMessage:set_flash(v)
  if v then self._class = 1 else self._class = nil end
  return self
end

function SMSMessage:set_type(v)
  self._type = v
  return self
end

function SMSMessage:type()
  return self._type
end

function SMSMessage:set_storage(v)
  self._storage = v
  return self
end

function SMSMessage:storage()
  return self._storage
end

function SMSMessage:set_index(v)
  self._index = v
  return self
end

function SMSMessage:index()
  return self._index
end

function SMSMessage:date()
  return self._date or self._smsc_date
end

end
---------------------------------------------------------------

return {
  new        = GsmModem.new;
  SMSMessage = SMSMessage.new;

  REC_UNREAD    = REC_UNREAD;
  REC_READ      = REC_READ;
  STORED_UNSENT = STORED_UNSENT;
  STORED_SENT   = STORED_SENT;
}