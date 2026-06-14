-- lua/pin_by_select.lua
-- 计数式软置顶：同一输入码的候选被稳定选择多次后，才参与重排。
-- 避免一次误选就永久置顶；旧的 pin_by_select.tsv 保留，新数据写入 v2。
-- 性能：重排只物化前 REORDER_CAP 个候选，其余保持流式；保存做节流，fini 兜底落盘。

local M = {}
local data_path
local map = {}        -- code -> {{ text = "...", count = n, last = epoch }, ...}
local DATA_FILE = "pin_by_select_v2.tsv"
local DEFAULT_KEEP = 8
local SHORT_CODE_KEEP = 24
local SINGLE_CODE_KEEP = 32
local MAX_CODE_LENGTH = 12
local REORDER_CAP = 100      -- 参与重排的候选上限，命中之外的候选不再强制枚举
local SAVE_PENDING_MAX = 3   -- 积累 N 次选择后落盘
local SAVE_INTERVAL = 30     -- 或距上次落盘超过 N 秒后落盘
local pending_saves = 0
local last_save_time = 0
local BYPASS_CODES = {
  uuid = true,  -- 让 uuid 动态候选保持原始顺序（不受置顶记忆影响）
  rq = true,    -- 日期
  sj = true,    -- 时间
  xq = true,    -- 星期
  dt = true,    -- 日期时间
  ts = true,    -- 时间戳
  nl = true,    -- 农历
}
local UUID_KEEP_LIMIT = 5
local UUID_TEXT_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89aAbB]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
local UUID_TEXT_LITERAL = "UUID"

