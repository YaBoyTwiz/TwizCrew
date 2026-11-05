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
  },
}
