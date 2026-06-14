
local M = {}
local BASE_QUALITY = 100000

local MAP = {
  gh = { "GitHub" },
  ai = { "AI", "AGI", "AIGC" },
  rime = { "Rime", "Squirrel", "Weasel" },
}

function M.func(input, seg, env)
  local arr = MAP[input]
  if not arr then return end
  for i = 1, #arr do
    local cand = Candidate("abbrev", seg.start, seg._end, arr[i], "")
    cand.quality = BASE_QUALITY - i
    yield(cand)
  end
end

return M
