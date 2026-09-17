# Antigravity CLI (`agy`) tutorial for orchestrators

How to drive Google's Antigravity CLI from another agent (Claude Code) or a script.
Source: https://antigravity.google/docs/cli/overview/ and linked pages, plus behaviour verified
against `agy` 1.2.5 on Linux (September 2026). "Verified" marks things tested, not just read.

## 1. Install, auth, models

- Install per https://antigravity.google/docs/cli/install/. Binary: `agy` (here
  `~/.local/bin/agy`). First interactive run handles Google sign-in.
- `agy models` lists model IDs (verified): `gemini-3.8-flash-high|medium|low`,
  `gemini-3.7-flash-*`, `gemini-3.6-flash-*`, `gemini-3.1-pro-high|low`, `claude-sonnet-4-6`,
  `claude-opus-4-6-thinking`, `gpt-oss-120b-medium`. There is no "3.8 max"; the top Gemini 3.8 is
  `gemini-3.8-flash-high`.
- `--effort low|medium|high` sets reasoning effort.
- Quota: `agy -p "/usage"` prints Gemini and Claude/GPT weekly and five-hour limits (verified).
  They are separate pools.

## 2. Headless (print) mode

```bash
agy -p "prompt" --model gemini-3.8-flash-high --effort high \
    --output-format json --print-timeout 20m
```

- stdout carries the result, stderr carries diagnostics.
- `--output-format json` returns one object (verified):
  `conversation_id`, `status` (`SUCCESS|ERROR|CANCELED|INTERRUPTED|INVALID|WAITING|RUNNING`),
  `response`, `duration_seconds`, `num_turns`, `usage` (input/output/thinking/cache tokens),
  `denied_actions`.
- `--output-format stream-json` emits NDJSON events `init`, `step_update`, `result`.
- `--input-format stream-json` (with `--output-format stream-json`) keeps one process for many
  turns: `{"event":"user","message":{"content":"..."}}` per line.
- `--json-schema '<schema or path>'` puts a parsed object in `structured_output`.
- Continue a conversation: `--conversation <id>` or `--continue` (most recent). The
  conversation's project is reused automatically.
- Default timeout 5 minutes; raise it with `--print-timeout`.
- Unknown model: exits 1 with status `ERROR`.
- Cost note (verified): every call loads the agent system prompt, about 27k input tokens even for
  a one-word prompt. Batch small work into one task.

## 3. Workspace: the first gotcha

Verified: in print mode the agent's workspace is **not** the shell's current directory, even for
trusted folders. Without a workspace it works in `~/.gemini/antigravity-cli/scratch` and cannot
see your project. Always pass `--add-dir "$PWD"` and state the absolute path in the prompt.

## 4. Permissions: the second gotcha

Config: `~/.gemini/antigravity-cli/settings.json`.

```json
{
  "permissions": {
    "allow": ["command(git)", "read_file(/home/me/code/)", "write_file(/home/me/code/)"],
    "deny":  ["command(sudo)", "command(rm)", "command(git push)"],
    "ask":   ["command(*)"]
  }
}
```

- Actions: `read_file`, `write_file`, `read_url`, `execute_url`, `command`, `unsandboxed`, `mcp`.
- Precedence: deny > ask > allow. `*` wildcard, `regex:` prefix for patterns. Denying `read_file`
  on a path also blocks `write_file` there.
- Default: workspace files allowed, everything else asks.
- **Headless mode cannot ask.** Any tool needing approval is soft-denied, the agent stops, and
  the process still exits 0 with `status: SUCCESS` and an empty `response` (verified). Detect it
  via `denied_actions` in the JSON or the stderr line
  `a tool required the "command" permission that headless mode cannot prompt for`.
