-- rq/RQ 日期首选：只把 YYYY-MM-DD 格式提到第一位，其他候选保持原顺序。

local M = {}

local function pass(input)
  for cand in input:iter() do yield(cand) end
end

local function is_rq(code)
  return code and string.lower(code:gsub("%s+", "")) == "rq"
end

local function is_iso_date(text)
  return text and text:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

function M.func(input, env)
  local context = env.engine.context
  if not is_rq(context.input or "") then
    pass(input)
    return
  end

  local target = nil
  local rest = {}
  for cand in input:iter() do
    if not target and is_iso_date(cand.text or "") then
      target = cand
    else
      rest[#rest + 1] = cand
    end
  end

  if target then yield(target) end
  for i = 1, #rest do yield(rest[i]) end
end

return M
