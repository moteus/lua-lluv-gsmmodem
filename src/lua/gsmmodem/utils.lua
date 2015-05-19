local tpdu  = require "tpdu"
local Bit7  = require "tpdu.bit7"
local iconv = require "iconv"

local unpack = unpack or table.unpack

-- This is not full GSM7 encode table but just ascii subset
local GSM_PAT = [=[^[ ^{}\%[~%]|@!?$_&%%#'"`,.()*+-/0123456789:;<=>ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz]*$]=]

local BASE_ENCODE = 'cp866'

local iconv_cache = setmetatable({},{__mode = k})

local function iconv_encode(from, to, str)
  local key  = from .. ':' .. to
  local conv = iconv_cache[ key ] or iconv.new(to, from)
  iconv_cache[ key ] = conv

  return conv:iconv(str)
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
  return split_len(str, len, 0x1B)
end

local function EncodeUcs2(str, len, from)
  from = from or BASE_ENCODE
  str = iconv_encode(BASE_ENCODE, 'ucs-2', str)

  return split_len(str, len * 2)
end

local function DecodeGsm7(str)
  return Bit7.Gsm2Asci(str)
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

local next_reference do
local ref = 0
next_reference = function ()
  ref = (ref + 1) % 0xFFFF
  if ref == 0 then ref = 1 end
  return ref
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
    60 * math.mod(tz * 100, 100) / 100
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
    year  = math.mod(d:getyear(), 1000),
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

return {
  EncodeUcs2      = EncodeUcs2;
  EncodeGsm7      = EncodeGsm7;
  DecodeUcs2      = DecodeUcs2;
  DecodeGsm7      = DecodeGsm7;
  EncodeSmsSubmit = EncodeSmsSubmit;
  pack_args       = pack_args;
  ts2date         = ts2date;
  date2ts         = date2ts;
  ocall           = ocall;
}