- Verified matching quirks:
  - A compound shell line is denied even when every part is allowlisted:
    `sort d.txt | uniq -c > e.txt && xxd d.txt | head -1` failed with `sort`, `uniq`, `xxd`,
    `head` all allowed. Tell the agent: one simple command per tool call, no pipes, `&&`, `;`,
    or redirects; write files with the file tools.
  - `command(pytest)` does not cover `.venv/bin/pytest`.
  - The agent reads its own skills. Skill folders under `~/.gemini/config/skills/` are often
    symlinks (here to `~/.agents/skills/` and a project's `.claude/skills/`); the real targets
    need `read_file(...)` rules or the run dies at startup.
- `--dangerously-skip-permissions` approves everything. Avoid it for unattended agents.
- `--sandbox` / `enableTerminalSandbox` runs commands in Linux namespaces: writes limited to the
  workspace, temp and build caches, no network, `~/.ssh` and `.env` hidden. The
  `toolPermission: "proceed-in-sandbox"` preset auto-runs sandboxed commands in the TUI, but did
  **not** stop soft-denials in print mode (verified).

## 4b. Web tools (research)

Verified: headless Gemini has `search_web` (works without a rule) and `read_url_content`, which
needs an allow rule or the run is soft-denied: `"read_url(*)"` (or narrower domains). Security
trade-off: a page Gemini reads can carry prompt injection, and URL reading can leak data in a
query string. Keep `execute_url` unallowed, and keep `read_file`/`write_file` rules limited to
project roots.

MCP servers (for example firecrawl or exa for Gemini's own `deep-research` skill) are added with
`agy mcp add` and are optional; the built-in tools are enough for `gresearch`.

## 5. Projects and conversations

- Conversations belong to projects. Plain `agy` uses `default-cli-project`; `--new-project`
  creates one; `--project <id>` attaches to an existing one; `/fork <project_id>` copies a
  conversation into another project.
- `/resume` (aliases `/switch`, `/conversation`) is a TUI picker and hangs in print mode
  (verified). Headless equivalent, from the local index (verified schema):

```bash
sqlite3 -readonly ~/.gemini/antigravity-cli/conversation_summaries.db \
  "select conversation_id, title, step_count, project_id, workspace_uris, last_modified_time
   from conversation_summaries order by last_modified_time desc limit 20"
```

  `workspace_uris` is a JSON list of percent-encoded `file://` URIs. Map a folder to its project
  ID there, then pass `--project <id>` so headless runs show up in that folder's `/resume` list.
- Conversation content lives in `~/.gemini/antigravity-cli/conversations/<id>.db`.

## 6. Slash commands

Full list (docs): `/add-dir`, `/agents`, `/boost`, `/artifact`, `/btw`, `/clear` `/new`, `/config`
`/settings`, `/context`, `/copy`, `/credits`, `/diff`, `/exit` `/quit`, `/fast`, `/feedback`,
`/fork` `/branch`, `/help`, `/hooks`, `/keybindings`, `/logout`, `/mcp`, `/model`, `/open`,
`/permissions`, `/planning`, `/rename`, `/resume` `/switch` `/conversation`, `/rewind` `/undo`,
`/skills`, `/statusline`, `/tasks`, `/teamwork-preview`, `/title`, `/usage` `/quota`, `/voice`
`/record`.

In print mode (`agy -p "/cmd" --output-format json`), verified to print: `/help`, `/usage`,
`/model`, `/skills`. Print-mode `/help` also lists `/agents`, `/changelog`, `/config`, `/credits`,
`/effort`, `/hooks`, `/permissions`. Verified to hang: `/resume`, `/tasks`. Treat other panels
the same. `--disable-slash-commands` turns expansion off.

Subcommands: `agy models`, `agy agents`, `agy mcp list|add|remove|enable|disable`,
`agy plugin list|install|import|enable|disable`, `agy changelog`, `agy update`,
`agy remote-control start|status|stop`.

## 7. Gemini's own multi-agent features

- **Subagents.** The main agent spawns background subagents itself. Custom agents are Markdown
  with YAML frontmatter in `.agents/agents/<name>.md` (workspace) or `~/.gemini/config/agents/`
  (global); `subagent: true` lets the main agent call them via `invoke_subagent`. Pick one for a
  session with `--agent`. Monitor in the TUI with `/agents`. Headless support is not documented.
- **`/boost <task>`**: orchestrator plus parallel subagents plus synthesis, for hard debugging
  and refactors. Paid plans.
- **`/teamwork-preview <task>`**: long-running team (Sentinel, Orchestrator, Explorers, Workers,
  Critic, Challenger, Auditor) with a scoping interview first. Paid plans, interactive.

For an external orchestrator, the simpler pattern is several independent headless workers (next
section): each has its own conversation ID, so the orchestrator can review and correct each one.

## 8. Pattern: external orchestrator with parallel Gemini workers

Wrapper used here: `bin/gdo` in this skill. What it does and why:

1. Prepends a contract: do exactly the task, never commit/push/reset, reply `BLOCKED` instead of
   guessing, one simple shell command per call, fixed report
   (`STATUS` / `FILES` / `VERIFY` / `NOTES`).
2. Passes `--add-dir "$PWD"` (section 3) and `--project <id>` when the folder already has an agy
   project (section 5).
3. Uses `--output-format json`, saves the raw JSON and stderr to `~/.cache/gdo/`, prints a compact
   summary plus `git status --short`.
4. Exits non-zero on non-`SUCCESS`, empty reply, or any soft-denial (section 4), so the
   orchestrator cannot mistake a dead run for success.
5. `gdo -c <id> "feedback"` continues the same worker; `gdo -l` lists the folder's conversations.

Verified: three workers started at the same moment in one repo each finished with their own
conversation, once the permission gaps above were fixed. Give parallel workers disjoint files.

The orchestrator's side of the loop: plan, write fully specified tasks with a `Verify:` command,
fan out, verify each result itself (run the check, read the diff), send feedback on the same
conversation, integrate, run the full checks once more.
