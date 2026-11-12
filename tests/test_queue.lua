return {
  files = { "Core/Init.lua", "Core/Util.lua", "Comm/Queue.lua" },
  tests = {
    burst_then_rate = function(ns, A)
      local now = 0
      local q = ns.Queue.new({ perSecond = 2, burst = 4, now = function() return now end })
      for i = 1, 10 do q:push(i) end
      local sent = {}
      local function send(item) sent[#sent + 1] = item end
      A.eq(q:pump(send), 4); A.eq(sent, { 1, 2, 3, 4 })
      now = 0.5; A.eq(q:pump(send), 1)
      now = 1.0; A.eq(q:pump(send), 1)
      A.eq(q:size(), 4)
      now = 10; A.eq(q:pump(send), 4) -- bucket capped at 4, not 16
      A.eq(q:size(), 0)
      A.eq(sent, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
    end,
    hold_blocks_until_released = function(ns, A)
      local q = ns.Queue.new({ perSecond = 2, burst = 4, now = function() return 0 end })
      q:hold(true); q:push("a"); q:push("b")
      A.eq(q:pump(function() end), 0); A.eq(q:size(), 2)
      q:hold(false)
      A.eq(q:pump(function() end), 2); A.eq(q:size(), 0)
    end,
    failed_send_keeps_item = function(ns, A)
      local q = ns.Queue.new({ perSecond = 2, burst = 4, now = function() return 0 end })
      q:push("a"); q:push("b")
      local seen = {}
      A.eq(q:pump(function(item) seen[#seen + 1] = item; return false end), 0)
      A.eq(q:size(), 2); A.eq(seen, { "a" })
      local got = {}
      A.eq(q:pump(function(item) got[#got + 1] = item end), 2)
      A.eq(got, { "a", "b" })
    end,
    failed_send_does_not_consume_token = function(ns, A)
      local q = ns.Queue.new({ perSecond = 2, burst = 4, now = function() return 0 end })
      for i = 1, 4 do q:push(i) end
      for _ = 1, 10 do q:pump(function() return false end) end
      A.eq(q:pump(function() end), 4)
    end,
    rate_never_exceeded_under_burst = function(ns, A)
      local now = 0
      local q = ns.Queue.new({ perSecond = 2, burst = 4, now = function() return now end })
      for i = 1, 12 do q:push(i) end
      local times = {}
      for step = 0, 100 do
        now = step * 0.1
        q:pump(function() times[#times + 1] = now end)
      end
      A.eq(#times, 12)
      A.ok(times[12] <= 4.5, "all sent by 4.5, last at " .. times[12])
      for i = 1, #times do
        local n = 0
        for j = i, #times do if times[j] < times[i] + 1 then n = n + 1 end end
        A.ok(n <= 2 + 4, "window at " .. times[i] .. " has " .. n)
      end
    end,
    replace_swaps_a_waiting_item_with_the_same_key = function(ns, A)
      local q = ns.Queue.new({ perSecond = 2, burst = 4, now = function() return 0 end })
      local party, raid = {}, {}
      q:push({ text = "other", dest = party })
      q:replace("POS", { text = "old", dest = party })
      q:replace("POS", { text = "new", dest = party })
      q:replace("POS", { text = "raid", dest = raid })
      A.eq(q:size(), 3, "one waiting position per destination")
      local got = {}
      q:pump(function(item) got[#got + 1] = item.text end)
      A.eq(got, { "other", "new", "raid" })
      q:replace("POS", { text = "after", dest = party })
      A.eq(q:size(), 1, "once sent, a new one is pushed")
    end,
    supersede_drops_waiting_ones_and_goes_to_the_back = function(ns, A)
      local q = ns.Queue.new({ perSecond = 2, burst = 4, now = function() return 0 end })
      local function same(a, b) return a.to == b.to end
      q:supersede("C", { text = "c1", dest = { to = "a" } }, same)
      q:supersede("C", { text = "c1", dest = { to = "b" } }, same)
      q:push({ text = "vote", dest = { to = "a" } })
      q:supersede("C", { text = "c2", dest = { to = "a" } }, same) -- equal by value, not the same table
      A.eq(q:size(), 3, "one waiting card per destination")
      local got = {}
      q:pump(function(item) got[#got + 1] = item.text .. item.dest.to end)
      A.eq(got, { "c1b", "votea", "c2a" }, "the newest card goes after what was queued before it")
    end,
    bulk_waits_behind_normal = function(ns, A)
      local q = ns.Queue.new({ perSecond = 2, burst = 4, now = function() return 0 end })
      q:push("b1", true); q:push("b2", true); q:push("b3", true)
      q:push("live")
      A.eq(q:size(), 4)
      local got = {}
      q:pump(function(item) got[#got + 1] = item end)
      A.eq(got, { "live", "b1", "b2", "b3" }, "the normal one leaves first, bulk keeps its own order")
      A.eq(q:size(), 0)
    end,
    live_item_overtakes_waiting_bulk = function(ns, A)
      local now = 0
      local q = ns.Queue.new({ perSecond = 2, burst = 1, now = function() return now end })
      q:push("b1", true); q:push("b2", true)
      local got = {}
      local function send(item) got[#got + 1] = item end
      q:pump(send)
      q:push("live")
      now = 1
      q:pump(send)
      A.eq(got, { "b1", "live" })
      now = 2
      q:pump(send)
      A.eq(got, { "b1", "live", "b2" })
    end,
    replace_and_supersede_stay_in_their_lane = function(ns, A)
      local q = ns.Queue.new({ perSecond = 2, burst = 4, now = function() return 0 end })
      local dest = {}
      q:replace("k", { text = "bulk1", dest = dest }, true)
      q:replace("k", { text = "live1", dest = dest })
      q:replace("k", { text = "bulk2", dest = dest }, true)
      q:replace("k", { text = "live2", dest = dest })
      A.eq(q:size(), 2)
      q:supersede("s", { text = "sb1", dest = dest }, function(a, b) return a == b end, true)
      q:supersede("s", { text = "sl1", dest = dest }, function(a, b) return a == b end)
      q:supersede("s", { text = "sb2", dest = dest }, function(a, b) return a == b end, true)
      q:supersede("s", { text = "sl2", dest = dest }, function(a, b) return a == b end)
      local got = {}
      q:pump(function(item) got[#got + 1] = item.text end)
      A.eq(got, { "live2", "sl2", "bulk2", "sb2" })
    end,
  },
}