local function split_tab(line)
  local t = {}
  for s in string.gmatch(line, "([^\t]+)") do
    t[#t+1] = s
  end
  return t
end

local function is_ascii(text)
  if not text then return false end
  for i = 1, #text do
    if text:byte(i) > 127 then return false end
  end
  return true
end

local function threshold_for(code, text)
  local n
  if #code <= 2 then
    n = 4
  elseif #code <= 4 then
    n = 3
  else
    n = 2
  end
  if is_ascii(text) then n = n + 1 end
  return n
end

local function is_learnable_code(code)
  if not code or code == "" then return false end
  if #code > MAX_CODE_LENGTH then return false end
  local lower = string.lower(code)
  if BYPASS_CODES[lower] then return false end
  return lower:match("^[%w']+$") ~= nil
end

local function is_learnable_text(code, text)
  if not text or text == "" then return false end
  if is_ascii(text) and text == code then return false end
  return true
end

local function parse_item(col)
  local count, last, text = col:match("^(%d+):(%d+):(.*)$")
  if text then
    return { text = text, count = tonumber(count) or 1, last = tonumber(last) or 0 }
  end
  return { text = col, count = 1, last = 0 }
end

local function sort_items(arr)
  table.sort(arr, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.last ~= b.last then return a.last > b.last end
    return a.text < b.text
  end)
end

local function keep_limit_for(code)
  if not code then return DEFAULT_KEEP end
  if #code <= 1 then return SINGLE_CODE_KEEP end
  if #code <= 2 then return SHORT_CODE_KEEP end
  return DEFAULT_KEEP
end

local function trim_items(arr, code, preserve_text)
  sort_items(arr)
  local keep = keep_limit_for(code)
  while #arr > keep do
    if preserve_text and arr[#arr] and arr[#arr].text == preserve_text then
      local removed = false
      for i = #arr - 1, 1, -1 do
        if arr[i].text ~= preserve_text then
          table.remove(arr, i)
          removed = true
          break
        end
      end
      if not removed then table.remove(arr) end
    else
      table.remove(arr)
    end
  end
end

local function load_map()
  map = {}
  local f = io.open(data_path, "r")
  if not f then return end
  for line in f:lines() do
    if line ~= "" then
      local cols = split_tab(line)
      local code = cols[1]
      if code and code ~= "" then
        map[code] = {}
        for i = 2, #cols do
          if cols[i] and cols[i] ~= "" then
            map[code][#map[code]+1] = parse_item(cols[i])
          end
        end
        trim_items(map[code], code)
      end
    end
  end
  f:close()
end

local function save_map()
  local tmp_path = data_path .. ".tmp"
  local f = io.open(tmp_path, "w")
  if not f then return end
  for code, arr in pairs(map) do
    if arr and #arr > 0 then
      trim_items(arr, code)
      f:write(code)
      for i = 1, #arr do
        local item = arr[i]
        f:write("\t", item.count, ":", item.last, ":", item.text)
      end
      f:write("\n")
    end
  end
  f:close()
  os.rename(tmp_path, data_path)
end

local function maybe_save(force)
  if pending_saves == 0 then return end
  local now = os.time()
  if force or pending_saves >= SAVE_PENDING_MAX or (now - last_save_time) >= SAVE_INTERVAL then
    save_map()
    pending_saves = 0
    last_save_time = now
  end
end

local function record_selection(code, text)
  if not map[code] then map[code] = {} end
  local arr = map[code]
  local now = os.time()

  for i = 1, #arr do
    local item = arr[i]
    if type(item) == "string" then
      item = { text = item, count = 1, last = 0 }
      arr[i] = item
    end
    if item.text == text then
      item.count = item.count + 1
      item.last = now
      trim_items(arr, code, text)
      return
    end
  end

  arr[#arr+1] = { text = text, count = 1, last = now }
  trim_items(arr, code, text)
end

local function is_uuid_text(text)
  if not text or text == "" then return false end
  return text:match(UUID_TEXT_PATTERN) ~= nil
end

local function is_uuid_allowed_text(text)
  if not text or text == "" then return false end
  if text == UUID_TEXT_LITERAL then return true end
  return is_uuid_text(text)
end

local function is_new_text(cand, yielded)
  local text = cand and cand.text
  if not text or text == "" then return true end
  if yielded[text] then return false end
  yielded[text] = true
  return true
end

function M.init(env)
  local dir = rime_api.get_user_data_dir()
  data_path = dir .. "/" .. DATA_FILE
  load_map()

  env.engine.context.commit_notifier:connect(function(ctx)
    local code = ctx.input
    if not is_learnable_code(code) then return end

    local text = ctx:get_commit_text()
    if not is_learnable_text(code, text) then return end

    record_selection(code, text)
    pending_saves = pending_saves + 1
    maybe_save(false)
  end)
end

function M.fini(env)
  maybe_save(true)
end

function M.func(input, env)
  local code = env.engine.context.input
  local lower_code = code and string.lower(code)

  -- uuid 模式下只保留 UUID 候选，屏蔽 UUID 英文释义等文本
  if lower_code == "uuid" then
    local kept = 0
    local yielded = {}
    for cand in input:iter() do
      if is_uuid_allowed_text(cand.text) and is_new_text(cand, yielded) then
        yield(cand)
        kept = kept + 1
        if kept >= UUID_KEEP_LIMIT then
          break
        end
      end
    end
    return
  end

  if lower_code and BYPASS_CODES[lower_code] then
    local yielded = {}
    for cand in input:iter() do
      if is_new_text(cand, yielded) then yield(cand) end
    end
    return
  end

  -- 先判定是否有可用的学习记录；没有就纯流式直通，绝不物化候选
  local arr = code and map[code]
  local eligible = {}
  if arr then
    for i = 1, #arr do
      local item = arr[i]
      if item.count >= threshold_for(code, item.text) then
        eligible[#eligible+1] = item
      end
    end
    sort_items(eligible)
  end

  local yielded = {}
  if #eligible == 0 then
    for cand in input:iter() do
      if is_new_text(cand, yielded) then yield(cand) end
    end
    return
  end

  -- 只物化前 REORDER_CAP 个候选参与重排，之后的候选保持流式输出
  local cache = {}
  local flushed = false

  local function flush_cache()
    local used = {}
    for i = 1, #eligible do
      local target = eligible[i].text
      for j = 1, #cache do
        if (not used[j]) and cache[j].text == target then
          if is_new_text(cache[j], yielded) then yield(cache[j]) end
          used[j] = true
          break
        end
      end
    end
    for j = 1, #cache do
      if not used[j] and is_new_text(cache[j], yielded) then yield(cache[j]) end
    end
  end

  for cand in input:iter() do
    if not flushed then
      cache[#cache + 1] = cand
      if #cache >= REORDER_CAP then
        flush_cache()
        flushed = true
      end
    else
      if is_new_text(cand, yielded) then yield(cand) end
    end
  end
  if not flushed then flush_cache() end
end

return M
