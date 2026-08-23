local function yield_cand(seg, text)
	local cand = Candidate("", seg.start, seg._end, text, "")
	cand.quality = 100
	yield(cand)
end

local M = {}
local DEFAULT_UUID_COUNT = 3
local UUID_V4_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89aAbB]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

local function commands_for_separator(path_separator)
	if path_separator == [[\]] then
		-- Windows 8.1～11 自带 Windows PowerShell；不依赖 Python 或 MSYS 路径。
		return {
			'powershell.exe -NoLogo -NoProfile -NonInteractive -Command "[guid]::NewGuid().ToString()" 2>NUL',
		}
	end

	return {
		"/usr/bin/uuidgen 2>/dev/null",
		"uuidgen 2>/dev/null",
		"python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null",
	}
end

local UUID_COMMANDS = commands_for_separator(package.config:sub(1, 1))

local function trim_space(s)
	if not s then return nil end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_uuid(s)
	local t = trim_space(s)
	if not t or t == "" then return nil end
	return string.lower(t)
end

local function is_uuid_v4(s)
	return s and s:match(UUID_V4_PATTERN) ~= nil
end

local function read_first_line(cmd)
	local opened, p = pcall(io.popen, cmd, "r")
	if not opened or not p then return nil end
	local read_ok, line = pcall(function() return p:read("*l") end)
	pcall(function() p:close() end)
	if not read_ok then return nil end
	return line
end

function M.init(env)
	M.uuid = env.engine.schema.config:get_string(env.name_space:gsub("^*", "")) or "uuid"
	M.uuid_count = DEFAULT_UUID_COUNT
end

function M.func(input, seg, _)
	if input ~= M.uuid then return end

	local seen = {}
	local generated = 0
	for _, command in ipairs(UUID_COMMANDS) do
		local attempts = 0
		local max_attempts = M.uuid_count * 2
		while generated < M.uuid_count and attempts < max_attempts do
			attempts = attempts + 1
			local u = normalize_uuid(read_first_line(command))
			-- 命令无效时立即换下一个后端，不再为每个候选重复拉起失败进程。
			if not is_uuid_v4(u) then break end
			if not seen[u] then
				seen[u] = true
				yield_cand(seg, u)
				generated = generated + 1
			end
		end
		if generated >= M.uuid_count then break end
	end
end

M._test = {
	commands_for_separator = commands_for_separator,
}

return M
