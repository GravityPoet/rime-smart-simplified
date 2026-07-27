-- 英文词条上屏自动添加空格
-- 在 engine/filters 的倒数第二个位置，增加 - lua_filter@en_spacer
--
-- 英文后，再输入英文单词（必须为候选项）自动添加空格
-- 由方案开关 smart_space 控制，默认关闭，方案菜单随时开关。
local F = {}

function F.func( input, env )
    if not env.engine.context:get_option("smart_space") then
        for cand in input:iter() do yield(cand) end
        return
    end
    local latest_text = env.engine.context.commit_history:latest_text()
    for cand in input:iter() do
        if cand.text:match( '^[%a\']+[%a\']*$' ) and latest_text and #latest_text > 0 and
            latest_text:find( '^ ?[%a\']+[%a\']*$' ) then
            cand = cand:to_shadow_candidate( 'en_spacer', cand.text:gsub( '(%a+\'?%a*)', ' %1' ), cand.comment )
        end
        yield( cand )
    end
end

return F
