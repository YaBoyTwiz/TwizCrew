return {
  files = { "Core/Init.lua", "Core/Util.lua", "Comm/Codec.lua" },
  tests = {
    roundtrip_escapes_separators = function(ns, A)
      local f = { st = "50% off ^_^ a~b c=d |Tx|t", zn = "Elwynn Forest", lv = "14" }
      local out = ns.Codec.encode("STATE", f); A.eq(#out, 1)
      A.eq(ns.Codec.decode(out[1]), { protocol = 1, type = "STATE", fields = f })
    end,
    encode_is_stable = function(ns, A)
      A.eq(ns.Codec.encode("PING", {})[1], "1^PING^")
      A.eq(ns.Codec.encode("STATE", { b = "2", a = "1" })[1], "1^STATE^a=1~b=2")
    end,
    long_state_splits_under_limit = function(ns, A)
      local f = { st = string.rep("x", 40), zn = string.rep("Z", 120), sz = string.rep("S", 120), cl = "MAGE" }
      local out = ns.Codec.encode("STATE", f); A.ok(#out >= 2)
      for _, s in ipairs(out) do A.ok(#s <= 255) end
      A.eq(ns.Codec.decode(out[1]).type, "STATE"); A.eq(ns.Codec.decode(out[2]).type, "UPDATE")
      local merged = {}
      for _, s in ipairs(out) do
        for k, v in pairs(ns.Codec.decode(s).fields) do merged[k] = v end
      end
      A.eq(merged, f)
    end,
    overlong_field_is_cut_on_letters_and_escapes = function(ns, A)
      -- every "^" costs 3 bytes escaped; "ø" is 2 bytes
      local out = ns.Codec.encode("STATE", { st = string.rep("^", 200), zn = string.rep("ø", 200) })
      for _, s in ipairs(out) do
        A.ok(#s <= 255)
        local m = ns.Codec.decode(s)
        A.ok(m)
      end
      local zn = ns.Codec.decode(out[#out]).fields.zn
      A.ok(#zn > 0 and #zn % 2 == 0)
      A.ok(string.find(zn, "^[\195\184]*$") ~= nil)
    end,
    decode_tolerates_unknown_and_garbage = function(ns, A)
      A.no(ns.Codec.decode("")); A.no(ns.Codec.decode("hello")); A.no(ns.Codec.decode("x^STATE^a=1"))
      A.no(ns.Codec.decode("2^NEWTHING^a=1")); A.no(ns.Codec.decode("1^NEWTHING^a=1"))
      A.eq(ns.Codec.decode("2^STATE^lv=3~zz=9~broken").fields, { lv = "3", zz = "9" })
      A.eq(select(2, ns.Codec.decode("1^NEWTHING^a=1")), "unknown type")
    end,
    decode_keeps_bad_escapes_literally = function(ns, A)
      A.eq(ns.Codec.decode("1^STATE^a=100%~b=%zz~c=%2~d=%41").fields,
        { a = "100%", b = "%zz", c = "%2", d = "%41" })
      A.eq(ns.Codec.decode("1^STATE^a=%2525").fields.a, "%25")
    end,
    decode_never_throws_on_random_bytes = function(ns, A)
      math.randomseed(12345)
      local alphabet = { "%", "^", "~", "=", "1", "2", "S", "T", "A", "E", "5", "\0", "\255", "|", "a" }
      for _ = 1, 3000 do
        local t = {}
        for i = 1, math.random(0, 40) do
          t[i] = math.random() < 0.7 and alphabet[math.random(#alphabet)] or string.char(math.random(0, 255))
        end
        local ok = pcall(ns.Codec.decode, table.concat(t))
        A.ok(ok)
      end
      A.ok(pcall(ns.Codec.decode, nil)); A.ok(pcall(ns.Codec.decode, 5))
    end,
  },
}
