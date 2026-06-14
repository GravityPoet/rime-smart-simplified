-- 词条隐藏、降频
-- 在 engine/processors 增加 - lua_processor@cold_word_drop.processor
-- 在 engine/filters 增加 - lua_filter@cold_word_drop.filter
-- 在 key_binder 增加快捷键：
-- reduce_freq_cand: "Control+j"  # 匹配当前输入码后隐藏指定的候选字词 或候选词条放到第四候选位置
-- drop_cand: "Control+d"       # 强制删词, 无视输入的编码
-- get_record_filername() 函数中仅支持了 Windows、macOS、Linux

local filter = {}
require("cold_word_drop.metatable")
local reduce_state = require("cold_word_drop.reduce_state")

function filter.init(env)
    local engine = env.engine
    local config = engine.schema.config
    local _sd, drop_words = pcall(require, "cold_word_drop/drop_words")
    local _sh, hide_words = pcall(require, "cold_word_drop/hide_words")
    local _st, turn_down_words = pcall(require, "cold_word_drop/turn_down_words")
    local _sr, reduce_freq_words = pcall(require, "cold_word_drop/reduce_freq_words")
    env.word_reduce_idx = config:get_int("cold_word_reduce/idx") or 4
    env.reduce_recover_uses = config:get_int("cold_word_reduce/recover_uses") or 6
    env.reduce_ttl_days = config:get_int("cold_word_reduce/ttl_days") or 14
    env.drop_words = _sd and drop_words or {}
    env.hide_words = _sh and hide_words or {}
    env.reduce_freq_words = (_st and turn_down_words) or (_sr and reduce_freq_words) or {}
    reduce_state.normalize_state(env.reduce_freq_words, os.time())
end

local function is_new_text(cand, yielded)
	local text = cand and cand.text
	if not text or text == "" then return true end
	if yielded[text] then return false end
	yielded[text] = true
	return true
end

local function yield_merged(normal, reduced)
	table.sort(reduced, function(a, b)
		if a.target ~= b.target then return a.target < b.target end
		return a.order < b.order
	end)

	local yielded = {}
	local out_idx = 0
	local r = 1

	local function emit(cand)
		if is_new_text(cand, yielded) then
			yield(cand)
			out_idx = out_idx + 1
		end
	end

	for i = 1, #normal do
		while reduced[r] and reduced[r].target <= out_idx + 1 do
			emit(reduced[r].cand)
			r = r + 1
		end
		emit(normal[i])
	end

	while reduced[r] do
		emit(reduced[r].cand)
		r = r + 1
	end
end

function filter.func(input, env)
	local normal = {}
	local reduced = {}
	local context = env.engine.context
	local preedit_str = (context.input or ""):gsub(" ", "")
	local drop_words = env.drop_words
	local hide_words = env.hide_words
	local reduce_freq_words = env.reduce_freq_words
	local now = os.time()

	for cand in input:iter() do
		local cand_text = cand.text:gsub(" ", "")
		local preedit_code = ((cand.preedit and cand.preedit ~= "") and cand.preedit or preedit_str):gsub(" ", "")
		local hidden = table.find_index(drop_words, cand_text)
			or (hide_words[cand_text] and table.find_index(hide_words[cand_text], preedit_code))

		if not hidden then
			local bucket = reduce_freq_words[cand_text]
			local record = type(bucket) == "table" and bucket[preedit_code] or nil
			local target = reduce_state.target_idx(record, env.word_reduce_idx, now, env.reduce_recover_uses, env.reduce_ttl_days)

			if target then
				table.insert(reduced, {
					cand = cand,
					target = target,
					order = #reduced + 1,
				})
			else
				table.insert(normal, cand)
			end
		end

		if #normal + #reduced >= 180 then
			break
		end
	end

	yield_merged(normal, reduced)
end

return filter
