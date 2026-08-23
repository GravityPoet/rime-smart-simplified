-- 本地上下文调序：学习最近 1/2/3 段上屏文本 -> 下一段候选的稳定搭配。
-- 只提升已经存在的候选，不联网、不生成新词，避免云输入式隐私风险。
-- 持久化使用“小型增量日志 + 周期性原子压缩”，避免频繁重写整个学习库。

local M = {}

local DATA_FILE = "context_boost.tsv"
local JOURNAL_FILE = "context_boost.journal.tsv"
local MIGRATION_BACKUP_SUFFIX = ".bak.pre-journal-v2"
local BOOST_LIMIT_PER_CONTEXT = 8
local MAX_TEXT_LEN = 24
local MIN_COUNT = 2
local HISTORY_LIMIT = 3
local CONTEXT_SEP = " > "
-- 只读取前一小段候选。Lua filter 的迭代器是惰性的，若在无提升记录时
-- 把整条流读完，会迫使万象语法把几百/几千个候选全部算出，造成明显卡顿。
-- 100 个候选可覆盖约 11 页常用长尾，同时给上下文排序留足命中空间。
local REORDER_CAP = 100
local SAVE_PENDING_MAX = 3
local SAVE_INTERVAL = 30
local SESSION_GAP_SECONDS = 5 * 60
local JOURNAL_COMPACT_ROWS = 2048
local JOURNAL_COMPACT_BYTES = 256 * 1024
local CONTEXT_WEIGHTS = { [1] = 1.0, [2] = 2.25, [3] = 4.0 }
local SESSION_TOUCH_BONUS = 0.75
local LOG_2 = math.log(2)

local data_path
local journal_path
local map = {}
local dirty_keys = {}
local pending_saves = 0
local last_save_time = 0
local journal_rows = 0
local has_malformed_records = false
local active_instances = 0
local active_user_dir

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
  count = tonumber(count)
  last = tonumber(last)
  if not text or text == "" or not count or count < 1 or not last or last < 0 then return nil end
  return { text = text, count = count, last = last }
end

local function sort_items(arr)
  table.sort(arr, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.last ~= b.last then return a.last > b.last end
    return a.text < b.text
  end)
end

local function recent_bonus(last, now)
  if not last or last <= 0 then return 0 end
  local age = math.max(0, now - last)
  if age <= 10 * 60 then return 0.75 end
  if age <= 60 * 60 then return 0.60 end
  if age <= 24 * 60 * 60 then return 0.40 end
  if age <= 7 * 24 * 60 * 60 then return 0.25 end
  if age <= 30 * 24 * 60 * 60 then return 0.10 end
  return 0
end

local function evidence_score(item, touched, now)
  local score = math.log(item.count + 1) / LOG_2 + recent_bonus(item.last, now)
  if touched then score = score + SESSION_TOUCH_BONUS end
  return score
end

