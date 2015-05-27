# lua-lluv-gsmmodem
[![Licence](http://img.shields.io/badge/Licence-MIT-brightgreen.svg)](LICENSE)
[![Build Status](https://travis-ci.org/moteus/lua-lluv-gsmmodem.svg?branch=master)](https://travis-ci.org/moteus/lua-lluv-gsmmodem)
[![Coverage Status](https://coveralls.io/repos/moteus/lua-lluv-gsmmodem/badge.svg)](https://coveralls.io/r/moteus/lua-lluv-gsmmodem)

###Usage
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

* Recv SMS
  ```Lua
  device:on_recv_sms(function(self, sms)
    print("SMS from:", sms:number(), "Text:", sms:text())
  end)
  ```
 
