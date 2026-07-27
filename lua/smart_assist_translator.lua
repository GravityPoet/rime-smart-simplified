-- 聊天模式短语/表情候选：本地映射，低权重补充，不抢常规首选。
-- 短语表优先读取用户目录 smart_chat_phrases.txt（TSV：编码<Tab>短语1<Tab>短语2…），
-- 文件不存在或为空时回落到内置默认表；安装脚本不会覆盖用户已有文件。

local M = {}
local QUALITY = 0.8
local DATA_FILE = "smart_chat_phrases.txt"

local DEFAULT_CHAT = {
  zan = { "赞", "👍", "太赞了" },
  wanan = { "晚安", "晚安 🌙" },
  zaoshanghao = { "早上好", "早上好 ☀️" },
  zao = { "早", "早上好" },
  kaixin = { "开心", "😄" },
  xiexie = { "谢谢", "谢谢 🙏", "多谢" },
  okok = { "OKOK", "👌" },
  haode = { "好的", "好嘞", "好哒" },
  meiwen = { "没问题", "没问题 👌" },
  jiayou = { "加油", "加油 💪" },
  baoqian = { "抱歉", "不好意思" },
  buhaoyisi = { "不好意思", "抱歉" },
  shoudao = { "收到", "收到 👌" },
  zhidaole = { "知道了", "了解" },
  mingbai = { "明白", "明白了" },
  xinkule = { "辛苦了", "辛苦啦" },
  mafanle = { "麻烦了", "麻烦你了" },
  gaoding = { "搞定", "搞定 ✅" },
  lihai = { "厉害", "厉害 👍" },
  gongxi = { "恭喜", "恭喜 🎉" },
  shengrikuaile = { "生日快乐", "生日快乐 🎂" },
  xinniankuaile = { "新年快乐", "新年快乐 🎉" },
  zhoumoyukuai = { "周末愉快", "周末愉快 ☀️" },
  zaijian = { "再见", "再见 👋" },
  huitouliao = { "回头聊", "回头聊 👋" },
}

local chat_map = nil

local function parse_phrase_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local map = {}
  local rows = 0
  for line in f:lines() do
    line = line:gsub("\r$", "")
    if line ~= "" and not line:match("^%s*#") then
      local cols = {}
      for col in line:gmatch("([^\t]+)") do
        cols[#cols + 1] = col
      end
      local code = cols[1] and cols[1]:lower()
      if code and code:match("^[a-z]+$") and #cols >= 2 then
        local arr = {}
        for i = 2, #cols do
          if cols[i] ~= "" then arr[#arr + 1] = cols[i] end
        end
        if #arr > 0 then
          map[code] = arr
          rows = rows + 1
        end
      end
    end
  end
  f:close()
  if rows == 0 then return nil end
  return map
end

function M.init(_)
  if chat_map then return end
  local loaded = nil
  if rime_api and rime_api.get_user_data_dir then
    local ok, result = pcall(function()
      return parse_phrase_file(rime_api.get_user_data_dir() .. "/" .. DATA_FILE)
    end)
    if ok then loaded = result end
  end
  chat_map = loaded or DEFAULT_CHAT
end

function M.func(input, seg, env)
  local context = env.engine.context
  if context:get_option("smart_code") or context:get_option("smart_write") then return end
  if not context:get_option("smart_chat") then return end
  if not chat_map then M.init(env) end
  local arr = chat_map[string.lower(input)]
  if not arr then return end
  for i = 1, #arr do
    local cand = Candidate("smart_chat", seg.start, seg._end, arr[i], "chat")
    cand.quality = QUALITY - i * 0.01
    yield(cand)
  end
end

M._test = {
  parse_phrase_file = parse_phrase_file,
  defaults = DEFAULT_CHAT,
  reset = function() chat_map = nil end,
}

return M
