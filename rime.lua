-- rime.lua (robust loader)
local function try(name, as)
  local ok, mod = pcall(require, name)
  if ok and mod then
    _G[as or name] = mod
  end
end

-- 个性化智能
try("pin_by_select", "pin_by_select")
try("abbrev_translator", "abbrev_translator")
try("context_boost_filter", "context_boost_filter")
try("smart_mode_filter", "smart_mode_filter")
try("smart_assist_translator", "smart_assist_translator")
try("short_code_clean_filter", "short_code_clean_filter")
try("rq_date_first_filter", "rq_date_first_filter")
try("cold_word_drop.processor", "cold_word_drop_processor")
try("cold_word_drop.filter", "cold_word_drop_filter")

-- rime-ice 常见模块（存在就启用，不存在不报错）
try("pin_cand_filter", "pin_cand_filter")
try("corrector", "corrector")
try("date_translator", "date_translator")
try("number_translator", "number_translator")
try("calc_translator", "calc_translator")
try("select_character", "select_character")
try("unicode", "unicode")
try("uuid", "uuid")
try("search", "search")
try("lunar", "lunar")
try("v_filter", "v_filter")
try("autocap_filter", "autocap_filter")
try("reduce_english_filter", "reduce_english_filter")
try("long_word_filter", "long_word_filter")
try("force_gc", "force_gc")
