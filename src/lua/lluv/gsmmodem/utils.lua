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

local tpdu    = require "tpdu"
local Bit7    = require "tpdu.bit7"
local hex2bin = require "tpdu.utils".hex2bin
local iconv   = require "iconv"
local lpeg    = require "lpeg"
local date    = require "date"
local ut      = require "lluv.utils"

local unpack = unpack or table.unpack

-- This is not full GSM7 encode table but just ascii subset
local GSM_PAT = [=[^[ ^{}\%[~%]|@!?$_&%%#'"`,.()*+-/0123456789:;<=>ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz]*$]=]

local BASE_ENCODE = 'ASCII'

local iconv_encode do

local IconvError = ut.class() do

local ERROR_NAMES = {
  [ iconv.ERROR_NO_MEMORY  ] = 'NO_MEMORY';
  [ iconv.ERROR_INVALID    ] = 'INVALID';
  [ iconv.ERROR_INCOMPLETE ] = 'INCOMPLETE';
  [ iconv.ERROR_FINALIZED  ] = 'FINALIZED';
  [ iconv.ERROR_UNKNOWN    ] = 'UNKNOWN';
}

local ERROR_MESSAGES = {
  [ iconv.ERROR_NO_MEMORY  ] = 'Failed to allocate enough memory in the conversion process';
  [ iconv.ERROR_INVALID    ] = 'An invalid character was found in the input sequence';
  [ iconv.ERROR_INCOMPLETE ] = 'An incomplete character was found in the input sequence';
  [ iconv.ERROR_FINALIZED  ] = 'Trying to use an already-finalized converter';
  [ iconv.ERROR_UNKNOWN    ] = 'There was an unknown error';
}

function IconvError:__init(no, ext)
  self._no   = no
  self._name = assert(ERROR_NAMES[self._no])
  self._ext  = ext

  return self
end

function IconvError:cat()  return 'ICONV' end

function IconvError:no()   return self._no    end

function IconvError:name() return self._name end

function IconvError:msg()  return ERROR_MESSAGES[self._no] end

function IconvError:ext()  return self._ext   end

function IconvError:__eq(rhs)
  return (self._no == rhs._no) and (self._name == rhs._name)
end

function IconvError:__tostring()
  local err = string.format("[%s][%s] %s (%d)",
    self:cat(), self:name(), self:msg(), self:no()
  )
  if self:ext() then
    err = string.format("%s - %s", err, self:ext())
  end
  return err
end

end

local iconv_cache = setmetatable({},{__mode = 'v'})

iconv_encode = function (from, to, str)
  if from == to then return str end

  local key  = from .. ':' .. to
  local conv = iconv_cache[ key ] 
  if not conv then
    local err conv, err = iconv.new(to, from)
    if not conv then
      return nil, IconvError.new(iconv.ERROR_UNKNOWN, key)
    end
  end
  iconv_cache[ key ] = conv

  local msg, err = conv:iconv(str)
  if err then err = IconvError.new(err, key) end

  return msg, err 
end

end

local function split_len(str, len, byte)
  if len >= #str then return str end

  local t, b, e = {}, 1, len
  while b <= #str do
    if byte and str:byte(e) == byte then e = e - 1 end
    t[#t+1] = str:sub(b, e)
    b, e = e + 1, e + len
  end
  return t
end

local function IsGsm7(str)
  return not not str:match(GSM_PAT)
end

local function EncodeGsm7(str, len)
  if not IsGsm7(str) then return false end

  str = Bit7.Asci2Gsm(str)
  return len and split_len(str, len, 0x1B) or str
end

local function EncodeUcs2(str, len, from)
  from = from or BASE_ENCODE
  str = iconv_encode(from, 'ucs-2', str)

  return len and split_len(str, len * 2) or str
end

local function DecodeGsm7(str, to)
  str = Bit7.Gsm2Asci(str)
  if to then
    str = iconv_encode('ASCII', to, str)
  end
  return str
end

local function DecodeUcs2(str, to)
  to = to or BASE_ENCODE
  return iconv_encode('ucs-2', to, str)
end

local MAX_SYMBOLS = {BIT7 = 160; BIT8 = 140; UCS2 = 70}
local CODECS = {
  BIT7 = EncodeGsm7;
  UCS2 = EncodeUcs2;
}

local function EncodeText(str, codec, len)
  len = len or MAX_SYMBOLS[codec]
  return CODECS[codec](str, len)
end

local function EncodeValidity(vp)
  if not vp then return vp end
  if type(vp) ~= 'number' then
    vp = date2ts(vp)
  end
  return vp
end

local next_reference, reset_reference do

local ref = 0

next_reference = function ()
  ref = (ref + 1) % 0xFFFF
  if ref == 0 then ref = 1 end
  return ref
end

reset_reference = function (v)
  ref = v or 0
end

end

local function EncodeSmsSubmit(number, text, opt)
  opt = opt or {}

  local reference           = opt.reference or 0
  local validity            = opt.validity
  local smsc                = opt.smsc
  local requestStatusReport = opt.requestStatusReport == nil and true or opt.requestStatusReport
  local rejectDuplicates    = not not opt.rejectDuplicates
  local replayPath          = not not opt.replayPath
  local flash               = not not opt.flash

  local encodedText = EncodeGsm7(text, MAX_SYMBOLS.BIT7)
  local codec = encodedText and 'BIT7' or 'UCS2'
  if not encodedText then encodedText = EncodeText(text, codec) end

  local pdu = { sc = smsc, addr = number,
    tp = {
      rd  = rejectDuplicates;
      rp  = replayPath;
      srr = requestStatusReport
    };
    dcs = {
      class = flash and 1 or 'NONE';
      codec = codec;
    };
    vp = EncodeValidity(validity);
    mr = reference;
  }

  local res = {}
  if type(encodedText) == 'string' then
    pdu.ud = encodedText
    res[#res + 1] = {tpdu.Encode(pdu)}
  else
    local ref, iei, ielen = next_reference(), 0, 5
    if ref > 0xFF then iei, ielen = 0x08, 6 end

    local len
    if codec == 'BIT7' then
      len = MAX_SYMBOLS['BIT7'] - math.ceil(ielen * 8 / 7) - 1
    else
      len = MAX_SYMBOLS['UCS2'] - ielen
    end

    encodedText = EncodeText(text, codec, len)
    pdu.udh = {{ iei = iei, ref = ref, cnt = #encodedText}}

    local i = 1
    while true do
      if not encodedText[i] then break end
      pdu.udh[1].no = i
      pdu.ud = encodedText[i]
      res[i] = {tpdu.Encode(pdu)}
      i = i + 1
    end
  end
  return res
end

local function DecodeUssd(msg, dcs, to)
  local t, err = tpdu._DCSBroadcastDecode(dcs)
  if not t then return nil, err end

  if string.match(msg, "^[0-9a-fA-F]+$") and (#msg % 2 == 0) then
    msg = hex2bin(msg)
  end

  local decoded, lang = msg, t.lang_code
  if t.group == 1 then
    -- Spec describe only UCS2 and BIT7
    local lang = DecodeGsm7(string.sub(msg, 1, 2))
    if t.codec == 'UCS2' then
      decoded = DecodeUcs2(string.sub(msg, 3), to)
    elseif t.codec == 'BIT7' then
      -- <LANG><CR>text
      decoded = string.sub(DecodeGsm7(msg, to), 4)
    end
  elseif t.codec == 'UCS2' then
    decoded = DecodeUcs2(msg, to)
  elseif t.codec == 'UCS2' then
    decoded = DecodeUcs2(msg, to)
  elseif t.codec == 'BIT7' then
    decoded = DecodeGsm7(msg, to)
  elseif t.codec == 'BIT8' then
    if to then
      decoded = iconv_encode('ASCII', to, msg)
    else
      decoded = msg
    end
  end

  return decoded
end

local function dummy()end

local function is_callable(f) return (type(f) == 'function') and f end

local function pack_args(...)
  local n    = select("#", ...)
  local args = {...}
  local cb   = args[n]
  if is_callable(cb) then
    args[n] = nil
    n = n - 1
  else
    cb = dummy
  end

  return cb, unpack(args, 1, n)
end

local function ts2date(d)
  local tz  = math.abs(d.tz)
  local htz = math.floor(tz)
  local mtz = math.floor(
    60 * ((tz * 100) % 100) / 100
  )

  local s = string.format("20%.2d-%.2d-%.2d %.2d:%.2d:%.2d %s%d:%.2d",
    d.year, d.month, d.day,
    d.hour, d.min, d.sec,
    d.tz < 0 and '-' or '+', htz, mtz
  )

  return date(s)
end

local function date2ts(d)
  local ts = {
    year  = d:getyear() % 1000,
    month = d:getmonth(),
    day   = d:getday(),
    hour  = d:gethours(),
    min   = d:getminutes(),
    sec   = d:getseconds(),
    tz    = d:getbias() / 60,
  }

  return ts
end

local function ocall(fn, ...)
  if fn then return fn(...) end
end

local function lpeg_match(str, pat)
  local t, pos = pat:match(str)
  if pos ~= nil then str = str:sub(pos) end
  return t, str
end

local split_args do
  local function MakeCsvGramma(sep, quot)
    assert(#sep == 1 and #quot == 1)
    local P, C, Cs, Ct, Cp = lpeg.P, lpeg.C, lpeg.Cs, lpeg.Ct, lpeg.Cp
    local nl, sp   = P('\n'), P(' ')^0
    local any, eos = P(1), P(-1)

    local nonescaped = C((any - (nl + P(quot) + P(sep) + eos))^0)
    local escaped = 
      sp * P(quot) *
        Cs(
          ((any - P(quot)) + (P(quot) * P(quot)) / quot)^0
        ) *
      P(quot) * sp

    local field      = escaped + nonescaped
    local record     = Ct(field * ( P(sep) * field )^0) * (nl + eos) * Cp()
    return record
  end

  local pat = MakeCsvGramma(',', '"')
  split_args = function(str)
    return lpeg_match(str, pat)
  end
end

local split_list, decode_list do
  local function MakeListGramma(sep)
    assert(#sep == 1)
    local P, C, Cs, Ct, Cp = lpeg.P, lpeg.C, lpeg.Cs, lpeg.Ct, lpeg.Cp
    local nl, sp   = P('\n'), P(' ')^0
    local any, eos = P(1), P(-1)
    local quot = P('(') + P(')')

    local nonescaped = sp * C(
      (any - (quot + P(sep) + nl - eos))^0
    ) * sp
    local escaped =  sp * P('(') * Cs((any - quot)^0) * P(')') * sp

    local field      = escaped + nonescaped
    local record     = Ct(field * ( P(sep) * field )^0) * (nl + eos) * Cp()
    return record
  end

  local pat = MakeListGramma(',')
  split_list = function(str)
    return lpeg_match(str, pat)
  end

  local function decode_range(res, t, flat)
    local a, b = ut.split_first(t, '-', true)
    if b and tonumber(a) and tonumber(b) then
      if flat then
        for i = tonumber(a), tonumber(b) do res[#res+1] = i end
      else
        res[#res+1] = {tonumber(a), tonumber(b)}
      end
    else
      res[#res + 1] = tonumber(t) or t
    end
    return res
  end

  local function decode_elem(t, flat)
    local res = {}
    t = split_args(t)
    for i = 1, #t do
      decode_range(res, t[i], flat)
    end
    if #res == 1 and type(res[1]) ~= 'table' then res = res[1] end
    return res
  end

  decode_list = function(t, flat)
    t = split_list(t)
    for i = 1, #t do
      t[i] = decode_elem(t[i], flat)
    end
    return t
  end
end

return {
  EncodeUcs2      = EncodeUcs2;
  EncodeGsm7      = EncodeGsm7;
  DecodeUcs2      = DecodeUcs2;
  DecodeGsm7      = DecodeGsm7;
  DecodeUssd      = DecodeUssd;
  IsGsm7Compat    = IsGsm7;
  EncodeSmsSubmit = EncodeSmsSubmit;
  pack_args       = pack_args;
  ts2date         = ts2date;
  date2ts         = date2ts;
  ocall           = ocall;
  split_args      = split_args;
  split_list      = split_list;
  decode_list     = decode_list;
  next_reference  = next_reference;
  reset_reference = reset_reference;
}
