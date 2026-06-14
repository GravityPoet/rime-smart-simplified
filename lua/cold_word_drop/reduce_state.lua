-- 可恢复软降权：Control+Shift+j 只是一段时间内的负反馈。
-- 后续持续选用会逐步削弱惩罚；到达次数或过期后恢复普通候选。

local M = {}

local DAY_SECONDS = 86400
local DEFAULT_BASE_IDX = 5
local DEFAULT_RECOVER_USES = 6
local DEFAULT_TTL_DAYS = 14
local AGE_STEP_DAYS = 7

local function now_epoch(now)
  return tonumber(now) or os.time()
end

local function as_int(value, fallback)
  local n = tonumber(value)
  if not n then return fallback end
  return math.floor(n)
end

local function normalize_record(record, now)
  now = now_epoch(now)
  if type(record) == "string" then
    return { reduced_at = now, last = now, use_count = 0 }, true
  end

  if type(record) ~= "table" then
    return nil, true
  end

  local reduced_at = as_int(record.reduced_at, as_int(record.last, now))
  local last = as_int(record.last, reduced_at)
  local use_count = as_int(record.use_count, as_int(record.count, 0))
  local changed = record.reduced_at ~= reduced_at
    or record.last ~= last
    or record.use_count ~= use_count

  if not changed then
    return record, false
  end

  return {
    reduced_at = reduced_at,
    last = last,
    use_count = use_count,
  }, changed
end

local function normalize_bucket(bucket, now)
  now = now_epoch(now)
  if type(bucket) ~= "table" then
    return nil, true
  end

  local changed = false

  if bucket[1] ~= nil then
    local normalized = {}
    for _, item in ipairs(bucket) do
      local code = item
      if type(item) == "table" then
        code = item.code or item[1]
      end
      if type(code) == "string" and code ~= "" then
        normalized[code] = { reduced_at = now, last = now, use_count = 0 }
        changed = true
      end
    end
    return normalized, changed
  end

  for code, record in pairs(bucket) do
    if type(code) == "string" and code ~= "" then
      local normalized_record, record_changed = normalize_record(record, now)
      if normalized_record then
        bucket[code] = normalized_record
      else
        bucket[code] = nil
        changed = true
      end
      changed = changed or record_changed
    else
      bucket[code] = nil
      changed = true
    end
  end

  return bucket, changed
end

function M.normalize_state(state, now)
  now = now_epoch(now)
  if type(state) ~= "table" then
    return {}, true
  end

  local changed = false
  for word, bucket in pairs(state) do
    local normalized_bucket, bucket_changed = normalize_bucket(bucket, now)
    if normalized_bucket and next(normalized_bucket) then
      state[word] = normalized_bucket
    else
      state[word] = nil
    end
    changed = changed or bucket_changed or state[word] ~= bucket
  end

  return state, changed
end

function M.is_active(record, now, recover_uses, ttl_days)
  if type(record) ~= "table" then return false end
  now = now_epoch(now)
  recover_uses = as_int(recover_uses, DEFAULT_RECOVER_USES)
  ttl_days = as_int(ttl_days, DEFAULT_TTL_DAYS)

  if as_int(record.use_count, 0) >= recover_uses then return false end

  local reduced_at = as_int(record.reduced_at, now)
  if ttl_days > 0 and now - reduced_at >= ttl_days * DAY_SECONDS then
    return false
  end

  return true
end

function M.target_idx(record, base_idx, now, recover_uses, ttl_days)
  if not M.is_active(record, now, recover_uses, ttl_days) then
    return nil
  end

  now = now_epoch(now)
  base_idx = as_int(base_idx, DEFAULT_BASE_IDX)
  local reduced_at = as_int(record.reduced_at, now)
  local age_days = math.max(0, math.floor((now - reduced_at) / DAY_SECONDS))
  local age_score = math.floor(age_days / AGE_STEP_DAYS) * 2
  local use_score = as_int(record.use_count, 0)
  local target = base_idx - math.floor((age_score + use_score) / 2)

  if target < 2 then return 2 end
  return target
end

function M.record_reduce(state, word, code, now)
  if not word or word == "" or not code or code == "" then
    return false
  end
  now = now_epoch(now)
  if type(state[word]) ~= "table" or state[word][1] ~= nil then
    state[word] = {}
  end
  state[word][code] = { reduced_at = now, last = now, use_count = 0 }
  return true
end

function M.record_reuse(state, word, code, now, recover_uses, ttl_days)
  if not word or word == "" or not code or code == "" then
    return false
  end
  local bucket = state[word]
  if type(bucket) ~= "table" then return false end
  local record = bucket[code]
  if not record then return false end

  now = now_epoch(now)
  if not M.is_active(record, now, recover_uses, ttl_days) then
    bucket[code] = nil
    if next(bucket) == nil then state[word] = nil end
    return true
  end

  record.use_count = as_int(record.use_count, 0) + 1
  record.last = now

  if not M.is_active(record, now, recover_uses, ttl_days) then
    bucket[code] = nil
    if next(bucket) == nil then state[word] = nil end
  end

  return true
end

function M.prune_state(state, now, recover_uses, ttl_days)
  now = now_epoch(now)
  local changed = false

  for word, bucket in pairs(state) do
    if type(bucket) == "table" then
      for code, record in pairs(bucket) do
        if not M.is_active(record, now, recover_uses, ttl_days) then
          bucket[code] = nil
          changed = true
        end
      end
      if next(bucket) == nil then
        state[word] = nil
        changed = true
      end
    else
      state[word] = nil
      changed = true
    end
  end

  return changed
end

return M
