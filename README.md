# Protocol SIFT — Camel edition

A fork of [Protocol SIFT](https://github.com/teamdfir/protocol-sift) (originally developed by Rob Lee)
that drives Claude Code through the **[Camel](https://github.com/allisterb/Camel) code-mode MCP
server** instead of hand-written skill files calling forensic CLIs directly.

## What changed, and why

The upstream Protocol SIFT configures Claude Code with a broad shell allow-list and a set of
`SKILL.md` files that teach the model how to invoke Volatility, Sleuth Kit, EZ Tools, Plaso, YARA,
etc. one command at a time. The model reasons over raw tool output in its context window.

This fork replaces that with **code-mode**: all forensics go through the Camel MCP server, which
exposes the SIFT tools as a typed JavaScript SDK plus higher-level DFIR **workflows** and an
**anomaly-detection** engine. Claude writes a small JS program; Camel runs it on the SIFT box,
executes the tools, and returns only the distilled result — keeping irrelevant tool output out of the
model's context. Camel also records every tool execution to a per-case audit log for chain of custody.

| Aspect | Upstream Protocol SIFT | This fork (Camel) |
|--------|------------------------|-------------------|
| Tool access | Direct shell CLIs, pre-approved | Camel MCP server (`ExecuteJavaScript`) |
| DFIR knowledge | `skills/*/SKILL.md` prompt libraries | Codified in Camel workflows |
| Output handling | Raw tool output into context (`tee` to `./exports`) | Distilled in-script; only results returned |
| Audit trail | `Stop` hook → `forensic_audit.log` | Camel per-case CLEF log (`audit-<caseId>.clef`) |
| Shell | Broad forensic-CLI allow-list | `Bash` denied — Camel (code-mode) is the only execution path |
| Where it runs | On the SIFT workstation | On the SIFT box **or** a remote machine driving SIFT over SSH |

This fork exists to **benchmark** the two approaches: run a scenario under upstream Protocol SIFT,
then under this Camel edition, and compare wall-clock time, token usage, hallucinations, and accuracy.
To isolate the variable under test (code-mode vs. skills + raw CLIs), the Camel edition **denies the
shell entirely** — the case's `.claude/settings.json` blocks `Bash`, so the agent is *guaranteed* to
run all forensics through the Camel MCP server and nothing else. The agent can still read files and
write its Markdown report to the output dirs with the file tools; it just cannot shell out.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| SANS SIFT Workstation | Ubuntu x86-64, standard SIFT tool set installed |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` (or your org's channel) |
| **Camel**, published | A built `Camel.CLI.dll` (default `/opt/camel/Camel.CLI.dll`) — provides the `create-case` and `server` commands |
| **.NET 9 runtime** | Required by Camel — <https://dotnet.microsoft.com/download/dotnet/9.0> |
| Anthropic API key | Set in `~/.claude/.credentials.json` after first `claude` run — **never copy** this file |
| Python 3 | Runs the `SessionEnd` chat-log hook. `pip3 install weasyprint` too if you want the optional PDF report |

Camel can run on the SIFT workstation itself (local environment) or on a separate machine (e.g.
Windows) that reaches the SIFT box over SSH.

---

## How it works

There is no installer, and **nothing touches your global `~/.claude` config.** The Camel CLI's
**`create-case`** command scaffolds a fully self-contained case directory — every setting, permission,
and hook lives *inside the case*, so everything Claude Code needs travels with the case:

```
<case-dir>/
├── CLAUDE.md                ← per-case instructions (SetCaseId pre-filled with the case id)
├── .mcp.json                ← registers the `camel` stdio MCP server (with the right dll path + mode)
├── .claude/
│   ├── settings.json        ← code-mode policy: allow mcp__camel__*, deny Bash, + the chat-log hook
│   └── preserve_chatlog.py  ← SessionEnd hook: bundles the client chat log into the case
├── analysis/  exports/  reports/   ← the only dirs Claude may write to
```

> Because the Camel edition writes nothing to `~/.claude`, you can install **upstream Protocol SIFT and
> this fork side-by-side** on the same SIFT box and run either against the same scenario without their
> configs colliding — exactly what a fair benchmark needs. Once you have a Camel release, the only other
> thing this fork needs is Claude Code (install it if it isn't already).

`create-case` knows its own assembly path and bakes it (plus any SSH options you pass) into the
generated `.mcp.json`, so Claude Code launches the server itself per session (`dotnet <CAMEL_DLL>
server …`) — nothing extra to start. The server exposes:

| MCP surface | Purpose |
|-------------|---------|
| `SetCaseId` (tool) | Set the audit case id — called once per case |
| `ExecuteJavaScript` (tool) | Run a JS program against the Camel DFIR SDK |
| `camel://sdk/core` (resource) | SDK execution model + every object/method |
| `camel://sdk/schema` (resource) | JSON schema of every returned value |

> **Transport note:** stdio is used by design — Camel's session management, the `SetCaseId` audit
> attribution, the progress heartbeat, and cancellation are all transport-agnostic. Camel also supports
> an HTTP transport (`dotnet <CAMEL_DLL> server --http`, default `http://localhost:5000`) if you prefer
> a shared, long-lived server — point `.mcp.json` at it with `"type": "http"` and a `"url"` instead.

---

## Starting a fresh investigation

```bash
# 1. Scaffold the case (local SIFT). On Windows, use your paths, e.g.
#    dotnet C:\camel\Camel.CLI.dll create-case C:\cases CLIENT-IR-2025-001
dotnet /opt/camel/Camel.CLI.dll create-case /cases CLIENT-IR-2025-001

# 2. Fill in the case details (and confirm SetCaseId is your case id)
nano /cases/CLIENT-IR-2025-001/CLAUDE.md

# 3. Make the evidence available to Camel (it mounts/reads read-only via its SDK)

# 4. Launch Claude from the case root
cd /cases/CLIENT-IR-2025-001
claude
```

The case id (`CLIENT-IR-2025-001` above) must be a safe identifier — letters, digits, dot, underscore,
dash — because it becomes the directory name, the `SetCaseId("…")` value, and the `audit-<caseId>.clef`
filename. `create-case` is **idempotent**: an existing `CLAUDE.md` / `.mcp.json` / `.claude/` file is
left untouched, so re-running never clobbers filled-in details or SSH settings.

In the session, Claude reads `camel://sdk/core` and `camel://sdk/schema`, calls `SetCaseId`, then drives
the case with `ExecuteJavaScript` — preferring Camel workflows, dropping to toolkits for primitives, and
using the anomaly engine to triage large timelines.

### Running against a remote SIFT workstation (SSH)

Unlike upstream Protocol SIFT, Camel can run on a **separate machine** (e.g. Windows) and execute the
forensic tools on a **remote Linux SIFT workstation over SSH**. Pass the SSH connection details to
`create-case` and they are baked into the case's `.mcp.json` (so Claude Code starts Camel in SSH mode):

```bash
dotnet /opt/camel/Camel.CLI.dll create-case /cases CLIENT-IR-2025-001 \
  --ssh --host <sifthost> --user <siftuser> --pass <siftpass>
# --port defaults to 22; supplying any of --host/--user/--pass implies --ssh unless --local is given.
```

The resulting `.mcp.json` `args` look like this (the default, without SSH flags, is just `"server"` for
a local SIFT box):

```json
"args": ["/opt/camel/Camel.CLI.dll", "server", "--ssh", "--host", "<sifthost>", "--user", "<siftuser>", "--pass", "<siftpass>"]
```

> **Security note:** the SSH password ends up on the process command line / in `.mcp.json`. Use a
> throwaway lab credential (as in the SANS SIFT VM), restrict the file, and never commit a real
> `.mcp.json`. For anything sensitive, set the credentials in Camel's `appsettings.json` instead and
> pass just `--ssh` to `create-case`.

### Optional: PDF reports

The agent writes Markdown reports (Bash is denied). To render one to PDF afterward,
[`analysis-scripts/generate_pdf_report.py`](analysis-scripts/generate_pdf_report.py) is a WeasyPrint
helper you run manually (`pip3 install weasyprint`).

---

## Repository structure

```
protocol-sift-camel/
├── README.md                          ← this file
└── analysis-scripts/
    └── generate_pdf_report.py         ← optional manual WeasyPrint PDF generator
```

Everything else — the case `CLAUDE.md`, `.mcp.json`, `.claude/settings.json`, and
`.claude/preserve_chatlog.py` — is **embedded in the Camel CLI** and emitted by `create-case`. This
repo is essentially documentation: a Camel release plus Claude Code is all you need.

---

## Chain of custody

- **Read-only evidence** — Camel mounts and reads evidence read-only; Claude never writes to
  `/cases/`, `/mnt/`, or `/media/`.
- **Per-case audit log** — Camel records every tool execution to `audit-<caseId>.clef` (case id,
  toolkit/tool, command, host, exit code, duration). Each `ExecuteJavaScript` result ends with an
  `[audit] case=<caseId> invocation=<id>` handle; Claude cites it next to each finding so a reviewer
  can trace any conclusion back to the exact commands that produced it.
- **Preserved chat log** — the case's `.claude/settings.json` registers a `SessionEnd` hook
  (`.claude/preserve_chatlog.py`) that copies the full Claude Code client transcript (every message,
  tool call, and timestamp) into `analysis/chatlogs/` when the session ends, bundling it with the case
  audit trail. The hook runs via the harness, not as an agent tool call, so it works despite the `Bash`
  deny. (For an apples-to-apples benchmark, add the same hook to the upstream Protocol SIFT config so
  both runs preserve their transcripts identically.)
- **No raw shell** — the forensic CLIs are denied by policy; all tool execution flows through Camel.

---

## What is NOT included (and why)

| Excluded | Reason |
|----------|--------|
| `~/.claude/.credentials.json` | Your Anthropic API key — never share or copy |
| `~/.claude/history.jsonl`, `projects/`, `debug/`, `telemetry/`, `cache/` | Session/machine specific |
| Camel itself | Built and published separately; this fork only wires Claude Code to it |
| Evidence files (*.E01, *.img) | Read-only evidence — never copy or share |

---

## Credits

Protocol SIFT was created by Rob Lee. This fork adapts it to the Camel code-mode DFIR runtime for the
SANS Find Evil! AI Hackathon.
