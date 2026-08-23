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
local REORDER_CAP = 180

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

	local function candidate_state(cand)
		local cand_text = cand.text:gsub(" ", "")
		local preedit_code = ((cand.preedit and cand.preedit ~= "") and cand.preedit or preedit_str):gsub(" ", "")
		local hidden = table.find_index(drop_words, cand_text)
			or (hide_words[cand_text] and table.find_index(hide_words[cand_text], preedit_code))
		return hidden, cand_text, preedit_code
	end

	-- 新安装或尚未记录负反馈时，直接流式通过，避免每次按键都对候选做
	-- gsub、线性查找和临时表分配。按下隐藏/降频快捷键后表会立刻变为非空，
	-- 下一次刷新自然进入完整过滤路径，无需重载方案。
	if next(drop_words) == nil and next(hide_words) == nil and next(reduce_freq_words) == nil then
		for cand in input:iter() do yield(cand) end
		return
	end

	-- 预测联想段每次上屏后触发，负反馈针对拼音候选记录（预测段无输入码，
	-- 记录也对不上），直接流式通过，减少上屏后的隐性成本。
	local in_prediction = (function()
		local ok, hit = pcall(function()
			local composition = context.composition
			if not composition or composition:empty() then return false end
			local seg = composition:back()
			return seg and seg:has_tag("prediction") or false
		end)
		return ok and hit
	end)()
	if in_prediction then
		for cand in input:iter() do yield(cand) end
		return
	end

	local iter = input:iter()
	local scanned = 0
	for cand in iter do
		local hidden, cand_text, preedit_code = candidate_state(cand)

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

		scanned = scanned + 1
		if scanned >= REORDER_CAP then break end
	end

	yield_merged(normal, reduced)

	-- 仅限制参与重排的前缀，不截断候选流。长尾继续应用永久删除/按码隐藏，
	-- 软降频候选已经位于 180 名之后，无需再把它向前“降”到首屏位置。
	for cand in iter do
		local hidden = candidate_state(cand)
		if not hidden then yield(cand) end
	end
end

return filter
