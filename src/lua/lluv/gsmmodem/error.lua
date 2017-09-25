------------------------------------------------------------------
--
--  Author: Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Copyright (C) 2015-2017 Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Licensed according to the included 'LICENSE' document
--
--  This file is part of lua-lluv-gsmmodem library.
--
------------------------------------------------------------------

local ut = require "lluv.utils"

local CMS_ERROR_INFO = { -- luacheck: ignore
  [300] = [[Mobile equipment (ME) failure. Mobile equipment refers to the mobile
  device that communicates with the wireless network. Usually it is a mobile
  phone or GSM/GPRS modem. The SIM card is defined as a separate entity and
  is not part of mobile equipment.
]],
  [301] = [[SMS service of mobile equipment (ME) is reserved.
  See +CMS error code 300 for the meaning of mobile equipment.]],
  [302] = [[The operation to be done by the AT command is not allowed.]],
  [303] = [[The operation to be done by the AT command is not supported.]],
  [304] = [[One or more parameter values assigned to the AT command are invalid. (For PDU mode)]],
  [305] = [[One or more parameter values assigned to the AT command are invalid. (For Text mode)]],
  [310] = [[There is no SIM card.]],
  [311] = [[The SIM card requires a PIN to operate. The AT command +CPIN
  (command name in text: Enter PIN) can be used to send the PIN to the SIM card.]],
  [312] = [[The SIM card requires a PH-SIM PIN to operate. The AT command +CPIN
  (command name in text: Enter PIN) can be used to send the PH-SIM PIN to the SIM card.]],
  [313] = [[SIM card failure.]],
  [314] = [[The SIM card is busy.]],
  [315] = [[The SIM card is wrong.]],
  [316] = [[The SIM card requires a PUK to operate. The AT command +CPIN
  (command name in text: Enter PIN) can be used to send the PUK to the SIM card.]],
  [320] = [[Memory/message storage failure.]],
  [321] = [[The memory/message storage index assigned to the AT command is invalid.]],
  [322] = [[The memory/message storage is out of space.]],
  [330] = [[The SMS center (SMSC) address is unknown.]],
  [331] = [[No network service is available.]],
  [332] = [[Network timeout occurred.]],
  [340] = [[There is no need to send message acknowledgement by the AT command +CNMA
  (command name in text: New Message Acknowledgement to ME/TA).]],
  [500] = [[An unknown error occurred.]],
  [513] = [[It can be:
  * MS loses the radio link
  * MS does not receive the acknowledge from the network (CP_ACK)
    about 28s after the transmission of the Short Message data (CP_DATA)
  * MS does not receive the acknowledge from the network (CP_DATA(RP_ACK))
    about 42s after the channel establishment request]],
  [514] = [[Service Center Address destination address are wrong]],
}

local CMS_ERROR = {
  [1  ] = 'Unassigned number',
  [8  ] = 'Operator determined barring',
  [10 ] = 'Call bared',
  [21 ] = 'Short message transfer rejected',
  [27 ] = 'Destination out of service',
  [28 ] = 'Unindentified subscriber',
  [29 ] = 'Facility rejected',
  [30 ] = 'Unknown subscriber',
  [38 ] = 'Network out of order',
  [41 ] = 'Temporary failure',
  [42 ] = 'Congestion',
  [47 ] = 'Recources unavailable',
  [50 ] = 'Requested facility not subscribed',
  [69 ] = 'Requested facility not implemented',
  [81 ] = 'Invalid short message transfer reference value',
  [95 ] = 'Invalid message unspecified',
  [96 ] = 'Invalid mandatory information',
  [97 ] = 'Message type non existent or not implemented',
  [98 ] = 'Message not compatible with short message protocol',
  [99 ] = 'Information element non-existent or not implemente',
  [111] = 'Protocol error, unspecified',
  [127] = 'Internetworking , unspecified',
  [128] = 'Telematic internetworking not supported',
  [129] = 'Short message type 0 not supported',
  [130] = 'Cannot replace short message',
  [143] = 'Unspecified TP-PID error',
  [144] = 'Data code scheme not supported',
  [145] = 'Message class not supported',
  [159] = 'Unspecified TP-DCS error',
  [160] = 'Command cannot be actioned',
  [161] = 'Command unsupported',
  [175] = 'Unspecified TP-Command error',
  [176] = 'TPDU not supported',
  [192] = 'SC busy',
  [193] = 'No SC subscription',
  [194] = 'SC System failure',
  [195] = 'Invalid SME address',
  [196] = 'Destination SME barred',
  [197] = 'SM Rejected-Duplicate SM',
  [198] = 'TP-VPF not supported',
  [199] = 'TP-VP not supported',
  [208] = 'D0 SIM SMS Storage full',
  [209] = 'No SMS Storage capability in SIM',
  [210] = 'Error in MS',
  [211] = 'Memory capacity exceeded',
  [212] = 'Sim application toolkit busy',
  [213] = 'SIM data download error',
  [255] = 'Unspecified error cause',
  [300] = 'ME Failure',
  [301] = 'SMS service of ME reserved',
  [302] = 'Operation not allowed',
  [303] = 'Operation not supported',
  [304] = 'Invalid PDU mode parameter',
  [305] = 'Invalid Text mode parameter',
  [310] = 'SIM not inserted',
  [311] = 'SIM PIN required',
  [312] = 'PH-SIM PIN required',
  [313] = 'SIM failure',
  [314] = 'SIM busy',
  [315] = 'SIM wrong',
  [316] = 'SIM PUK required',
  [317] = 'SIM PIN2 required',
  [318] = 'SIM PUK2 required',
  [320] = 'Memory failure',
  [321] = 'Invalid memory index',
  [322] = 'Memory full',
  [330] = 'SMSC address unknown',
  [331] = 'No network service',
  [332] = 'Network timeout',
  [340] = 'No +CNMA expected',
  [500] = 'Unknown error',
  [512] = 'User abort (specifique a certain fabricants)',
  [513] = 'Unable to store',
  [514] = 'Invalid Status',
  [515] = 'Device busy or Invalid Character in string',
  [516] = 'Invalid length',
  [517] = 'Invalid character in PDU',
  [518] = 'Invalid parameter',
  [519] = 'Invalid length or character',
  [520] = 'Invalid character in text',
  [521] = 'Timer expired',
  [522] = 'Operation temporary not allowed',
  [532] = 'SIM not ready',
  [534] = 'Cell Broadcast error unknown',
  [535] = 'Protocol stack busy',
  [538] = 'Invalid parameter',
}

