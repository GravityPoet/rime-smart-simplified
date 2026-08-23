-- Deterministic, synthetic candidate-stream benchmark.
--
-- This is deliberately not an accuracy benchmark: it measures CPU time for
-- the two bounded candidate-stream seams that are independent of a frontend,
-- user dictionary, and network model.  The shell harness measures install,
-- build, and Lua-process startup proxies separately.

local root = assert(arg[1], "repository root is required")
local iterations = tonumber(arg[2]) or 20
local run_id = arg[3] or "local"

assert(iterations >= 1 and iterations <= 10000, "iterations must be between 1 and 10000")

package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local function json_escape(value)
  local text = tostring(value)
  text = text:gsub("\\", "\\\\")
    :gsub('"', '\\"')
    :gsub("\r", "\\r")
    :gsub("\n", "\\n")
    :gsub("\t", "\\t")
  return '"' .. text .. '"'
end

local function json_number(value)
  if value ~= value or value == math.huge or value == -math.huge then
    return "null"
  end
  return string.format("%.3f", value)
end

local function json_bool(value)
  return value and "true" or "false"
end

local function json_number_array(values)
  local encoded = {}
  for i = 1, #values do encoded[#encoded + 1] = json_number(values[i]) end
  return "[" .. table.concat(encoded, ",") .. "]"
end

local function emit_module_record(module_name, samples, candidate_count, output_count, tail_preserved)
  local sorted = {}
  for i = 1, #samples do sorted[i] = samples[i] end
  table.sort(sorted)

  local total = 0
  for i = 1, #samples do total = total + samples[i] end
  local p95_index = math.max(1, math.ceil(#sorted * 0.95))
  local median_index = math.max(1, math.ceil(#sorted * 0.50))

  io.write("{",
    '"schema":"rime-smart-simplified-benchmark/v1",',
    '"record":"lua_filter",',
    '"run_id":', json_escape(run_id), ",",
    '"module":', json_escape(module_name), ",",
    '"synthetic":true,',
    '"proxy":true,',
    '"real_frontend":false,',
    '"accuracy_claim":false,',
    '"measurement":"synthetic_candidate_stream",',
    '"candidate_count":', tostring(candidate_count), ",",
    '"output_count":', tostring(output_count), ",",
    '"tail_preserved":', json_bool(tail_preserved), ",",
    '"iterations":', tostring(#samples), ",",
    '"batch_size":5,',
    '"clock":"os.clock_cpu",',
    '"unit":"cpu_ms_per_run",',
    '"min_cpu_ms":', json_number(sorted[1]), ",",
    '"median_cpu_ms":', json_number(sorted[median_index]), ",",
    '"p95_cpu_ms":', json_number(sorted[p95_index]), ",",
    '"mean_cpu_ms":', json_number(total / #samples), ",",
    '"samples_cpu_ms":', json_number_array(samples),
    "}\n")
end

local function candidate(text, candidate_type)
  return {
    type = candidate_type or "table",
    start = 0,
    _end = 1,
    text = text,
    comment = "",
    quality = 0,
  }
end

local function make_candidates(count)
  local candidates = {}
  for i = 1, count do
    local text = "候选" .. tostring(i)
    local candidate_type = "table"
    if i == 1 then
      text = "你"
    elseif i % 17 == 0 then
      text = "用户短语" .. tostring(i)
      candidate_type = "abbrev"
    elseif i % 19 == 0 then
      text = "嗎" .. tostring(i)
    elseif i % 23 == 0 then
      text = "😀" .. tostring(i)
    elseif i % 29 == 0 then
      text = "GitHub" .. tostring(i)
    end
    candidates[i] = candidate(text, candidate_type)
  end
  -- Keep the long-tail assertion independent from the category mix above.
  candidates[count] = candidate("候选" .. tostring(count))
  return candidates
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

local function run_once(fn, candidates)
  local old_yield = _G.yield
  local output = {}
  _G.yield = function(value) output[#output + 1] = value end
  local ok, err = pcall(function() fn(input_from(candidates)) end)
  _G.yield = old_yield
  if not ok then error(err, 0) end
  return output
end

local function measure(module_name, fn, candidates, expected_count, expected_tail, extra_check)
  local batch_size = 5
  local warmups = 3
  local tail_preserved = true

  for _ = 1, warmups do
    local output = run_once(fn, candidates)
    assert(#output == expected_count, module_name .. " warm-up output count changed")
    tail_preserved = tail_preserved and output[#output].text == expected_tail
    assert(output[#output].text == expected_tail, module_name .. " warm-up tail changed")
    if extra_check then extra_check(output) end
  end

  local samples = {}
  for i = 1, iterations do
    local started = os.clock()
    local output
    for _ = 1, batch_size do output = run_once(fn, candidates) end
    local elapsed_ms = (os.clock() - started) * 1000 / batch_size
    assert(#output == expected_count, module_name .. " output count changed")
    tail_preserved = tail_preserved and output[#output].text == expected_tail
    assert(output[#output].text == expected_tail, module_name .. " tail candidate was lost")
    if extra_check then extra_check(output) end
    samples[i] = elapsed_ms
  end

  emit_module_record(module_name, samples, #candidates, expected_count, tail_preserved)
end

local candidates = make_candidates(250)

package.loaded.short_code_clean_filter = nil
local short_code = require("short_code_clean_filter")
local short_env = {
  engine = {
    context = {
      input = "ni",
      get_option = function(_, _) return false end,
    },
  },
}
measure("short_code_clean_filter", function(input)
  short_code.func(input, short_env)
end, candidates, 250, "候选250", function(output)
  assert(output[1].text == "用户短语17", "protected synthetic phrase should stay first")
end)

package.loaded["cold_word_drop.filter"] = nil
local cold_filter = require("cold_word_drop.filter")
local cold_env = {
  engine = {
    context = {
      input = "ni",
      composition = nil,
    },
  },
  drop_words = { "候选220" },
  hide_words = {},
  reduce_freq_words = {},
  word_reduce_idx = 5,
  reduce_recover_uses = 6,
  reduce_ttl_days = 14,
}
measure("cold_word_drop.filter", function(input)
  cold_filter.func(input, cold_env)
end, candidates, 249, "候选250", function(output)
  for i = 1, #output do
    assert(output[i].text ~= "候选220", "synthetic drop rule must apply to deep tail")
  end
end)
