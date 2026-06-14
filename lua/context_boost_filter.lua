-- 本地上下文调序：学习最近 1/2/3 段上屏文本 -> 下一段候选的稳定搭配。
-- 只提升已经存在的候选，不联网、不生成新词，避免云输入式隐私风险。
-- 性能：重排只物化前 REORDER_CAP 个候选；保存节流；加载时清理长期未用的一次性记录。

local M = {}

local DATA_FILE = "context_boost.tsv"
local K = 8
local MAX_TEXT_LEN = 24
local MIN_COUNT = 2
local HISTORY_LIMIT = 3
local CONTEXT_SEP = " > "
local REORDER_CAP = 100
local SAVE_PENDING_MAX = 3
local SAVE_INTERVAL = 30
local PRUNE_AGE_SECONDS = 90 * 86400  -- 超过 90 天未再出现且未达 MIN_COUNT 的记录，加载时丢弃

local data_path
local map = {}
local history = {}
local pending_saves = 0
local last_save_time = 0

local function split_tab(line)
  local t = {}
  for s in string.gmatch(line, "([^\t]+)") do
    t[#t + 1] = s
  end
  return t
end

local function clean_text(text)
  if not text then return nil end
  text = tostring(text):gsub("[%c\t]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  if utf8 and utf8.len and utf8.len(text) and utf8.len(text) > MAX_TEXT_LEN then return nil end
  return text
end

local function is_ascii(text)
  for i = 1, #text do
    if text:byte(i) > 127 then return false end
  end
  return true
end

local function learnable(text)
  text = clean_text(text)
  if not text then return nil end
  if text:match("^%p+$") then return nil end
  if is_ascii(text) and #text <= 2 then return nil end
  return text
end

local function parse_item(col)
  local count, last, text = col:match("^(%d+):(%d+):(.*)$")
  if not text or text == "" then return nil end
  return { text = text, count = tonumber(count) or 1, last = tonumber(last) or 0 }
end

local function sort_items(arr)
  table.sort(arr, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.last ~= b.last then return a.last > b.last end
    return a.text < b.text
  end)
end

local function trim_items(arr)
  sort_items(arr)
  while #arr > K do table.remove(arr) end
end

local function is_stale(item, now)
  return item.count < MIN_COUNT
    and item.last > 0
    and (now - item.last) > PRUNE_AGE_SECONDS
end

local function load_map()
  map = {}
  local f = io.open(data_path, "r")
  if not f then return end
  local now = os.time()
  for line in f:lines() do
    local cols = split_tab(line)
    local prev = cols[1]
    if prev and prev ~= "" then
      local arr = {}
      for i = 2, #cols do
        local item = parse_item(cols[i])
        if item and not is_stale(item, now) then arr[#arr + 1] = item end
      end
      if #arr > 0 then
        trim_items(arr)
        map[prev] = arr
      end
    end
  end
  f:close()
end

local function save_map()
  local tmp_path = data_path .. ".tmp"
  local f = io.open(tmp_path, "w")
  if not f then return end
  for prev, arr in pairs(map) do
    if arr and #arr > 0 then
      trim_items(arr)
      f:write(prev)
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

local function record_pair(prev, text)
  if not map[prev] then map[prev] = {} end
  local arr = map[prev]
  local now = os.time()
  for i = 1, #arr do
    if arr[i].text == text then
      arr[i].count = arr[i].count + 1
      arr[i].last = now
      trim_items(arr)
      return
    end
  end
  arr[#arr + 1] = { text = text, count = 1, last = now }
  trim_items(arr)
end

local function make_context_key(count)
  if #history < count then return nil end
  local parts = {}
  for i = #history - count + 1, #history do
    parts[#parts + 1] = history[i]
  end
  return "@" .. count .. ":" .. table.concat(parts, CONTEXT_SEP)
end

local function push_history(text)
  history[#history + 1] = text
  while #history > HISTORY_LIMIT do
    table.remove(history, 1)
  end
end

local function pass_through(input)
  for cand in input:iter() do yield(cand) end
end

local function is_new_text(cand, yielded)
  local text = cand and cand.text
  if not text or text == "" then return true end
  if yielded[text] then return false end
  yielded[text] = true
  return true
end

function M.init(env)
  data_path = rime_api.get_user_data_dir() .. "/" .. DATA_FILE
  load_map()

  env.engine.context.commit_notifier:connect(function(ctx)
    local text = learnable(ctx:get_commit_text())
    if not text then return end
    if #history >= 1 and history[#history] == text then return end

    local changed = false
    if #history >= 1 then
      record_pair(history[#history], text)
      changed = true
    end
    for count = 2, HISTORY_LIMIT do
      local key = make_context_key(count)
      if key then
        record_pair(key, text)
        changed = true
      end
    end

    if changed then
      pending_saves = pending_saves + 1
      maybe_save(false)
    end
    push_history(text)
  end)
end

function M.fini(env)
  maybe_save(true)
end

local function collect_boosted()
  local keys = {}
  for count = HISTORY_LIMIT, 2, -1 do
    local key = make_context_key(count)
    if key then keys[#keys + 1] = key end
  end
  if #history >= 1 then
    keys[#keys + 1] = history[#history]
  end

  local boosted = {}
  local seen = {}
  for _, key in ipairs(keys) do
    local arr = map[key]
    if arr then
      local eligible = {}
      for i = 1, #arr do
        if arr[i].count >= MIN_COUNT and not seen[arr[i].text] then
          eligible[#eligible + 1] = arr[i]
          seen[arr[i].text] = true
        end
      end
      sort_items(eligible)
      for i = 1, #eligible do
        boosted[#boosted + 1] = eligible[i]
      end
    end
  end

  return boosted
end

function M.func(input, env)
  local context = env.engine.context
  if not context:get_option("smart_context") then
    pass_through(input)
    return
  end

  local boosted = collect_boosted()
  if #boosted == 0 then
    pass_through(input)
    return
  end

  -- 只物化前 REORDER_CAP 个候选参与重排，之后的候选保持流式输出
  local cache = {}
  local flushed = false
  local yielded = {}

  local function flush_cache()
    local used = {}
    for i = 1, #boosted do
      for j = 1, #cache do
        if not used[j] and cache[j].text == boosted[i].text then
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