local CME_ERROR = {
  [0  ] = 'Phone failure',
  [1  ] = 'No connection to phone',
  [2  ] = 'Phone adapter link reserved',
  [3  ] = 'Operation not allowed',
  [4  ] = 'Operation not supported',
  [5  ] = 'PH_SIM PIN required',
  [6  ] = 'PH_FSIM PIN required',
  [7  ] = 'PH_FSIM PUK required',
  [10 ] = 'SIM not inserted',
  [11 ] = 'SIM PIN required',
  [12 ] = 'SIM PUK required',
  [13 ] = 'SIM failure',
  [14 ] = 'SIM busy',
  [15 ] = 'SIM wrong',
  [16 ] = 'Incorrect password',
  [17 ] = 'SIM PIN2 required',
  [18 ] = 'SIM PUK2 required',
  [20 ] = 'Memory full',
  [21 ] = 'Invalid index',
  [22 ] = 'Not found',
  [23 ] = 'Memory failure',
  [24 ] = 'Text string too long',
  [25 ] = 'Invalid characters in text string',
  [26 ] = 'Dial string too long',
  [27 ] = 'Invalid characters in dial string',
  [30 ] = 'No network service',
  [31 ] = 'Network timeout',
  [32 ] = 'Network not allowed, emergency calls only',
  [40 ] = 'Network personalization PIN required',
  [41 ] = 'Network personalization PUK required',
  [42 ] = 'Network subset personalization PIN required',
  [43 ] = 'Network subset personalization PUK required',
  [44 ] = 'Service provider personalization PIN required',
  [45 ] = 'Service provider personalization PUK required',
  [46 ] = 'Corporate personalization PIN required',
  [47 ] = 'Corporate personalization PUK required',
  [48 ] = 'PH-SIM PUK required',
  [100] = 'Unknown error',
  [103] = 'Illegal MS',
  [106] = 'Illegal ME',
  [107] = 'GPRS services not allowed',
  [111] = 'PLMN not allowed',
  [112] = 'Location area not allowed',
  [113] = 'Roaming not allowed in this location area',
  [126] = 'Operation temporary not allowed',
  [132] = 'Service operation not supported',
  [133] = 'Requested service option not subscribed',
  [134] = 'Service option temporary out of order',
  [148] = 'Unspecified GPRS error',
  [149] = 'PDP authentication failure',
  [150] = 'Invalid mobile class',
  [256] = 'Operation temporarily not allowed',
  [257] = 'Call barred',
  [258] = 'Phone is busy',
  [259] = 'User abort',
  [260] = 'Invalid dial string',
  [261] = 'SS not executed',
  [262] = 'SIM Blocked',
  [263] = 'Invalid block',
  [772] = 'SIM powered down',
}

local AT_ERROR = {
  CMS                = CMS_ERROR;
  CME                = CME_ERROR;
  ERROR              = {[0] = 'General error'};
  ENOTSUPPORT        = {[0] = 'Command is not supported'};
  ETOOMANYPARAMETERS = {[0] = 'Too many parameters'};
  EPROTO             = {[0] = 'Invalid response'};
  TIMEOUT            = {[0] = 'Command timeout expire'};
  REBOOT             = {[0] = 'Modem rebooted'};
  EINTER             = {[0] = 'Command interrupted by user'};
}

local STATUS_TO_NAME = {
  ['+CMS ERROR'         ] = 'CMS',
  ['+CME ERROR'         ] = 'CME',
  ['COMMAND NOT SUPPORT'] = 'ENOTSUPPORT',
  ['TOO MANY PARAMETERS'] = 'ETOOMANYPARAMETERS',
}

local ATError = ut.class() do

function ATError:__init(name, no, ext)
  self._no   = no or 0
  self._name = name
  self._ext  = ext
  assert(AT_ERROR[name], name )
  return self
end

function ATError:cat()  return 'GSM-AT' end -- luacheck: ignore self

function ATError:no()   return self._no    end

function ATError:name() return self._name end

function ATError:msg()
  local t = AT_ERROR[self._name]
  local msg
  if t then msg = t[self._no] end
  return msg or 'Unknown error'
end

function ATError:ext()  return self._ext   end

function ATError:__eq(rhs)
  return (self._no == rhs._no) and (self._name == rhs._name)
end

function ATError:__tostring()
  local err = string.format("[%s][%s] %s (%d)",
    self:cat(), self:name(), self:msg(), self:no()
  )
  if self:ext() then
    err = string.format("%s - %s", err, self:ext())
  end
  return err
end

end

local function make_error(status, info, ext)
  local name = STATUS_TO_NAME[status] or status
  local no   = tonumber(info)
  if not no then -- if modem response is '+CME ERROR: SIM powered down'
    ext = info or ext
  end
  return ATError.new(name, no, ext)
end

return {
  error = make_error
}

