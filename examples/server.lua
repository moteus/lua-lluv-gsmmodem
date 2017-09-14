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

device:on('sms::recv', function(self, _, ...) on_sms(self, ...)  end)

device:on('call',      function(self, _, ...) on_call(self, ...) end)

device:on('sms::save', function(self, _, index, mem)
  self:read_sms(index, {delete=true, memory = mem}, function(self, err, sms, del_err)
    if err then
      return print("Error read sms:", err)
    end

    on_sms(self, sms, del_err)
  end)
end)

device:on('boot', function(self)
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
  print("SMS from:", sms:number(), "Text:", sms:text('cp866'))
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

uv.run(debug.traceback)
