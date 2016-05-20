package.path = '../src/lua/?.lua;' .. package.path

local GsmModem = require "lluv.gsmmodem"
local uv       = require "lluv"
local ut       = require "lluv.utils"
local utils    = require "lluv.gsmmodem.utils"
local ok, pp   = pcall(require, "pp")
if not ok then pp = print end

local device = GsmModem.new('COM3', {
  baud         = '_9600';
  data_bits    = '_8';
  parity       = 'NONE';
  stop_bits    = '_1';
  flow_control = 'OFF';
  rts          = 'ON';
})

local SMS_NUMBER  = nil
local USSD_NUMBER = '*100#'
local CODE_PAGE   = 'cp866'

device:open(function(self, err, info)
  if err then
    print("Port open FAIL:", err)
    return self:close()
  end

  print("Port open:", info)

  self:configure(function(self, err, cmd, info)
    if err then
      print("Fail init modem:", err, 'Command:', cmd)
      return self:close()
    end

    print("Configure done")

    -- self:set_rs232_trace(true)

    self:read_sms(1, {memory='SM'}, function(self, err, sms)
      print(err or sms:text(CODE_PAGE))
    end)

    self:read_sms(1, {memory='ME'}, function(self, err, sms)
      print(err or sms:text(CODE_PAGE))
    end)

    self:each_sms({memory = 'SM'}, function(self, err, index, sms, total, last)
      if err and not index then
        return print("Error:", err)
      end

      if err then -- try read sms directly
        return self:read_sms(index, {memory = 'SM'}, function(self, err, sms)
          print(index, sms and sms:number(), sms and sms:text(CODE_PAGE) or err, sms and sms:date())
        end)
      end

      print(index,  sms and sms:number(), sms and sms:text(CODE_PAGE) or err, sms and sms:date())
    end)

    if USSD_NUMBER then
      self:send_ussd(USSD_NUMBER, function(self, err, status, data, dcs)
        if data then data = utils.DecodeUssd(data, dcs, CODE_PAGE) end

        print('USSD Result:', err, status, data, dcs)
      end)
    end

    if SMS_NUMBER then
      self:send_sms(SMS_NUMBER, 'hello', {validity = 5, waitReport = true}, function(self, err, ref)
        print('SMS Send result:', err or 'OK', 'Message reference:', ref or '<NONE>')
      end)
    end

    self:cmd():at(function()
      self:close()
    end)

  end)
end)

uv.run(debug.traceback)
