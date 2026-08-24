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
  expect_equal(module._test.utc8_weekday(0), "四")
end)

test("date time and week translators all use fixed UTC+8", function()
  package.loaded.date_translator = nil
  local module = require("date_translator")
  local config = { get_string = function() return nil end }
  local env = { name_space = "date_translator", engine = { schema = { config = config } } }
  module.init(env)

  local old_time = os.time
  os.time = function() return 0 end
  local ok, outputs = pcall(function()
    return {
      date = collect(function() module.func("rq", { start = 0, _end = 2 }, env) end),
      time = collect(function() module.func("sj", { start = 0, _end = 2 }, env) end),
      week = collect(function() module.func("xq", { start = 0, _end = 2 }, env) end),
    }
  end)
  os.time = old_time
  if not ok then error(outputs) end

  expect_equal(outputs.date[1].text, "1970-01-01")
  expect_equal(outputs.time[1].text, "08:00")
  expect_equal(outputs.week[1].text, "星期四")
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

test("UUID translator uses a native Windows backend and bounds failed process launches", function()
  package.loaded.uuid = nil
  local module = require("uuid")
  local windows_commands = module._test.commands_for_separator([[\]])
  expect_equal(#windows_commands, 1)
  expect(windows_commands[1]:find("powershell.exe", 1, true) ~= nil,
    "Windows UUID generation must not depend on /usr/bin or Python")
  local platform_commands = module._test.commands_for_separator(package.config:sub(1, 1))

  local config = { get_string = function() return nil end }
  module.init({ name_space = "*uuid", engine = { schema = { config = config } } })
  local old_popen = io.popen
  local values = {
    "11111111-1111-4111-8111-111111111111",
    "22222222-2222-4222-9222-222222222222",
    "33333333-3333-4333-a333-333333333333",
  }
  local calls = 0
  io.popen = function()
    calls = calls + 1
    return {
      read = function() return values[calls] end,
      close = function() return true end,
    }
  end
  local ok, result = pcall(function()
    return collect(function() module.func("uuid", { start = 0, _end = 4 }, {}) end)
  end)
  io.popen = old_popen
  if not ok then error(result) end
  expect_equal(#result, 3)
  expect_equal(calls, 3, "a working backend should be reused for all requested UUIDs")

  calls = 0
  io.popen = function()
    calls = calls + 1
    return {
      read = function() return nil end,
      close = function() return true end,
    }
  end
  ok, result = pcall(function()
    return collect(function() module.func("uuid", { start = 0, _end = 4 }, {}) end)
  end)
  io.popen = old_popen
  if not ok then error(result) end
  expect_equal(#result, 0)
  expect_equal(calls, #platform_commands,
    "each unavailable backend should be tried once instead of spawning 72 failed processes")
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

test("chat mode boosts real emoji but never plain short Chinese words", function()
  package.loaded.smart_mode_filter = nil
  local module = require("smart_mode_filter")
  local env = { engine = { context = fake_context({ smart_chat = true }, "test") } }
  local output = collect(function()
    module.func(input_from({ candidate("中文词"), candidate("短词"), candidate("👍"), candidate("其他") }), env)
  end)
  expect_equal(output[1].text, "中文词", "first candidate stays protected")
  expect_equal(output[2].text, "👍", "emoji candidate should be boosted")
  expect_equal(output[3].text, "短词", "short Chinese words must not be treated as emoji")
  expect_equal(output[4].text, "其他")
end)

test("smart mode reorders within the cap and streams the tail", function()
  package.loaded.smart_mode_filter = nil
  local module = require("smart_mode_filter")
  local candidates = {}
  for i = 1, 150 do candidates[i] = candidate("候选" .. i) end
  candidates[120] = candidate("GitHub")
  local env = { engine = { context = fake_context({ smart_code = true }, "gh") } }
  local output = collect(function() module.func(input_from(candidates), env) end)
  expect_equal(#output, 150, "smart mode must not truncate deep paging")
  local found = false
  for _, cand in ipairs(output) do
    if cand.text == "GitHub" then found = true end
  end
  expect(found, "tail candidates beyond the cap must still be yielded")
end)

test("short-code cleanup bounds work before first yield and streams the tail", function()
  package.loaded.short_code_clean_filter = nil
  local module = require("short_code_clean_filter")
  local env = { engine = { context = fake_context({}, "ni") } }

  local consumed = 0
  local index = 0
  local lazy_input = {
    iter = function()
      return function()
        index = index + 1
        if index > 10000 then return nil end
        consumed = consumed + 1
        return candidate("候选" .. index)
      end
    end,
  }
  local old_yield = _G.yield
  _G.yield = coroutine.yield
  local co = coroutine.create(function() module.func(lazy_input, env) end)
  local ok, first = coroutine.resume(co)
  _G.yield = old_yield
  if not ok then error(first) end
  expect_equal(consumed, 100, "short-code filter must yield after its bounded reorder prefix")
  expect_equal(first.text, "候选1")

  local candidates = {}
  for i = 1, 250 do candidates[i] = candidate("候选" .. i) end
  candidates[80] = candidate("GitHub", "abbrev")
  local output = collect(function() module.func(input_from(candidates), env) end)
  expect_equal(#output, 250, "short-code cleanup must preserve deep paging")
  expect_equal(output[1].text, "GitHub", "protected candidates inside the reorder prefix stay promoted")
  expect_equal(output[250].text, "候选250", "tail candidates must keep streaming")
end)

test("candidate-stream filters preserve the Rime iterator state", function()
  package.loaded.short_code_clean_filter = nil
  local module = require("short_code_clean_filter")
  local candidates = {}
  for i = 1, 250 do candidates[i] = candidate("候选" .. i) end
  local token = {}
  local function rime_input()
    return {
      iter = function()
        local index = 0
        return function(state)
          expect_equal(state, token, "filter must pass the iterator state back to Rime")
          index = index + 1
          return candidates[index]
        end, token, nil
      end,
    }
  end
  local env = { engine = { context = fake_context({}, "ni") } }
  local output = collect(function() module.func(rime_input(), env) end)
  expect_equal(#output, 250, "Rime iterator state must preserve the complete candidate stream")
  expect_equal(output[#output].text, "候选250")
end)

test("pin_by_select disconnects its commit notifier on fini", function()
  package.loaded.pin_by_select = nil
  local root_dir = test_tmp_root
  local old_rime_api = _G.rime_api
  _G.rime_api = { get_user_data_dir = function() return root_dir end }
  local disconnected = false
  local connection = { disconnect = function() disconnected = true end }
  local context = {
    commit_notifier = { connect = function() return connection end },
    get_commit_text = function() return "" end,
  }
  local env = { engine = { context = context } }
  local module = require("pin_by_select")
  module.init(env)
  module.fini(env)
  _G.rime_api = old_rime_api
  expect(disconnected, "fini must disconnect the commit notifier")
  os.remove(root_dir .. "/pin_by_select_v2.tsv")
end)

test("pin_by_select keeps shared learning when two engines initialize together", function()
  package.loaded.pin_by_select = nil
  local root_dir = test_tmp_root
  local data_path = root_dir .. "/pin_by_select_v2.tsv"
  os.remove(data_path)
  local old_rime_api = _G.rime_api
  _G.rime_api = { get_user_data_dir = function() return root_dir end }
  local callbacks = {}
  local committed = "你"
  local function make_env()
    local context = {
      commit_notifier = { connect = function(_, fn)
        callbacks[#callbacks + 1] = fn
        return { disconnect = function() end }
      end },
      input = "ni",
      get_commit_text = function() return committed end,
    }
    return { engine = { context = context } }, context
  end
  local env1 = make_env()
  local env2 = make_env()
  local module = require("pin_by_select")
  module.init(env1)
  callbacks[1](env1.engine.context)
  module.init(env2)
  callbacks[1](env1.engine.context)
  module.fini(env1)
  module.fini(env2)
  _G.rime_api = old_rime_api

  local saved = assert(io.open(data_path, "r")):read("*a")
  expect(saved:match("2:%d+:你") ~= nil,
    "a second engine must not reload away unsaved pin counts")
  os.remove(data_path)
end)

test("cold-word shortcuts preserve the configured Shift modifier", function()
  package.loaded["cold_word_drop.processor"] = nil
  local module = require("cold_word_drop.processor")
  local old_rime_api = _G.rime_api
  local old_open = io.open
  _G.rime_api = {
    get_user_data_dir = function() return test_tmp_root end,
    get_distribution_code_name = function() return "Squirrel" end,
  }
  io.open = function()
    return {
      setvbuf = function() end,
      write = function() return true end,
      close = function() return true end,
    }
  end

  local context = {
    get_script_text = function() return "ni" end,
    has_menu = function() return true end,
    get_selected_candidate = function() return { text = "你" } end,
    refresh_non_confirmed_composition = function() end,
  }
  local env = {
    engine = { context = context },
    drop_cand_key = "Control+Shift+d",
    hide_cand_key = "Control+Shift+x",
    reduce_cand_key = "Control+Shift+j",
    drop_words = {},
    hide_words = {},
    reduce_freq_words = {},
  }
  env.tbls = {
    drop_list = env.drop_words,
    hide_list = env.hide_words,
    reduce_freq_list = env.reduce_freq_words,
  }
  local function press(repr)
    return module.func({ repr = function() return repr end }, env)
  end

  local ok, err = pcall(function()
    expect_equal(press("Control+d"), 2, "Control+d must remain available to the host editor")
    expect_equal(press("Control+x"), 2, "Control+x must not hide a candidate without Shift")
    expect_equal(press("Control+j"), 2, "Control+j must not reduce a candidate without Shift")
    expect_equal(next(env.drop_words), nil)
    expect_equal(next(env.hide_words), nil)
    expect_equal(next(env.reduce_freq_words), nil)

    -- Rime frontends may encode Shift by uppercasing the key symbol.
    expect_equal(press("Control+D"), 1)
    expect_equal(press("Control+X"), 1)
    expect_equal(press("Control+J"), 1)
    expect_equal(env.drop_words[1], "你")
    expect(env.hide_words["你"] ~= nil, "shifted hide shortcut should still work")
    expect(env.reduce_freq_words["你"] ~= nil, "shifted reduce shortcut should still work")
  end)
  io.open = old_open
  _G.rime_api = old_rime_api
  if not ok then error(err) end
end)

test("cold-word filter keeps and filters candidates beyond the reorder cap", function()
  package.loaded["cold_word_drop.filter"] = nil
  local module = require("cold_word_drop.filter")
  local candidates = {}
  for i = 1, 250 do candidates[i] = candidate("候选" .. i) end
  local env = {
    engine = { context = { input = "test", composition = nil } },
    drop_words = { "候选220" },
    hide_words = {},
    reduce_freq_words = {},
    word_reduce_idx = 5,
    reduce_recover_uses = 6,
    reduce_ttl_days = 14,
  }
  local output = collect(function() module.func(input_from(candidates), env) end)
  expect_equal(#output, 249, "the reorder cap must not truncate deep paging")
  expect_equal(output[#output].text, "候选250")
  for _, cand in ipairs(output) do
    expect(cand.text ~= "候选220", "drop rules must still apply beyond the reorder prefix")
  end
end)

test("chat phrase file overrides built-in defaults and tolerates comments", function()
  package.loaded.smart_assist_translator = nil
  local module = require("smart_assist_translator")
  local path = test_tmp_root .. "/smart_chat_phrases.txt"
  local f = assert(io.open(path, "w"))
  f:write("# comment line\n")
  f:write("\n")
  f:write("nihao\t你好\t你好呀\n")
  f:write("BadCode!\t不该出现\n")
  f:write("onlycode\n")
  f:close()

  local parsed = module._test.parse_phrase_file(path)
  os.remove(path)
  expect(parsed ~= nil, "phrase file should parse")
  expect_equal(parsed["nihao"][1], "你好")
  expect_equal(parsed["nihao"][2], "你好呀")
  expect_equal(parsed["badcode!"], nil, "invalid codes must be rejected")
  expect_equal(parsed["onlycode"], nil, "rows without phrases must be rejected")

  expect_equal(module._test.parse_phrase_file(test_tmp_root .. "/definitely_missing.txt"), nil,
    "missing file should fall back to defaults")
  expect(module._test.defaults["xiexie"] ~= nil, "built-in defaults must keep common phrases")
  expect(module._test.defaults["baoqian"] ~= nil, "built-in defaults must use the full pinyin for 抱歉")
  expect(module._test.defaults["huitouliao"] ~= nil, "built-in defaults must use the full pinyin for 回头聊")
  expect_equal(module._test.defaults["baoquan"], nil, "misspelled pinyin must not remain in defaults")
  expect_equal(module._test.defaults["huitoulia"], nil, "truncated pinyin must not remain in defaults")
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

test("context runtime map keeps untouched learning rows compact", function()
  package.loaded.context_boost_filter = nil
  local module = require("context_boost_filter")
  local path = os.tmpname()
  local source = {
    ["当前上下文"] = {
      { text = "候选一", count = 4, last = 2000000000 },
      { text = "候选二", count = 2, last = 1999999999 },
    },
    ["未命中上下文"] = {
      { text = "完整保留", count = 1, last = 1 },
    },
  }
  expect(module._test.write_snapshot(path, source), "snapshot write should succeed")

  local compact = {}
  local rows, malformed, exists = module._test.load_compact_file(path, compact)
  expect(exists, "compact snapshot should exist")
  expect_equal(rows, 2)
  expect_equal(malformed, 0)
  expect_equal(type(compact["当前上下文"]), "string", "runtime should not eagerly expand every row")
  expect_equal(type(compact["未命中上下文"]), "string", "untouched learning must stay compact")

  local resolved = module._test.resolve_items(compact, "当前上下文")
  expect_equal(resolved[1].text, "候选一")
  expect_equal(resolved[1].count, 4)
  expect_equal(type(compact["未命中上下文"]), "string", "resolving one key must not expand other learning")

  os.remove(path)
  os.remove(path .. ".tmp")
end)

test("context filter passes the full stream through when disabled", function()
  package.loaded.context_boost_filter = nil
  local module = require("context_boost_filter")
  local candidates = {}
  for i = 1, 150 do candidates[i] = candidate("候选" .. i) end
  local env = { engine = { context = fake_context({ smart_context = false }, "test") } }
  local output = collect(function() module.func(input_from(candidates), env) end)
  expect_equal(#output, 150, "pass-through must not truncate deep paging")
  expect_equal(output[150].text, "候选150")
end)

test("context filter reorders within the cap and streams the tail", function()
  package.loaded.context_boost_filter = nil
  local root_dir = test_tmp_root
  os.remove(root_dir .. "/context_boost.tsv")
  os.remove(root_dir .. "/context_boost.journal.tsv")

  local old_rime_api = _G.rime_api
  _G.rime_api = { get_user_data_dir = function() return root_dir end }
  local callback
  local committed = ""
  local context = {
    commit_notifier = { connect = function(_, fn) callback = fn end },
    get_commit_text = function() return committed end,
    get_option = function(_, name) return name == "smart_context" end,
    input = "test",
  }
  local env = { engine = { context = context } }
  local module = require("context_boost_filter")
  module.init(env)
  -- 学习 甲词→乙词，并把历史推回到「甲词」结尾，使乙词成为可提升项。
  for _, text in ipairs({ "甲词", "乙词", "甲词" }) do
    committed = text
    callback(context)
  end

  local candidates = {}
  for i = 1, 150 do candidates[i] = candidate("候选" .. i) end
  candidates[50] = candidate("乙词")
  local output = collect(function() module.func(input_from(candidates), env) end)
  module.fini(env)
  _G.rime_api = old_rime_api
  os.remove(root_dir .. "/context_boost.tsv")
  os.remove(root_dir .. "/context_boost.journal.tsv")

  expect_equal(output[1].text, "乙词", "learned pair should be boosted to the top")
  expect_equal(#output, 150, "reordering must keep the tail of the stream")
  expect_equal(output[150].text, "候选150")
end)

test("context filter disconnects its commit notifier on fini", function()
  package.loaded.context_boost_filter = nil
  local root_dir = test_tmp_root
  local old_rime_api = _G.rime_api
  _G.rime_api = { get_user_data_dir = function() return root_dir end }
  local disconnected = false
  local connection = { disconnect = function() disconnected = true end }
  local context = {
    commit_notifier = { connect = function() return connection end },
    get_commit_text = function() return "" end,
  }
  local env = { engine = { context = context } }
  local module = require("context_boost_filter")
  module.init(env)
  module.fini(env)
  _G.rime_api = old_rime_api
  expect(disconnected, "fini must disconnect the commit notifier")
  expect_equal(env.commit_connection, nil, "fini must clear the stored connection")
end)

test("context instances share the map but keep histories per engine", function()
  package.loaded.context_boost_filter = nil
  local root_dir = test_tmp_root
  local data_path = root_dir .. "/context_boost.tsv"
  local journal_path = root_dir .. "/context_boost.journal.tsv"
  os.remove(data_path)
  os.remove(journal_path)
  local old_rime_api = _G.rime_api
  _G.rime_api = { get_user_data_dir = function() return root_dir end }
  local callbacks = {}
  local committed = { "甲", "乙", "丙" }
  local function make_env(index)
    local context = {
      commit_notifier = { connect = function(_, fn)
        callbacks[index] = fn
        return { disconnect = function() end }
      end },
      get_commit_text = function() return committed[index] end,
    }
    return { engine = { context = context } }, context
  end
  local env1 = make_env(1)
  local env2 = make_env(2)
  local module = require("context_boost_filter")
  module.init(env1)
  callbacks[1](env1.engine.context)
  committed[1] = "乙"
  callbacks[1](env1.engine.context)
  module.init(env2)
  committed[2] = "丁"
  callbacks[2](env2.engine.context)
  committed[1] = "丙"
  callbacks[1](env1.engine.context)
  module.fini(env1)
  module.fini(env2)
  _G.rime_api = old_rime_api

  local loaded = {}
  local rows = module._test.load_file(journal_path, loaded)
  expect(rows >= 2, "shared map should retain pairs learned before the second engine")
  expect(loaded["甲"] ~= nil, "first engine learning must survive second initialization")
  expect(loaded["乙"] ~= nil, "each engine must continue writing to the shared map")
  for _, item in ipairs(loaded["乙"] or {}) do
    expect(item.text ~= "丁", "histories from separate engines must not be joined")
  end
  os.remove(data_path)
  os.remove(journal_path)
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

test("cn_en_spacer stays inert until smart_space is enabled", function()
  package.loaded.cn_en_spacer = nil
  local module = require("cn_en_spacer")
  local function shadowable(text)
    local cand = candidate(text)
    cand.to_shadow_candidate = function(self, _, new_text)
      local shadow = candidate(new_text, self.type)
      shadow.to_shadow_candidate = self.to_shadow_candidate
      return shadow
    end
    return cand
  end

  local off_env = { engine = { context = fake_context({}, "vipzhongp") } }
  local off = collect(function()
    module.func(input_from({ shadowable("VIP中P") }), off_env)
  end)
  expect_equal(off[1].text, "VIP中P", "switch off must not rewrite candidates")

  local on_env = { engine = { context = fake_context({ smart_space = true }, "vipzhongp") } }
  local on = collect(function()
    module.func(input_from({ shadowable("VIP中P"), shadowable("纯中文") }), on_env)
  end)
  expect_equal(on[1].text, "VIP 中 P", "mixed text should gain spaces when enabled")
  expect_equal(on[2].text, "纯中文", "pure Chinese text must stay untouched")
end)

test("en_spacer adds a leading space only after an English commit", function()
  package.loaded.en_spacer = nil
  local module = require("en_spacer")
  local function shadowable(text)
    local cand = candidate(text)
    cand.to_shadow_candidate = function(self, _, new_text)
      local shadow = candidate(new_text, self.type)
      shadow.to_shadow_candidate = self.to_shadow_candidate
      return shadow
    end
    return cand
  end
  local function env_with(latest, options)
    local context = fake_context(options or { smart_space = true }, "world")
    context.commit_history = { latest_text = function() return latest end }
    return { engine = { context = context } }
  end

  local off = collect(function()
    module.func(input_from({ shadowable("world") }), env_with("hello", {}))
  end)
  expect_equal(off[1].text, "world", "switch off must not rewrite candidates")

  local after_english = collect(function()
    module.func(input_from({ shadowable("world") }), env_with("hello"))
  end)
  expect_equal(after_english[1].text, " world", "English after English should gain a space")

  local after_chinese = collect(function()
    module.func(input_from({ shadowable("world") }), env_with("你好"))
  end)
  expect_equal(after_chinese[1].text, "world", "English after Chinese must stay untouched")
end)

test("date trigger filter keeps each dynamic result first without dropping candidates", function()
  package.loaded.rq_date_first_filter = nil
  local module = require("rq_date_first_filter")
  local cases = {
    { code = "RQ", expected = "2026-07-18", candidates = { "日期", "2026-07-18", "其他" } },
    { code = "s j", expected = "14:30", candidates = { "时间", "14:30:01", "14:30", "其他" } },
    { code = "xq", expected = "星期六", candidates = { "小区", "周六", "星期六", "其他" } },
    { code = "dt", expected = "2026-07-18T14:30:01+08:00",
      candidates = { "动态", "2026-07-18 14:30:01", "2026-07-18T14:30:01+08:00", "其他" } },
  }

  for _, case in ipairs(cases) do
    local env = { engine = { context = fake_context({}, case.code) } }
    local candidates = {}
    for i, text in ipairs(case.candidates) do candidates[i] = candidate(text) end
    local output = collect(function() module.func(input_from(candidates), env) end)
    expect_equal(output[1].text, case.expected, case.code .. " should promote its dynamic result")
    expect_equal(#output, #case.candidates, case.code .. " must preserve candidate count")
  end
end)

if failed > 0 then
  io.stderr:write(string.format("Lua behavior tests: %d passed, %d failed\n", passed, failed))
  os.exit(1)
end
print(string.format("Lua behavior tests: %d passed, 0 failed", passed))
