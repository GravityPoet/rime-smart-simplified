-- 日期时间触发词首选：把对应的动态结果提到第一位，其他候选保持原顺序。

local M = {}

local function pass(input)
  for cand in input:iter() do yield(cand) end
end

local WEEK_TEXTS = {
  ["星期日"] = true,
  ["星期一"] = true,
  ["星期二"] = true,
  ["星期三"] = true,
  ["星期四"] = true,
  ["星期五"] = true,
  ["星期六"] = true,
}

local function preferred_matcher(code)
  code = code and string.lower(code:gsub("%s+", "")) or ""
  if code == "rq" then
    return function(text) return text:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil end
  end
  if code == "sj" then
    return function(text) return text:match("^%d%d:%d%d$") ~= nil end
  end
  if code == "xq" then
    return function(text) return WEEK_TEXTS[text] == true end
  end
  if code == "dt" then
    return function(text)
      return text:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%+08:00$") ~= nil
    end
  end
  return nil
end

function M.func(input, env)
  local context = env.engine.context
  local matches = preferred_matcher(context.input or "")
  if not matches then
    pass(input)
    return
  end

  local target = nil
  local rest = {}
  for cand in input:iter() do
    if not target and matches(cand.text or "") then
      target = cand
    else
      rest[#rest + 1] = cand
    end
  end

  if target then yield(target) end
  for i = 1, #rest do yield(rest[i]) end
end

return M