local function parse_line(line)
  local cols = split_tab((line or ""):gsub("\r$", ""))
  local key = cols[1]
  if not key or key == "" then return nil, nil, true end

  local arr = {}
  local malformed = false
  for i = 2, #cols do
    local item = parse_item(cols[i])
    if item then
      arr[#arr + 1] = item
    else
      malformed = true
    end
  end
  if #arr == 0 then return nil, nil, true end
  sort_items(arr)
  return key, arr, malformed
end

local function valid_item_column(col)
  local count, last, text = col:match("^(%d+):(%d+):(.*)$")
  count = tonumber(count)
  last = tonumber(last)
  return text ~= nil and text ~= "" and count ~= nil and count >= 1 and last ~= nil and last >= 0
end

local function parse_compact_line(line)
  line = (line or ""):gsub("\r$", "")
  local key, payload = line:match("^([^\t]+)\t(.+)$")
  if not key or not payload then return nil, nil, true end

  local valid = 0
  local malformed = false
  for col in payload:gmatch("([^\t]+)") do
    if valid_item_column(col) then
      valid = valid + 1
    else
      malformed = true
    end
  end
  if valid == 0 then return nil, nil, true end
  return key, payload, malformed
end

local function parse_payload(payload)
  local arr = {}
  for col in (payload or ""):gmatch("([^\t]+)") do
    local item = parse_item(col)
    if item then arr[#arr + 1] = item end
  end
  sort_items(arr)
  return arr
end

local function load_file(path, target)
  local f = io.open(path, "r")
  if not f then return 0, 0, false end
  local rows = 0
  local malformed = 0
  for line in f:lines() do
    local key, arr, bad = parse_line(line)
    if key and arr then
      target[key] = arr
      rows = rows + 1
    end
    if bad then malformed = malformed + 1 end
  end
  f:close()
  return rows, malformed, true
end

local function load_compact_file(path, target)
  local f = io.open(path, "r")
  if not f then return 0, 0, false end
  local rows = 0
  local malformed = 0
  for line in f:lines() do
    local key, payload, bad = parse_compact_line(line)
    if key and payload then
      -- 未命中的 99%+ 上下文保持紧凑字符串；只有真正使用时才展开为 Lua 表。
      target[key] = payload
      rows = rows + 1
    end
    if bad then malformed = malformed + 1 end
  end
  f:close()
  return rows, malformed, true
end

local function resolve_items(target, key)
  local value = key and target[key]
  if type(value) == "table" then return value end
  if type(value) ~= "string" then return nil end

  local arr = parse_payload(value)
  target[key] = arr
  return arr
end

local function sorted_keys(target)
  local keys = {}
  for key, value in pairs(target) do
    if value == true or type(value) == "string" or (type(value) == "table" and #value > 0) then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  return keys
end

local function write_record(f, key, arr)
  if type(arr) == "string" then
    return f:write(key, "\t", arr, "\n") ~= nil
  end
  sort_items(arr)
  if not f:write(key) then return false end
  for i = 1, #arr do
    local item = arr[i]
    if not f:write("\t", item.count, ":", item.last, ":", item.text) then return false end
  end
  return f:write("\n") ~= nil
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function replace_file(source, destination)
  -- POSIX rename replaces atomically. Some Windows runtimes reject replacing
  -- an existing destination, so fall back to a recoverable two-rename swap.
  if os.rename(source, destination) then return true end
  if not file_exists(destination) then return false end

  local previous = destination .. ".replace-backup"
  os.remove(previous)
  if not os.rename(destination, previous) then return false end
  if os.rename(source, destination) then
    os.remove(previous)
    return true
  end
  os.rename(previous, destination)
  return false
end

local function recover_interrupted_replace(path)
  local previous = path .. ".replace-backup"
  if file_exists(path) then
    if file_exists(previous) then os.remove(previous) end
  elseif file_exists(previous) then
    os.rename(previous, path)
  end
end

local function write_snapshot(path, target)
  local tmp_path = path .. ".tmp"
  local f = io.open(tmp_path, "w")
  if not f then return false end

  local ok = true
  local keys = sorted_keys(target)
  for i = 1, #keys do
    local key = keys[i]
    if not write_record(f, key, target[key]) then
      ok = false
      break
    end
  end
  if not f:flush() then ok = false end
  if not f:close() then ok = false end

  if ok and replace_file(tmp_path, path) then return true end
  os.remove(tmp_path)
  return false
end

local function file_size(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local size = f:seek("end") or 0
  f:close()
  return size
end

local function copy_file_once(source, destination)
  if file_exists(destination) then return true end
  local input = io.open(source, "rb")
  if not input then return true end

  local tmp_path = destination .. ".tmp"
  local output = io.open(tmp_path, "wb")
  if not output then
    input:close()
    return false
  end

  local ok = true
  while true do
    local chunk = input:read(64 * 1024)
    if not chunk then break end
    if not output:write(chunk) then
      ok = false
      break
    end
  end
  input:close()
  if not output:flush() then ok = false end
  if not output:close() then ok = false end

  if ok and os.rename(tmp_path, destination) then return true end
  os.remove(tmp_path)
  return false
end

local function ensure_migration_backup()
  if not copy_file_once(data_path, data_path .. MIGRATION_BACKUP_SUFFIX) then return false end
  if not copy_file_once(journal_path, journal_path .. MIGRATION_BACKUP_SUFFIX) then return false end
  return true
end

local function compact_map()
  if not write_snapshot(data_path, map) then return false end
  if file_exists(journal_path) and not os.remove(journal_path) then return false end
  dirty_keys = {}
  pending_saves = 0
  journal_rows = 0
  has_malformed_records = false
  last_save_time = os.time()
  return true
end

local function append_dirty()
  local keys = sorted_keys(dirty_keys)
  if #keys == 0 then
    pending_saves = 0
    return true
  end

  local f = io.open(journal_path, "a")
  if not f then return false end
  local ok = true
  for i = 1, #keys do
    local key = keys[i]
    local arr = map[key]
    if arr and #arr > 0 and not write_record(f, key, arr) then
      ok = false
      break
    end
  end
  if not f:flush() then ok = false end
  if not f:close() then ok = false end
  if not ok then return false end

  for i = 1, #keys do dirty_keys[keys[i]] = nil end
  pending_saves = 0
  journal_rows = journal_rows + #keys
  last_save_time = os.time()
  return true
end

local function maybe_compact()
  local oversized = journal_rows >= JOURNAL_COMPACT_ROWS
    or file_size(journal_path) >= JOURNAL_COMPACT_BYTES
  if not oversized or has_malformed_records then return end
  if not ensure_migration_backup() then return end
  compact_map()
end

local function maybe_save(force)
  local now = os.time()
  if pending_saves > 0
    and (force or pending_saves >= SAVE_PENDING_MAX or (now - last_save_time) >= SAVE_INTERVAL)
  then
    if append_dirty() then maybe_compact() end
  elseif force then
    maybe_compact()
  end
end

local function load_map()
  map = {}
  dirty_keys = {}
  pending_saves = 0
  last_save_time = os.time()

  recover_interrupted_replace(data_path)

  local _, base_malformed = load_compact_file(data_path, map)
  local loaded_journal_rows, journal_malformed = load_compact_file(journal_path, map)
  journal_rows = loaded_journal_rows
  has_malformed_records = (base_malformed + journal_malformed) > 0
  maybe_compact()
end

local function mark_session_touch(touched, key, text)
  if not touched[key] then touched[key] = {} end
  touched[key][text] = true
end

local function record_pair(prev, text, now, touched)
  local arr = resolve_items(map, prev)
  if not arr then
    arr = {}
    map[prev] = arr
  end
  for i = 1, #arr do
    if arr[i].text == text then
      arr[i].count = arr[i].count + 1
      arr[i].last = now
      sort_items(arr)
      dirty_keys[prev] = true
      mark_session_touch(touched, prev, text)
      return
    end
  end
  arr[#arr + 1] = { text = text, count = 1, last = now }
  sort_items(arr)
  dirty_keys[prev] = true
  mark_session_touch(touched, prev, text)
end

local function make_context_key(source_history, count)
  if #source_history < count then return nil end
  if count == 1 then return source_history[#source_history] end
  local parts = {}
  for i = #source_history - count + 1, #source_history do
    parts[#parts + 1] = source_history[i]
  end
  return "@" .. count .. ":" .. table.concat(parts, CONTEXT_SEP)
end

local function push_history(history, text)
  history[#history + 1] = text
  while #history > HISTORY_LIMIT do
    table.remove(history, 1)
  end
end

-- 纯直通必须保持完整流式：yield 是惰性挂起，下游（分页菜单）拉多少
-- 算多少，不设上限也不会强制展开整条候选流；截断反而会让深翻页丢候选。
local function pass_through(input)
  for cand in input:iter() do
    yield(cand)
  end
end

local function is_new_text(cand, yielded)
  local text = cand and cand.text
  if not text or text == "" then return true end
  if yielded[text] then return false end
  yielded[text] = true
  return true
end

-- 预测联想段（librime-predict）在每次上屏后触发；候选顺序本就来自
-- 预测模型，重排收益低而每次上屏都要付缓存/查表成本，是打字「发粘」
-- 的来源之一。预测段一律走零开销直通。
local function in_prediction_segment(context)
  local ok, hit = pcall(function()
    local composition = context.composition
    if not composition or composition:empty() then return false end
    local seg = composition:back()
    return seg and seg:has_tag("prediction") or false
  end)
  return ok and hit
end

function M.init(env)
  local user_dir = rime_api.get_user_data_dir()
  if active_instances == 0 then
    data_path = user_dir .. "/" .. DATA_FILE
    journal_path = user_dir .. "/" .. JOURNAL_FILE
    active_user_dir = user_dir
    load_map()
  elseif active_user_dir ~= user_dir then
    error("context_boost_filter cannot serve multiple Rime user directories in one Lua runtime")
  end

  env._context_history = {}
  env._context_session_touched = {}
  env._context_last_commit_time = 0
  env._context_active = true
  active_instances = active_instances + 1

  env.commit_connection = env.engine.context.commit_notifier:connect(function(ctx)
    local text = learnable(ctx:get_commit_text())
    if not text then return end

    local now = os.time()
    local history = env._context_history
    local session_touched = env._context_session_touched
    if env._context_last_commit_time > 0 and (now - env._context_last_commit_time) > SESSION_GAP_SECONDS then
      history = {}
      session_touched = {}
      env._context_history = history
      env._context_session_touched = session_touched
    end
    env._context_last_commit_time = now

    local changed = false
    if #history >= 1 then
      record_pair(history[#history], text, now, session_touched)
      changed = true
    end
    for count = 2, HISTORY_LIMIT do
      local key = make_context_key(history, count)
      if key then
        record_pair(key, text, now, session_touched)
        changed = true
      end
    end

    if changed then
      pending_saves = pending_saves + 1
      maybe_save(false)
    end
    push_history(history, text)
  end)
end

function M.fini(env)
  -- 断开通知器，避免切换方案后旧回调残留导致重复计数。
  if env and env.commit_connection then
    if env.commit_connection.disconnect then env.commit_connection:disconnect() end
    env.commit_connection = nil
  end
  maybe_save(true)
  if env and env._context_active then
    env._context_active = false
    active_instances = math.max(0, active_instances - 1)
    if active_instances == 0 then active_user_dir = nil end
  end
end

local function rank_boosted(target, source_history, touched_map, now)
  local aggregate = {}
  for depth = HISTORY_LIMIT, 1, -1 do
    local key = make_context_key(source_history, depth)
    local arr = resolve_items(target, key)
    if arr then
      local ranked = {}
      local touched_for_key = touched_map[key] or {}
      for i = 1, #arr do
        local item = arr[i]
        local touched = touched_for_key[item.text] == true
        if item.count >= MIN_COUNT or touched then
          ranked[#ranked + 1] = {
            item = item,
            evidence = evidence_score(item, touched, now),
          }
        end
      end
      table.sort(ranked, function(a, b)
        if a.evidence ~= b.evidence then return a.evidence > b.evidence end
        if a.item.count ~= b.item.count then return a.item.count > b.item.count end
        if a.item.last ~= b.item.last then return a.item.last > b.item.last end
        return a.item.text < b.item.text
      end)

      local limit = math.min(#ranked, BOOST_LIMIT_PER_CONTEXT)
      for i = 1, limit do
        local item = ranked[i].item
        local score = ranked[i].evidence * CONTEXT_WEIGHTS[depth]
        local existing = aggregate[item.text]
        if existing then
          existing.score = existing.score + score
          existing.best_depth = math.max(existing.best_depth, depth)
          existing.count = math.max(existing.count, item.count)
          existing.last = math.max(existing.last, item.last)
        else
          aggregate[item.text] = {
            text = item.text,
            score = score,
            best_depth = depth,
            count = item.count,
            last = item.last,
          }
        end
      end
    end
  end

  local boosted = {}
  for _, item in pairs(aggregate) do boosted[#boosted + 1] = item end
  table.sort(boosted, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.best_depth ~= b.best_depth then return a.best_depth > b.best_depth end
    if a.count ~= b.count then return a.count > b.count end
    if a.last ~= b.last then return a.last > b.last end
    return a.text < b.text
  end)
  return boosted
end

local function collect_boosted(source_history, touched)
  return rank_boosted(map, source_history, touched, os.time())
end

function M.func(input, env)
  local context = env.engine.context
  if not context:get_option("smart_context") or in_prediction_segment(context) then
    pass_through(input)
    return
  end

  local boosted = collect_boosted(env._context_history or {}, env._context_session_touched or {})
  if #boosted == 0 then
    pass_through(input)
    return
  end

  local cache = {}
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

  -- 只物化前 REORDER_CAP 个候选参与重排；之后的候选保持流式输出，
  -- 深翻页仍能拿到完整候选流。
  local flushed = false
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

M._test = {
  load_compact_file = load_compact_file,
  load_file = load_file,
  parse_line = parse_line,
  rank_boosted = rank_boosted,
  recent_bonus = recent_bonus,
  resolve_items = resolve_items,
  write_snapshot = write_snapshot,
}

return M
