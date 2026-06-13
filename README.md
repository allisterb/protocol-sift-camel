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
shell entirely** — `settings.json` blocks `Bash`, so the agent is *guaranteed* to run all forensics
through the Camel MCP server and nothing else. The agent can still read files and write its Markdown
report to the output dirs with the file tools; it just cannot shell out.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| SANS SIFT Workstation | Ubuntu x86-64, standard SIFT tool set installed |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` (or your org's channel) — the installer fetches it if missing |
| **Camel**, published | A built `Camel.CLI.dll` on the SIFT box (default `/opt/camel/Camel.CLI.dll`) |
| **.NET 9 runtime** | Required by Camel — <https://dotnet.microsoft.com/download/dotnet/9.0> |
| Anthropic API key | Set in `~/.claude/.credentials.json` after first `claude` run — **never copy** this file |
| Python 3 + WeasyPrint | `pip3 install weasyprint` — only for PDF report generation |

Camel can run on the SIFT workstation itself (local environment) or on a separate machine that reaches
the SIFT box over SSH — configured in Camel's own `appsettings.json`, independent of this fork.

---

## How the wiring works

The installer registers Camel as a **stdio MCP server** named `camel`. Claude Code launches it per
session (`dotnet <CAMEL_DLL> server`) — there is nothing extra to start. The server exposes:

| MCP surface | Purpose |
|-------------|---------|
| `SetCaseId` (tool) | Set the audit case id — called once per case |
| `ExecuteJavaScript` (tool) | Run a JS program against the Camel DFIR SDK |
| `camel://sdk/core` (resource) | SDK execution model + every object/method |
| `camel://sdk/schema` (resource) | JSON schema of every returned value |

Permissions in `global/settings.json` pre-approve `mcp__camel__*` and the file tools (`Read` +
scoped `Write`/`Edit` to the output dirs), and **deny `Bash`** — so the agent can only act through
Camel. `CLAUDE.md` reinforces this in instructions.

> **Transport note:** stdio is used by design — Camel's session management, the `SetCaseId` audit
> attribution, the progress heartbeat, and cancellation are all transport-agnostic (stdio buckets the
> single client under one session id). Camel also supports an HTTP transport
> (`dotnet <CAMEL_DLL> server --http`, default `http://localhost:5000`) if you prefer a shared,
> long-lived server — point the `.mcp.json` at it with `"type": "http"` and a `"url"` instead.

### Running against a remote SIFT workstation (SSH)

Unlike upstream Protocol SIFT, Camel can run on a **separate machine** (e.g. Windows) and execute the
forensic tools on a **remote Linux SIFT workstation over SSH**. The Camel CLI takes the SSH connection
details as flags, so you don't have to edit Camel's `appsettings.json`:

```bash
dotnet <CAMEL_DLL> server --ssh --host <sifthost> --user <siftuser> --pass <siftpass>
# --port defaults to 22; supplying any of --host/--user/--pass implies --ssh unless --local is given.
```

**You launch Camel in SSH mode by putting those options in the case's `.mcp.json`** — Claude Code
runs whatever `args` you list, so just add the SSH flags after `"server"`. Edit
`.mcp.json` to look like this:

```json
{
  "mcpServers": {
    "camel": {
      "type": "stdio",
      "command": "dotnet",
      "args": [
        "C:/camel/Camel.CLI.dll", "server",
        "--ssh",
        "--host", "<sifthost>",
        "--user", "<siftuser>",
        "--pass", "<siftpass>",
        "--port", "22"
      ],
      "env": {}
    }
  }
}
```

The default `.mcp.json` (just `"server"`) runs Camel against the **local** SIFT box; adding the
`--ssh --host/--user/--pass` options switches it to drive a **remote** SIFT over SSH. You can also let
`install.sh` write this for you — set the SSH variables and it bakes the flags into the generated
`.mcp.json`:

```bash
CAMEL_DLL=C:/camel/Camel.CLI.dll \
CAMEL_SSH_HOST=<sifthost> CAMEL_SSH_USER=<siftuser> CAMEL_SSH_PASS=<siftpass> \
  bash install.sh
```

