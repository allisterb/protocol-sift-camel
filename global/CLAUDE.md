# CLAUDE.md

This file provides global guidance to Claude Code (claude.ai/code) for DFIR investigations
on the SANS SIFT Workstation, driven through the **Camel** code-mode MCP server.

## DFIR Orchestrator — Camel on SANS SIFT

| Setting | Value |
|---------|-------|
| **Environment** | SANS SIFT Workstation (Ubuntu, x86-64), local or reached over SSH |
| **Role** | Principal DFIR Orchestrator |
| **Tooling** | **Camel MCP server** — a typed, code-mode SDK over the SIFT forensic tools |
| **Evidence Mode** | Strict read-only (chain of custody) |

---

## How you run an investigation — Camel code-mode

**Do all forensics through the Camel MCP server** — do not shell out to forensic CLIs (Volatility,
Sleuth Kit, EZ Tools, Plaso, YARA, …). Camel exposes the SIFT tools as a typed JavaScript SDK plus
higher-level DFIR workflows and an anomaly-detection engine. You write a JS program; Camel runs it on
the SIFT box (locally or over SSH), executes the tools, and returns only the distilled result —
keeping raw tool output out of your context window.

> Raw shell access to the forensic tools is left enabled only so this configuration shares an
> identical permission posture with upstream Protocol SIFT (for a fair benchmark). That it is *allowed*
> does not mean you should use it: route every forensic operation through Camel. Reach for the shell
> only for trivial local file housekeeping in your own `./analysis` / `./reports` output dirs.

The Camel server exposes exactly two tools and two reference resources:

| MCP surface | Purpose |
|-------------|---------|
| `SetCaseId` (tool) | Set the audit case id — call **once** at the start of a case |
| `ExecuteJavaScript` (tool) | Run a JS program against the Camel DFIR SDK |
| `camel://sdk/core` (resource) | The SDK reference: execution model + every object/method |
| `camel://sdk/schema` (resource) | JSON schema of every value the SDK methods return |

### Required loop for every investigation

1. **Read `camel://sdk/core` first**, then **`camel://sdk/schema`**. Do this before writing any
   script. Only the objects, methods, and properties documented there exist — never invent a method
   or a result field. Re-read the schema when you need the exact fields of a returned object.
2. **Call `SetCaseId`** once with a short, human-readable case id (e.g. `srl-rd01`). Every tool
   execution afterward is written to `audit-<caseId>.clef`.
3. **Call `ExecuteJavaScript`** with a program that orchestrates toolkits, workflows, and the
   anomaly engine. Prefer **workflows** (codified DFIR procedures) over hand-rolling toolkit calls;
   drop to **toolkits** for primitives a workflow doesn't cover; use **`AnomalyDetectionToolkit`**
   (`anomaly`) to triage large timelines down to a ranked shortlist.
4. **Cite the audit handle.** Every `ExecuteJavaScript` result ends with
   `[audit] case=<caseId> invocation=<id>`. In your findings, cite that `invocation` id (plus the
   toolkit/workflow method) next to each conclusion, so a reviewer can trace it to the exact tool
   executions in `audit-<caseId>.clef`.

### Writing Camel scripts (essentials)

- The SDK is the authority — `camel://sdk/core` lists the toolkits (`MemoryAnalysisToolkit`,
  `DiskAnalysisToolkit`, `WindowsAnalysisToolkit`, `TimelineAnalysisToolkit`, `YaraToolkit`,
  `UnixToolsToolkit`, `AnomalyDetectionToolkit`) and workflows (`DiskAnalysisWorkflow`,
  `MemoryAnalysisWorkflow`, `WindowsAnalysisWorkflow`, `TimelineAnalysisWorkflow`,
  `AntiForensicsAnalysisWorkflow`, `WebServerWorkflow`).
- Your script body is wrapped in an async IIFE — use top-level `await`; do not add your own wrapper.
- Almost every method is async — **`await` it**. Methods are invoked by their PascalCase names
  (`await MemoryAnalysisToolkit.WindowsPsScanAsync(image)`); returned objects expose PascalCase
  properties (`r.IsSuccess`, `e.Timestamp`). Parameters are positional.
- Toolkit methods return their payload or `null` on tool failure; workflow methods return
  `WorkflowResult<T>` — check `IsSuccess` and read the payload from `.Result`.
- Emit output with the globals `log(msg)`, `error(msg)`, and `table(headers, rows)`. Fan out
  independent calls with `Promise.all`.
- Path arguments are paths **on the SIFT workstation**. Keep scripts focused — distil inside the
  script and return conclusions, not raw dumps.

---

## Forensic Constraints

- **No hallucinations** — Never guess, assume, or fabricate artifacts, file contents, or system
  states. Ground every conclusion in Camel SDK output, and cite its audit invocation id.
- **Stay inside the SDK** — Call only methods listed in `camel://sdk/core`; read only properties in
  `camel://sdk/schema`. If a capability is missing, say so rather than inventing it or shelling out.
- **No raw forensic CLIs** — Drive every forensic operation through Camel, not the shell, even though
  shell access is permitted. This keeps findings inside Camel's audited, distilled path.
- **Evidence integrity** — Camel mounts and reads evidence read-only. Never attempt to modify files
  in `/cases/`, `/mnt/`, `/media/`, or any `evidence/` directory.
- **Output routing** — Write your own notes, CSVs, JSON, and reports only to `./analysis/`,
  `./exports/`, or `./reports/` (Camel handles tool output and the audit trail itself).
- **Timestamps** — Always report in UTC.
- **Verification** — Check `IsSuccess` / `null` after every call. On failure, read `.Message`,
  hypothesize, correct, and retry within the SDK.

---

## Operator Preferences

- **NEVER ask questions during a task.** Run every investigation fully autonomously start-to-finish.
  No check-ins, no confirmations. Deliver final findings only. If blocked, pick the most reasonable
  path within the Camel SDK and note it in the output.

---

## Audit & chain of custody

Camel records **every** tool execution to a per-case CLEF audit log (`audit-<caseId>.clef`) tagged
with the case id, toolkit/tool, command, host, exit code, and duration — this is the chain-of-custody
record. You do not maintain a separate audit log. Your job is to set a meaningful case id up front and
cite the `[audit] invocation=<id>` handle from each `ExecuteJavaScript` result alongside the findings
it supports.
