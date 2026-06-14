-- 首屏守门：短拼音优先给简体常用候选，把繁体/生僻、emoji、英文候选后移。
-- 只调整顺序，不删除候选；放在个性化学习之后，作为最终首屏清理。

local M = {}

local DEMOTE_TEXTS = {
  ["嗎"] = true,
  ["呒"] = true,
  ["呣"] = true,
}

local LOW_PRIORITY_CHARS_TEXT = table.concat({
  "嗎麼麽妳們個這裡裏於與為無來說時會後還對開關過",
  "國學體臺萬億長門見貝車東風電雲馬鳥魚龍齊齒",
  "難應當實點畫話語讀寫聽愛樂氣漢廣廠產業辦變邊選",
  "買賣賽貴費貨貿錢銀銅鐵鉛鍾鐘錶標準層壓釋針",
  "呒呣嘸冇佢咁咗喺啲嘅嚟乜啱嘢係唔",
})

local LOW_PRIORITY_CHARS = {}

local function each_utf8_char(text, fn)
  if utf8 and utf8.codes and utf8.char then
    local ok = pcall(function()
      for _, cp in utf8.codes(text) do
        fn(utf8.char(cp))
      end
    end)
    if ok then return end
  end

  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    fn(ch)
  end
end

each_utf8_char(LOW_PRIORITY_CHARS_TEXT, function(ch)
  LOW_PRIORITY_CHARS[ch] = true
end)

local function pass(input)
  for cand in input:iter() do yield(cand) end
end

local function is_guarded_alpha_code(code)
  if not code or code == "" then return false end
  code = string.lower(code)
  return #code <= 4 and code:match("^[a-z]+$") ~= nil
end

local function has_ascii_letter(text)
  return text and text:match("[A-Za-z]") ~= nil
end

local function is_email_like(text)
  return text and text:match("^[%w%._%+%-]+@[%w%._%+%-]+$") ~= nil
end

local function is_user_defined_ascii(cand, text)
  local cand_type = cand.type or ""
  return cand_type == "abbrev"
    or cand_type == "user_table"
    or cand_type == "user_phrase"
    or is_email_like(text)
end

local function is_emoji_codepoint(cp)
  return (cp >= 0x1F000 and cp <= 0x1FAFF)
    or (cp >= 0x2600 and cp <= 0x27BF)
    or cp == 0xFE0F
end

local function has_emoji(text)
  if not text or text == "" then return false end
  if utf8 and utf8.codes then
    local ok, hit = pcall(function()
      for _, cp in utf8.codes(text) do
        if is_emoji_codepoint(cp) then return true end
      end
      return false
    end)
    if ok then return hit end
  end

  -- 兜底：常见 emoji 多在四字节区；中文常用字通常是三字节。
  return text:find("[\240-\244]") ~= nil
end

local function has_cjk_extension(text)
  if not text or text == "" or not utf8 or not utf8.codes then return false end
  local ok, hit = pcall(function()
    for _, cp in utf8.codes(text) do
      if (cp >= 0x3400 and cp <= 0x4DBF) or cp >= 0x20000 then
        return true
      end
    end
    return false
  end)
  return ok and hit
end

local function is_low_priority_cjk(text, keep_traditional)
  if keep_traditional then return false end
  if DEMOTE_TEXTS[text] then return true end
  if has_cjk_extension(text) then return true end
  local hit = false
  each_utf8_char(text, function(ch)
    if LOW_PRIORITY_CHARS[ch] then hit = true end
  end)
  return hit
end

local function push(list, cand)
  list[#list + 1] = cand
end

local function yield_list(list)
  for i = 1, #list do yield(list[i]) end
end

function M.func(input, env)
  local context = env.engine.context
  local code = context.input
  if context:get_option("traditionalization") or context:get_option("smart_code") or not is_guarded_alpha_code(code) then
    pass(input)
    return
  end

  local normal = {}
  local protected = {}
  local demoted = {}
  local emoji = {}
  local english = {}

  for cand in input:iter() do
    local text = cand.text or ""
    if is_user_defined_ascii(cand, text) then
      push(protected, cand)
    elseif is_low_priority_cjk(text, false) then
      push(demoted, cand)
    elseif has_emoji(text) then
      push(emoji, cand)
    elseif has_ascii_letter(text) then
      push(english, cand)
    else
      push(normal, cand)
    end
  end

  yield_list(protected)
  yield_list(normal)
  yield_list(demoted)
  yield_list(emoji)
  yield_list(english)
end

return M
