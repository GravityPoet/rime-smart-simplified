-- 场景模式调序：聊天/写作/代码模式按需提升不同类型候选。
-- 默认模式下不改变排序；用户通过方案菜单启用。

local M = {}

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

local function is_emoji_like(text)
  return utf8_len(text) <= 4 and has_non_ascii(text) and not text:match("[%w%s]")
end

local function is_long_chinese(text)
  return has_non_ascii(text) and not text:match("[%w]") and utf8_len(text) >= 4
end

local function pass(input)
  for cand in input:iter() do yield(cand) end
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
  if not (code_mode or write_mode or chat_mode) then
    pass(input)
    return
  end

  local cands = {}
  for cand in input:iter() do cands[#cands + 1] = cand end
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
end

return M
