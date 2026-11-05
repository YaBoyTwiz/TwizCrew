return {
  files = { "Core/Init.lua", "Core/Util.lua", "Comm/Codec.lua" },
  tests = {
    roundtrip_escapes_separators = function(ns, A)
      local f = { st = "50% off ^_^ a~b c=d |Tx|t", zn = "Elwynn Forest", lv = "14" }
      local out = ns.Codec.encode("STATE", f); A.eq(#out, 1)
      A.eq(ns.Codec.decode(out[1]), { protocol = 1, type = "STATE", fields = f })
    end,
    updreq_roundtrip = function(ns, A)
      local out = ns.Codec.encode("UPDREQ", { ver = "0.2.10", rs = "0.2.0" })
      A.eq(out, { "1^UPDREQ^rs=0.2.0~ver=0.2.10" })
      A.eq(ns.Codec.decode(out[1]), { protocol = 1, type = "UPDREQ", fields = { ver = "0.2.10", rs = "0.2.0" } })
    end,
    encode_is_stable = function(ns, A)
      A.eq(ns.Codec.encode("PING", {})[1], "1^PING^")
      A.eq(ns.Codec.encode("STATE", { b = "2", a = "1" })[1], "1^STATE^a=1~b=2")
    end,
    layer_fields_lead_the_first_chunk = function(ns, A)
      A.eq(ns.Codec.encode("STATE", { b = "2", lk = "111", a = "1", zn = "Elwynn", ins = "0" })[1],
        "1^STATE^zn=Elwynn~ins=0~lk=111~a=1~b=2")
      local f = { st = string.rep("x", 40), zn = string.rep("Z", 120), sz = string.rep("S", 120), cl = "MAGE",
        lk = "111", ins = "0", xp = "50", lv = "12", tg = "AFK", ver = "0.1.0" }
      local out = ns.Codec.encode("STATE", f)
      A.ok(#out >= 2)
      local first = ns.Codec.decode(out[1]).fields
      A.eq(first.zn, f.zn); A.eq(first.ins, "0"); A.eq(first.lk, "111")
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
      local zn
      for _, s in ipairs(out) do zn = zn or ns.Codec.decode(s).fields.zn end
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
    stats_pieces_keep_type_and_repeat_keys = function(ns, A)
      local f = { sid = "Holyb\195\184i-Realm-1700000000", q = "1700000000-1" }
      local keys = { "dt", "df", "dd", "dw", "db", "ld", "pl", "wp", "af", "ds", "st", "mt", "sw", "jp", "hs", "jk",
        "rp", "qa", "dl", "dv", "rz", "pt" }
      for i, k in ipairs(keys) do
        f["s_" .. k] = tostring(100000 + i); f["a_" .. k] = tostring(123456789 + i)
      end
      local out = ns.Codec.encode("STATS", f, { repeatKeys = { "sid", "q", "off" } })
      A.ok(#out >= 2)
      local merged = {}
      for _, s in ipairs(out) do
        A.ok(#s <= 255)
        local m = ns.Codec.decode(s)
        A.eq(m.type, "STATS"); A.eq(m.fields.sid, f.sid); A.eq(m.fields.q, f.q)
        for k, v in pairs(m.fields) do merged[k] = v end
      end
      A.eq(merged, f)
    end,
    session_fields_follow_layer_fields = function(ns, A)
      A.eq(ns.Codec.encode("STATE", { a = "1", sst = "5m", sid = "T-5", lk = "1", zn = "Z" })[1],
        "1^STATE^zn=Z~lk=1~sid=T-5~sst=5m~a=1")
    end,
    new_types_decode = function(ns, A)
      for _, t in ipairs({ "STATS", "STATSREQ", "ROAST" }) do A.eq(ns.Codec.decode("1^" .. t .. "^").type, t) end
    end,
    numbers_are_never_cut = function(ns, A)
      local out = ns.Codec.encode("STATS", { sid = "T-1", st = string.rep("x", 300), s_dt = "12345" },
        { repeatKeys = { "sid" } })
      local found = false
      for _, s in ipairs(out) do
        A.ok(#s <= 255)
        local m = ns.Codec.decode(s)
        if m.fields.s_dt == "12345" then found = true end
      end
      A.ok(found)
    end,
  },
}