> **Security note:** these flags put the SSH password on the process command line / in `.mcp.json`.
> Use a throwaway lab credential (as in the SANS SIFT VM), restrict the file, and never commit a real
> `.mcp.json`. For anything sensitive, set the credentials in Camel's `appsettings.json` instead and
> launch with just `--ssh`.

---

## Installation

```bash
git clone --depth=1 https://github.com/allisterb/protocol-sift-camel.git
cd protocol-sift-camel

# Point the installer at your published Camel CLI assembly (default: /opt/camel/Camel.CLI.dll)
CAMEL_DLL=/opt/camel/Camel.CLI.dll bash install.sh
```

The script will:
- Install Claude Code if it isn't already present
- Check for the .NET 9 runtime and the Camel CLI assembly
- Install `global/CLAUDE.md` and `global/settings.json` into `~/.claude/`
- Install the case template and a `.mcp.json` that registers the `camel` server (with the resolved
  `Camel.CLI.dll` path) into `~/.claude/case-templates/`
- Install the PDF report generator into `~/.claude/analysis-scripts/`
- Back up any existing `~/.claude/{CLAUDE.md,settings.json}` to `.bak-<timestamp>` first

You can also pass the path positionally: `bash install.sh /opt/camel/Camel.CLI.dll`.

---

## Repository structure

```
protocol-sift-camel/
├── README.md                          ← this file
├── install.sh                         ← installer (registers the Camel MCP server)
├── global/
│   ├── CLAUDE.md                      ← global instructions: drive DFIR through Camel
│   └── settings.json                  ← allow mcp__camel__*; deny raw forensic CLIs
├── case-templates/
│   ├── CLAUDE.md                      ← per-case template (Camel SDK recipes)
│   └── .mcp.json                      ← registers the `camel` stdio MCP server
└── analysis-scripts/
    └── generate_pdf_report.py         ← WeasyPrint PDF generator (unchanged)
```

---

## Starting a fresh investigation

```bash
# 1. Prepare the case directory
export CASE=CLIENT-IR-2025-001
mkdir -p /cases/${CASE}/{analysis,exports,reports}
cp ~/.claude/case-templates/CLAUDE.md /cases/${CASE}/CLAUDE.md
cp ~/.claude/case-templates/.mcp.json /cases/${CASE}/.mcp.json   # registers the camel server
cp ~/.claude/analysis-scripts/generate_pdf_report.py /cases/${CASE}/analysis/
nano /cases/${CASE}/CLAUDE.md   # fill in case details

# 2. Make evidence available to Camel (Camel mounts/reads it read-only via its SDK)

# 3. Launch Claude from the case root (sets relative Write paths)
cd /cases/${CASE}
claude
```

In the session, Claude reads `camel://sdk/core` and `camel://sdk/schema`, calls `SetCaseId`, then
drives the case with `ExecuteJavaScript` — preferring Camel workflows, dropping to toolkits for
primitives, and using the anomaly engine to triage large timelines.

---

## Chain of custody

- **Read-only evidence** — Camel mounts and reads evidence read-only; Claude never writes to
  `/cases/`, `/mnt/`, or `/media/`.
- **Per-case audit log** — Camel records every tool execution to `audit-<caseId>.clef` (case id,
  toolkit/tool, command, host, exit code, duration). Each `ExecuteJavaScript` result ends with an
  `[audit] case=<caseId> invocation=<id>` handle; Claude cites it next to each finding so a reviewer
  can trace any conclusion back to the exact commands that produced it.
- **Preserved chat log** — a `SessionEnd` hook (`analysis-scripts/preserve_chatlog.py`) copies the
  full Claude Code client transcript (every message, tool call, and timestamp) into
  `./analysis/chatlogs/` when the session ends, bundling the chat log with the case audit trail. The
  hook runs via the harness, not as an agent tool call, so it works despite the `Bash` deny. (For an
  apples-to-apples benchmark, add the same hook to the upstream Protocol SIFT config so both runs
  preserve their transcripts identically.)
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
