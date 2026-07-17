local root = assert(arg[1], "repository root is required")
local test_tmp_root = assert(arg[2], "temporary test directory is required")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local passed = 0
local failed = 0

local function expect(condition, message)
  if not condition then error(message or "expectation failed", 2) end
end

local function expect_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write("FAIL ", name, ": ", tostring(err), "\n")
  end
end

Candidate = function(candidate_type, start_pos, end_pos, text, comment)
  return {
    type = candidate_type,
    start = start_pos,
    _end = end_pos,
    text = text,
    comment = comment,
    quality = 0,
  }
end

local function collect(fn)
  local old_yield = _G.yield
  local output = {}
  _G.yield = function(candidate) output[#output + 1] = candidate end
  local ok, err = pcall(fn)
  _G.yield = old_yield
  if not ok then error(err, 2) end
  return output
end

local function input_from(candidates)
  local index = 0
  return {
    iter = function()
      return function()
        index = index + 1
        return candidates[index]
      end
    end,
  }
end

local function candidate(text, candidate_type)
  return Candidate(candidate_type or "table", 0, 1, text, "")
end

local function fake_context(options, code)
  return {
    input = code or "",
    get_option = function(_, name) return options[name] or false end,
  }
end

test("RFC3339 stays fixed at UTC+8 regardless of host timezone", function()
  package.loaded.date_translator = nil
  local module = require("date_translator")
  expect_equal(module._test.utc8_rfc3339(0), "1970-01-01T08:00:00+08:00")
  expect_equal(module._test.utc8_format('%Y-%m-%d %H:%M:%S', 0), "1970-01-01 08:00:00")
end)

test("datetime translator emits RFC3339 first", function()
  package.loaded.date_translator = nil
  local module = require("date_translator")
  local config = { get_string = function() return nil end }
  local env = { name_space = "date_translator", engine = { schema = { config = config } } }
  module.init(env)
  local output = collect(function() module.func("dt", { start = 0, _end = 2 }, env) end)
  expect(#output >= 3, "datetime translator should emit three candidates")
  expect(output[1].text:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%+08:00$") ~= nil,
    "first datetime candidate must be UTC+8 RFC3339")
end)

test("smart modes use deterministic code priority for legacy mixed state", function()
  package.loaded.smart_mode_filter = nil
  local module = require("smart_mode_filter")
  local options = { smart_code = true, smart_write = true, smart_chat = true }
  local env = { engine = { context = fake_context(options, "gh") } }
  local output = collect(function()
    module.func(input_from({ candidate("中文"), candidate("👍"), candidate("GitHub"), candidate("这是一个长词") }), env)
  end)
  expect_equal(output[1].text, "GitHub", "code-like candidate should be first")
  expect_equal(output[2].text, "中文", "non-code candidates should retain order")
  expect_equal(output[3].text, "👍", "chat boost must not leak into code mode")
end)

test("chat assistant does not leak into code or write mode", function()
  package.loaded.smart_assist_translator = nil
  local module = require("smart_assist_translator")
  local mixed = { smart_chat = true, smart_code = true }
  local mixed_env = { engine = { context = fake_context(mixed, "xiexie") } }
  local blocked = collect(function() module.func("xiexie", { start = 0, _end = 7 }, mixed_env) end)
  expect_equal(#blocked, 0, "chat candidates must be blocked by code mode")

  local chat_env = { engine = { context = fake_context({ smart_chat = true }, "xiexie") } }
  local enabled = collect(function() module.func("xiexie", { start = 0, _end = 7 }, chat_env) end)
  expect_equal(enabled[1].text, "谢谢")
  expect_equal(enabled[2].text, "谢谢 🙏")
end)

test("context snapshot round-trip preserves old singleton seeds", function()
  package.loaded.context_boost_filter = nil
  local module = require("context_boost_filter")
  local path = os.tmpname()
  local source = {
    ["上一段"] = {
      { text = "下一段:含冒号", count = 3, last = 2000000000 },
      { text = "候选二", count = 2, last = 1999999999 },
    },
    ["很久以前"] = {
      { text = "仍然保留", count = 1, last = 1 },
    },
    ["多候选上下文"] = {},
  }
  for i = 1, 12 do
    source["多候选上下文"][i] = { text = "候选" .. i, count = 1, last = i }
  end
  expect(module._test.write_snapshot(path, source), "snapshot write should succeed")
  local loaded = {}
  local rows, malformed, exists = module._test.load_file(path, loaded)
  os.remove(path)
  os.remove(path .. ".tmp")
  expect(exists, "snapshot should exist")
  expect_equal(rows, 3)
  expect_equal(malformed, 0)
  expect_equal(loaded["上一段"][1].text, "下一段:含冒号")
  expect_equal(loaded["上一段"][1].count, 3)
  expect_equal(loaded["很久以前"][1].text, "仍然保留")
  expect_equal(loaded["很久以前"][1].count, 1)
  expect_equal(#loaded["多候选上下文"], 12, "snapshot must not cap stored candidates")
end)

test("context one-shot learning is active only in the current session", function()
  package.loaded.context_boost_filter = nil
  local module = require("context_boost_filter")
  local now = 2000000000
  local target = {
    ["当前上下文"] = {
      { text = "长期候选", count = 2, last = now - 365 * 86400 },
      { text = "刚选候选", count = 1, last = now },
    },
  }
  local without_touch = module._test.rank_boosted(target, { "当前上下文" }, {}, now)
  expect_equal(without_touch[1].text, "长期候选", "cross-session singleton must remain a seed")

  local touched = { ["当前上下文"] = { ["刚选候选"] = true } }
  local current_session = module._test.rank_boosted(target, { "当前上下文" }, touched, now)
  expect_equal(current_session[1].text, "刚选候选", "current-session choice should adapt immediately")
end)

test("context ranking fuses one two and three-segment evidence", function()
  package.loaded.context_boost_filter = nil
  local module = require("context_boost_filter")
  local now = 2000000000
  local old = now - 365 * 86400
  local target = {
    ["丙"] = { { text = "泛化高频", count = 20, last = old } },
    ["@2:乙 > 丙"] = { { text = "精确上下文", count = 2, last = old } },
    ["@3:甲 > 乙 > 丙"] = { { text = "精确上下文", count = 2, last = old } },
  }
  local ranked = module._test.rank_boosted(target, { "甲", "乙", "丙" }, {}, now)
  expect_equal(ranked[1].text, "精确上下文", "corroborated deeper context should beat generic frequency")
  expect(ranked[1].score > ranked[2].score, "fused evidence should have a strictly higher score")
end)

test("context ranking adapts to a recent preference without changing stored counts", function()
  package.loaded.context_boost_filter = nil
  local module = require("context_boost_filter")
  local now = 2000000000
  local target = {
    ["上下文"] = {
      { text = "旧习惯", count = 5, last = now - 365 * 86400 },
      { text = "新偏好", count = 4, last = now },
    },
  }
  local ranked = module._test.rank_boosted(target, { "上下文" }, {}, now)
  expect_equal(ranked[1].text, "新偏好", "recent preference should outrank a slightly larger stale count")
  expect_equal(target["上下文"][1].count, 5, "ranking must not decay or rewrite history")
  expect_equal(target["上下文"][2].count, 4, "ranking must preserve the recent count")
end)

test("context compaction keeps every valid singleton seed", function()
  package.loaded.context_boost_filter = nil
  local root_dir = test_tmp_root
  local snapshot_path = root_dir .. "/context_boost.tsv"
  local journal_path = root_dir .. "/context_boost.journal.tsv"
  local backup_suffix = ".bak.pre-journal-v2"
  os.remove(snapshot_path)
  os.remove(journal_path)
  os.remove(snapshot_path .. backup_suffix)
  os.remove(journal_path .. backup_suffix)

  local snapshot = assert(io.open(snapshot_path, "w"))
  snapshot:write("old-key\t1:1:old-seed\n")
  snapshot:close()
  local journal = assert(io.open(journal_path, "w"))
  for i = 1, 2048 do
    journal:write("journal-", i, "\t1:1:seed-", i, "\n")
  end
  journal:close()

  local old_rime_api = _G.rime_api
  _G.rime_api = { get_user_data_dir = function() return root_dir end }
  local context = {
    commit_notifier = { connect = function() end },
    get_commit_text = function() return "" end,
  }
  local env = { engine = { context = context } }
  local module = require("context_boost_filter")
  module.init(env)
  module.fini(env)
  _G.rime_api = old_rime_api

  local loaded = {}
  local rows, malformed = module._test.load_file(snapshot_path, loaded)
  expect_equal(rows, 2049, "lossless compaction must preserve every key")
  expect_equal(malformed, 0)
  expect_equal(loaded["old-key"][1].text, "old-seed")
  expect_equal(loaded["journal-1"][1].text, "seed-1")
  expect(io.open(journal_path, "r") == nil, "compacted journal should be removed")

  os.remove(snapshot_path)
  os.remove(journal_path)
  os.remove(snapshot_path .. backup_suffix)
  os.remove(journal_path .. backup_suffix)
end)

test("context compaction never rewrites around malformed learning data", function()
  package.loaded.context_boost_filter = nil
  local root_dir = test_tmp_root
  local snapshot_path = root_dir .. "/context_boost.tsv"
  local journal_path = root_dir .. "/context_boost.journal.tsv"
  local backup_suffix = ".bak.pre-journal-v2"
  os.remove(snapshot_path)
  os.remove(journal_path)
  os.remove(snapshot_path .. backup_suffix)
  os.remove(journal_path .. backup_suffix)

  local original_snapshot = "old-key\t1:1:old-seed\n"
  local snapshot = assert(io.open(snapshot_path, "w"))
  snapshot:write(original_snapshot)
  snapshot:close()
  local journal = assert(io.open(journal_path, "w"))
  for i = 1, 2048 do
    journal:write("journal-", i, "\t1:1:seed-", i, "\n")
  end
  journal:write("malformed-row-without-items\n")
  journal:close()

  local old_rime_api = _G.rime_api
  _G.rime_api = { get_user_data_dir = function() return root_dir end }
  local context = {
    commit_notifier = { connect = function() end },
    get_commit_text = function() return "" end,
  }
  local env = { engine = { context = context } }
  local module = require("context_boost_filter")
  module.init(env)
  module.fini(env)
  _G.rime_api = old_rime_api

  local persisted_snapshot = assert(io.open(snapshot_path, "r"))
  local persisted_content = persisted_snapshot:read("*a")
  persisted_snapshot:close()
  expect_equal(persisted_content, original_snapshot, "malformed input must block snapshot replacement")
  local retained_journal = io.open(journal_path, "r")
  expect(retained_journal ~= nil, "raw malformed journal must remain available for recovery")
  retained_journal:close()

  os.remove(snapshot_path)
  os.remove(journal_path)
  os.remove(snapshot_path .. backup_suffix)
  os.remove(journal_path .. backup_suffix)
end)

test("context commits append a journal without rewriting the snapshot", function()
  package.loaded.context_boost_filter = nil
  local root_dir = test_tmp_root

  local old_rime_api = _G.rime_api
  _G.rime_api = { get_user_data_dir = function() return root_dir end }
  local callback
  local committed = ""
  local context = {
    commit_notifier = { connect = function(_, fn) callback = fn end },
    get_commit_text = function() return committed end,
  }
  local env = { engine = { context = context } }
  local module = require("context_boost_filter")
  module.init(env)
  for _, text in ipairs({ "甲测试", "乙测试", "丙测试", "丁测试" }) do
    committed = text
    callback(context)
  end
  module.fini(env)
  _G.rime_api = old_rime_api

  local journal_path = root_dir .. "/context_boost.journal.tsv"
  local journal = io.open(journal_path, "r")
  expect(journal ~= nil, "journal should be created after learned commits")
  local rows = 0
  for _ in journal:lines() do rows = rows + 1 end
  journal:close()
  expect(rows >= 3, "journal should contain dirty context snapshots")
  local snapshot = io.open(root_dir .. "/context_boost.tsv", "r")
  if snapshot then snapshot:close() end
  expect(snapshot == nil, "small commit batches must not force a full snapshot rewrite")

  os.remove(journal_path)
  os.remove(journal_path .. ".tmp")
end)

test("context learns intentional repeated commits", function()
  package.loaded.context_boost_filter = nil
  local root_dir = test_tmp_root
  local snapshot_path = root_dir .. "/context_boost.tsv"
  local journal_path = root_dir .. "/context_boost.journal.tsv"
  os.remove(snapshot_path)
  os.remove(journal_path)

  local old_rime_api = _G.rime_api
  _G.rime_api = { get_user_data_dir = function() return root_dir end }
  local callback
  local committed = "重复测试"
  local context = {
    commit_notifier = { connect = function(_, fn) callback = fn end },
    get_commit_text = function() return committed end,
  }
  local env = { engine = { context = context } }
  local module = require("context_boost_filter")
  module.init(env)
  callback(context)
  callback(context)
  module.fini(env)
  _G.rime_api = old_rime_api

  local loaded = {}
  local rows, malformed = module._test.load_file(journal_path, loaded)
  expect_equal(rows, 1)
  expect_equal(malformed, 0)
  expect_equal(loaded["重复测试"][1].text, "重复测试")
  expect_equal(loaded["重复测试"][1].count, 1)

  os.remove(snapshot_path)
  os.remove(journal_path)
end)

test("rq filter keeps ISO date first without dropping candidates", function()
  package.loaded.rq_date_first_filter = nil
  local module = require("rq_date_first_filter")
  local env = { engine = { context = fake_context({}, "RQ") } }
  local output = collect(function()
    module.func(input_from({ candidate("日期"), candidate("2026-07-18"), candidate("其他") }), env)
  end)
  expect_equal(output[1].text, "2026-07-18")
  expect_equal(output[2].text, "日期")
  expect_equal(output[3].text, "其他")
end)

if failed > 0 then
  io.stderr:write(string.format("Lua behavior tests: %d passed, %d failed\n", passed, failed))
  os.exit(1)
end
print(string.format("Lua behavior tests: %d passed, 0 failed", passed))
