-- 词条隐藏、降频
-- 在 engine/processors 增加 - lua_processor@cold_word_drop.processor
-- 在 engine/filters 增加 - lua_filter@cold_word_drop.filter
-- 在 key_binder 增加快捷键：
-- reduce_freq_cand: "Control+j"  # 匹配当前输入码后隐藏指定的候选字词 或候选词条放到第四候选位置
-- drop_cand: "Control+d"         # 强制删词, 无视输入的编码
-- get_record_filername() 函数中仅支持了 Windows、macOS、Linux

require("cold_word_drop.string")
require("cold_word_drop.metatable")
local reduce_state = require("cold_word_drop.reduce_state")
local processor = {}

local function add_action_key(action_map, key_repr, action_type)
	if not key_repr or key_repr == "" then
		return
	end
	action_map[key_repr] = action_type

	local prefix, key_name = key_repr:match("^(.*%+)([^%+]+)$")
	if not prefix or not key_name or not key_name:match("^[A-Za-z]$") then
		return
	end

	local lower_key = key_name:lower()
	local upper_key = key_name:upper()
	if prefix:match("Shift%+$") then
		local no_shift_prefix = prefix:gsub("Shift%+$", "")
		action_map[prefix .. lower_key] = action_type
		action_map[prefix .. upper_key] = action_type
		action_map[no_shift_prefix .. lower_key] = action_type
		action_map[no_shift_prefix .. upper_key] = action_type
	else
		action_map[prefix .. lower_key] = action_type
		action_map[prefix .. upper_key] = action_type
	end
end

local function get_record_filername(record_type)
	local path_sep = "/"
	local user_data_dir = rime_api:get_user_data_dir()
	local user_distribute_name = ""
	if rime_api.get_distribution_code_name then
		user_distribute_name = rime_api:get_distribution_code_name() or ""
	end
	if user_distribute_name:lower():match("weasel") then path_sep = [[\]] end
	if user_distribute_name:lower():match("ibus") then
		return string.format("%s/rime/lua/cold_word_drop/%s_words.lua",
			os.getenv("HOME") .. "/.config/ibus",
			record_type
		)
	else
		local file_path = string.format("%s/lua/cold_word_drop/%s_words.lua", user_data_dir, record_type)
		return file_path:gsub("/", path_sep)
	end
end

local function write_word_to_file(env, record_type)
	local filename = get_record_filername(record_type)
	local record_header = string.format("local %s_words =\n", record_type)
	local record_tailer = string.format("\nreturn %s_words", record_type)
	if not filename then
		return false
	end
	local fd = assert(io.open(filename, "w")) --打开
	-- fd:flush() --刷新
	local x = string.format("%s_list", record_type)
	local record = table.serialize(env.tbls[x]) -- lua 的 table 对象 序列化为字符串
	fd:setvbuf("line")
	fd:write(record_header) --写入文件头部
	fd:write(record) --写入 序列化的字符串
	fd:write(record_tailer) --写入文件尾部, 结束记录
	fd:close() --关闭
end

local function append_word_to_droplist(env, ctx, action_type)
	local word = ctx.word:gsub(" ", "")
	local input_code = ctx.code:gsub(" ", "")

	if action_type == "drop" then
		if not table.find_index(env.drop_words, word) then
			table.insert(env.drop_words, word) -- 高亮选中的词条插入到 drop_list
		end
		return true
	end

	if action_type == "hide" then
		if not env.hide_words[word] then
			env.hide_words[word] = { input_code }
			-- 隐藏的词条如果已经在 hide_list 中, 则将输入串追加到 值表中, 如: ['藏'] = {'chang', 'zhang'}
		elseif not table.find_index(env.hide_words[word], input_code) then
			table.insert(env.hide_words[word], input_code)
		end
		return true
	end

	if action_type == "reduce_freq" then
		return reduce_state.record_reduce(env.reduce_freq_words, word, input_code, os.time())
	end
end

function processor.init(env)
    local engine = env.engine
    local config = engine.schema.config
    local _sd, drop_words = pcall(require, "cold_word_drop/drop_words")
    local _sh, hide_words = pcall(require, "cold_word_drop/hide_words")
    local _st, turn_down_words = pcall(require, "cold_word_drop/turn_down_words")
    local _sr, reduce_freq_words = pcall(require, "cold_word_drop/reduce_freq_words")
    env.drop_words = _sd and drop_words or {}
    env.hide_words = _sh and hide_words or {}
    env.reduce_freq_words = (_st and turn_down_words) or (_sr and reduce_freq_words) or {}
    env.drop_cand_key = config:get_string("key_binder/drop_cand") or "Control+d"
    env.hide_cand_key = config:get_string("key_binder/hide_cand") or "Control+x"
    env.turn_down_cand_key = config:get_string("key_binder/turn_down_cand") or nil
    env.reduce_cand_key = env.turn_down_cand_key or config:get_string("key_binder/reduce_freq_cand") or "Control+j"
    env.reduce_recover_uses = config:get_int("cold_word_reduce/recover_uses") or 6
    env.reduce_ttl_days = config:get_int("cold_word_reduce/ttl_days") or 14
    env.tbls = {
		["drop_list"] = env.drop_words,
		["hide_list"] = env.hide_words,
		["reduce_freq_list"] = env.reduce_freq_words,
	}

	local now = os.time()
	local _, normalized = reduce_state.normalize_state(env.reduce_freq_words, now)
	local pruned = reduce_state.prune_state(env.reduce_freq_words, now, env.reduce_recover_uses, env.reduce_ttl_days)
	if normalized or pruned then
		write_word_to_file(env, "reduce_freq")
	end

	engine.context.commit_notifier:connect(function(ctx)
		local code = (ctx.input or ""):gsub(" ", "")
		if code == "" then return end
		local text = ctx:get_commit_text()
		if not text or text == "" then return end
		text = text:gsub(" ", "")

		local changed = reduce_state.record_reuse(
			env.reduce_freq_words,
			text,
			code,
			os.time(),
			env.reduce_recover_uses,
			env.reduce_ttl_days
		)
		if changed then
			write_word_to_file(env, "reduce_freq")
		end
	end)
end

function processor.func(key, env)
	local engine = env.engine
	local context = engine.context
	local preedit_code = context:get_script_text()
	local action_map = {}
	add_action_key(action_map, env.drop_cand_key, "drop")
	add_action_key(action_map, env.hide_cand_key, "hide")
	add_action_key(action_map, env.reduce_cand_key, "reduce_freq")
	local action_type = action_map[key:repr()]

	if context:has_menu() and action_type then
		local cand = context:get_selected_candidate()
		if not cand or not cand.text then
			return 2
		end
		local ctx_map = {
			["word"] = cand.text,
			["code"] = preedit_code,
		}
		local res = append_word_to_droplist(env, ctx_map, action_type)

		context:refresh_non_confirmed_composition() -- 刷新当前输入法候选菜单, 实现看到实时效果
		if not res then
			return 2
		end

		if res then
			-- 期望被删的词和隐藏的词条写入文件(drop_words.lua, hide_words.lua)
			write_word_to_file(env, action_type)
		end

		return 1 -- kAccept
	end

	return 2 -- kNoop, 不做任何操作, 交给下个组件处理
end

return processor
