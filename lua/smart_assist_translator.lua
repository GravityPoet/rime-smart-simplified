-- 聊天模式短语/表情候选：本地映射，低权重补充，不抢常规首选。

local M = {}
local QUALITY = 0.8

local CHAT = {
  zan = { "赞", "👍", "太赞了" },
  wanan = { "晚安", "晚安 🌙" },
  zaoshanghao = { "早上好", "早上好 ☀️" },
  kaixin = { "开心", "😄" },
  xiexie = { "谢谢", "谢谢 🙏" },
  okok = { "OKOK", "👌" },
  haode = { "好的", "好嘞" },
  meiwen = { "没问题", "没问题 👌" },
  jiayou = { "加油", "加油 💪" },
  baoquan = { "抱歉", "不好意思" },
}

function M.func(input, seg, env)
  if not env.engine.context:get_option("smart_chat") then return end
  local arr = CHAT[string.lower(input)]
  if not arr then return end
  for i = 1, #arr do
    local cand = Candidate("smart_chat", seg.start, seg._end, arr[i], "chat")
    cand.quality = QUALITY - i * 0.01
    yield(cand)
  end
end

return M
