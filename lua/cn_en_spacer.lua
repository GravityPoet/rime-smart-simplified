-- 中英混输词条自动空格
-- 在 engine/filters 增加 - lua_filter@cn_en_spacer
--
-- 为中英混输词条（cn_en.dict.yaml）自动空格
-- 示例：`VIP中P` → `VIP 中 P`
-- 由方案开关 smart_space 控制，默认关闭，方案菜单随时开关。
--
-- ChatGPT 写的（本仓库加了 smart_space 开关）

local M = {}

local function add_spaces(s)
    -- 在中文字符后和英文字符前插入空格
    s = s:gsub("([\228-\233][\128-\191]-)([%w%p])", "%1 %2")
    -- 在英文字符后和中文字符前插入空格
    s = s:gsub("([%w%p])([\228-\233][\128-\191]-)", "%1 %2")
    return s
end

-- 是否同时包含中文和英文数字
local function is_mixed_cn_en_num(s)
    return s:find("([\228-\233][\128-\191]-)") and s:find("[%a%d]")
end

function M.func(input, env)
    if not env.engine.context:get_option("smart_space") then
        for cand in input:iter() do yield(cand) end
        return
    end
    for cand in input:iter() do
        local output = cand
        if is_mixed_cn_en_num(cand.text) then
            output = cand:to_shadow_candidate(cand.type, add_spaces(cand.text), cand.comment)
        end
        yield(output)
    end
end

return M
