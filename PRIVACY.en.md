# Privacy Boundary

This configuration pack is local-first:

- It does not call a cloud input API or upload typed content.
- It does not require an account.
- Local learning data stays in the Rime user directory.
- By default, the installer downloads the Wanxiang LTS grammar model and librime-predict `predict.db` from official GitHub Releases and verifies their hashes. These are installation-time asset requests; daily typing does not call those sites.

Rime naturally accumulates personal typing habits. Do not publish these files or directories without reviewing them:

- `custom_phrase.txt`
- `smart_chat_phrases.txt`
- `context_boost.tsv`
- `context_boost.journal.tsv`
- `context_boost*.bak.*`
- `pin_by_select.tsv`
- `pin_by_select_v2.tsv`
- `lua/cold_word_drop/drop_words.lua`
- `lua/cold_word_drop/hide_words.lua`
- `lua/cold_word_drop/reduce_freq_words.lua`
- `predict.db`
- `*.userdb/`
- `sync/`
- `installation.yaml`
- `user.yaml`
- `*.gram`

Before publishing a fork or pull request, scan the checkout:

```bash
rg -n -i "email|phone|token|secret|password|api[_-]?key|/Users/|@[A-Z0-9.-]+\\.[A-Z]{2,}" .
```
