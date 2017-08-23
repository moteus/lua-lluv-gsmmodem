# lua-lluv-gsmmodem
[![Licence](http://img.shields.io/badge/Licence-MIT-brightgreen.svg)](LICENSE)
[![Build Status](https://travis-ci.org/moteus/lua-lluv-gsmmodem.svg?branch=master)](https://travis-ci.org/moteus/lua-lluv-gsmmodem)
[![Coverage Status](https://coveralls.io/repos/moteus/lua-lluv-gsmmodem/badge.svg)](https://coveralls.io/r/moteus/lua-lluv-gsmmodem)

### Usage
* Open and configure
  ```Lua
  local device = GsmModem.new('COM3', {
      baud         = '_9600';
      data_bits    = '_8';
      parity       = 'NONE';
      stop_bits    = '_1';
      flow_control = 'OFF';
      rts          = 'ON';
  })
  device:open(function(self, err, info)
    if err then
      print('Fail open port:', err)
      return self:close()
    end
    print('Connected to port:', info)
    -- Now we should configure modem to allow GsmModem class works properly
    -- (e.g. sms pdu mode, notify mode for sms and calls)
    -- Ofcourse you can use it as-is with out configure.
    self:configure(function(self, err, cmd)
      if err then
        print('Configure error:', err, ' Command:', cmd)
        return self:close()
      end
      print('Configure done')
      -------------------------------------------
      -- Here you can start do your work
      -------------------------------------------
    end)
  end)
  ```

* Send SMS
  ```Lua
  device:send_sms('+7777777', 'Hello world', function(self, err, ref)
    print('SMS Send result:', err or 'OK', 'Message reference:', ref or '<NONE>')
  end)
  ```

* Send SMS and wait report
  ```Lua
  device:send_sms('+7777777', 'Hello world', {waitReport = 'final'}, function(self, err, ref, response)
    if err or not response.success then
      print('SMS Send fail:', err or response.info, 'Message reference:', ref or '<NONE>')
    else
      print('SMS Send pass', 'Message reference:', ref or '<NONE>')
    end
  end)
  ```

* Send USSD
  ```Lua
  device:send_ussd('*100#', function(self, err, msg)
    print('USSD Result:', err, msg and msg:status(), msg and msg:text())
  end)
  ```

* Recv SMS
  ```Lua
  device:on('sms::recv', function(self, event, sms)
    print("SMS from:", sms:number(), "Text:", sms:text())
  end)
  ```

* Proceed SMS delivery report
  ```Lua
  device:on('report::recv', function(self, event, sms)
    local success, status = sms:delivery_status()
    print("SMS reference:", sms:reference(), "Number:", sms:number(), "Success:", success, "Status:", status.info)
  end)
  ```

* Read SMS
  ```Lua
  -- read and delete first SMS from SIM card
  device:read_sms(1, {memory = 'SM', delete = true}, function(self, err, sms)
    print("SMS from:", sms:number(), "Text:", sms:text())
  end)

  -- read all unreaded sms from phone memory
  device:each_sms(GsmModem.REC_UNREAD, {memory='ME'}, function(self, err, idx, sms)
    if err and not index then
      -- e.g. invalid memory
      return print("List SMS error:", err)
    end

    if err then
      -- Some times device can return invalid sms on list (CMGL), but you can
      -- try read sms directly (CMGR) (e.g. device:read_sms(idx ...)
      -- This is works on my WaveCom SIM300
      return print("Read SMS #" .. idx .. " error:", err)
    end

    print("#" .. idx, "SMS from:", sms:number(), "Text:", sms:text())
  end)
  ```
