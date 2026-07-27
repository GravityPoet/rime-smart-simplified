-- 场景模式调序：聊天/写作/代码模式按需提升不同类型候选。
-- 默认模式下不改变排序；用户通过方案菜单启用。

local M = {}

-- 与 context_boost_filter 相同的物化上限：重排需要缓存候选，
-- 但绝不强制展开整条惰性流；超出上限的候选保持流式原序输出。
local REORDER_CAP = 100

local function utf8_len(text)
  if utf8 and utf8.len then return utf8.len(text) or #text end
  return #text
end

local function has_non_ascii(text)
  for i = 1, #text do
    if text:byte(i) > 127 then return true end
  end
  return false
end

local function is_ascii_like(text)
  return text:match("^[%w%._%-%+/#@]+$") ~= nil
end

local function is_emoji_codepoint(cp)
  return (cp >= 0x1F000 and cp <= 0x1FAFF)
    or (cp >= 0x2600 and cp <= 0x27BF)
    or cp == 0xFE0F
end

-- 仅按码点判定 emoji；普通短中文词（如「你好」）不得被当作表情提升。
local function is_emoji_like(text)
  if not has_non_ascii(text) or utf8_len(text) > 4 then return false end
  if not (utf8 and utf8.codes) then
    -- 兜底：常见 emoji 位于四字节区，中文常用字是三字节。
    return text:find("[\240-\244]") ~= nil
  end
  local ok, hit = pcall(function()
    for _, cp in utf8.codes(text) do
      if is_emoji_codepoint(cp) then return true end
    end
    return false
  end)
  return ok and hit
end

local function is_long_chinese(text)
  return has_non_ascii(text) and not text:match("[%w]") and utf8_len(text) >= 4
end

local function pass(input)
  for cand in input:iter() do yield(cand) end
end

-- 预测联想段每次上屏后触发；场景重排对预测候选收益低而成本每次都付，
-- 预测段一律走零开销直通（与 context_boost_filter 同策略）。
local function in_prediction_segment(context)
  local ok, hit = pcall(function()
    local composition = context.composition
    if not composition or composition:empty() then return false end
    local seg = composition:back()
    return seg and seg:has_tag("prediction") or false
  end)
  return ok and hit
end

local function yield_unique(list, yielded)
  for _, cand in ipairs(list) do
    local text = cand.text
    if not yielded[text] then
      yielded[text] = true
      yield(cand)
    end
  end
end

function M.func(input, env)
  local context = env.engine.context
  local code_mode = context:get_option("smart_code")
  local write_mode = context:get_option("smart_write")
  local chat_mode = context:get_option("smart_chat")
  if not (code_mode or write_mode or chat_mode) or in_prediction_segment(context) then
    pass(input)
    return
  end

  -- 只物化前 REORDER_CAP 个候选参与重排；之后的候选保持流式输出，
  -- 避免万象语法在长句下被迫展开几百上千个候选造成卡顿。
  local iter = input:iter()
  local cands = {}
  local overflow_cand = nil
  for cand in iter do
    cands[#cands + 1] = cand
    if #cands >= REORDER_CAP then
      overflow_cand = iter()
      break
    end
  end

  if #cands <= 1 then
    yield_unique(cands, {})
    return
  end

  local primary = {}
  local boosted = {}
  local rest = {}
  -- 互斥 options 是主防线；这里保留确定性优先级，兼容升级前可能遗留的
  -- 多个 true 状态，避免不同模式的提升规则混在一起。
  local active_mode = code_mode and "code" or (write_mode and "write" or "chat")

  for i, cand in ipairs(cands) do
    local text = cand.text or ""
    local hit = false
    if active_mode == "code" then hit = is_ascii_like(text) end
    if active_mode == "write" then hit = is_long_chinese(text) end
    if active_mode == "chat" then hit = is_emoji_like(text) end

    if active_mode == "code" then
      if hit then table.insert(boosted, cand) else table.insert(rest, cand) end
    else
      if i == 1 then
        table.insert(primary, cand)
      elseif hit then
        table.insert(boosted, cand)
      else
        table.insert(rest, cand)
      end
    end
  end

  local yielded = {}
  yield_unique(primary, yielded)
  yield_unique(boosted, yielded)
  yield_unique(rest, yielded)

  if overflow_cand then
    repeat
      local text = overflow_cand.text
      if not text or text == "" or not yielded[text] then
        if text and text ~= "" then yielded[text] = true end
        yield(overflow_cand)
      end
      overflow_cand = iter()
    until not overflow_cand
  end
end

return M
