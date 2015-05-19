local uv       = require "lluv"
local GsmModem = require "lluv.gsmmodem"

local function GsmServer(port, opt, on_sms, on_call)

local device = GsmModem.new(port, opt)

local function init_device(self)
  self:configure(function(self, err, cmd, info)
    if err then
      print("Fail init modem:", err, cmd, info)
      return device:close()
    end
    print("Modem ready")
    self:set_delay(0)
    self:cmd():OperatorName(function(self, err, name) print("Operator:", name) end)
    self:cmd():IMEI(function(self, err, imei)         print("    IMEI:", imei) end)
    self:cmd():at(function()self:set_delay() end)
  end)
end

device:on_recv_sms(function(self, typ, pdu, len)
  local sms = GsmModem.SMSMessage():decode_pdu(pdu, GsmModem.REC_UNREAD)
  if sms then on_sms(self, sms) end
end)

device:on_save_sms(function(self, typ, mem, index)
  self:cmd():CMGR(index, function(self, err, pdu, state)
    if err then
      return print("Error read sms:", err, pdu, state)
    end

    self:cmd():CMGD(index, function(self, err, ...)
      if err then
        return print("Error delete sms:", err, ...)
      end
  
      print("SMS #" .. tostring(index) .. ' deleted')
    end)

    local sms = GsmModem.SMSMessage():decode_pdu(pdu, state)
    if sms then on_sms(self, sms) end
  end)
end)

device:on_call(function(self, typ, ani)
  on_call(self, ani)
end)

device:on_boot(function(self)
  uv.timer():start(10000, function(timer)
    timer:close()
    init_device(self)
  end)
end)

device:open(function(self, err, msg)
  if err then
    print('Fail open port:', err, msg)
    return
  end

  print("Port open:", msg)
  init_device(self)
end)

end

local function on_sms(device, sms)
  print("SMS from:", sms:number(), "Text:", sms:text())
end

local function on_call(device, ani)
  print("Call from:", ani)
end

GsmServer('COM3', {
  baud         = '_9600';
  data_bits    = '_8';
  parity       = 'NONE';
  stop_bits    = '_1';
  flow_control = 'OFF';
  rts          = 'ON';
}, on_sms, on_call)

uv.run()
