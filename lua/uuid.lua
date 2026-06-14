local function yield_cand(seg, text)
	local cand = Candidate("", seg.start, seg._end, text, "")
	cand.quality = 100
	yield(cand)
end

local M = {}
local DEFAULT_UUID_COUNT = 3
local UUIDGEN_CMD = "/usr/bin/uuidgen"
local PY_UUID_CMD = "python3 -c 'import uuid; print(uuid.uuid4())'"
local UUID_V4_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89aAbB]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

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
	local p = io.popen(cmd, "r")
	if not p then return nil end
	local line = p:read("*l")
	p:close()
	return line
end

local function generate_uuid_v4_secure()
	local raw = read_first_line(UUIDGEN_CMD)
	local u = normalize_uuid(raw)
	if is_uuid_v4(u) then return u end

	raw = read_first_line(PY_UUID_CMD)
	u = normalize_uuid(raw)
	if is_uuid_v4(u) then return u end

	return nil
end

function M.init(env)
	M.uuid = env.engine.schema.config:get_string(env.name_space:gsub("^*", "")) or "uuid"
	M.uuid_count = DEFAULT_UUID_COUNT
end

function M.func(input, seg, _)
	if input ~= M.uuid then return end

	local seen = {}
	local generated = 0
	local attempts = 0
	local max_attempts = M.uuid_count * 12
	while generated < M.uuid_count and attempts < max_attempts do
		attempts = attempts + 1
		local u = generate_uuid_v4_secure()
		if u and not seen[u] then
			seen[u] = true
			yield_cand(seg, u)
			generated = generated + 1
		end
	end
end

return M
