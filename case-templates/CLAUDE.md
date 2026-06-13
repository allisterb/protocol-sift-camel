# CLAUDE.md

Per-case project instructions, layered on top of the global `~/.claude/CLAUDE.md`. All forensics in
this case run through the **Camel** code-mode MCP server (see the global file for the required loop).

**Course:** SANS FOR508 — Advanced Incident Response, Threat Hunting & Digital Forensics
**Scenario:** Stark Research Labs (SRL) — Lab 1.1 APT Incident Response Challenge

> This template ships with the SRL FOR508 demo scenario. Strip the SRL-specific content and fill in
> the new engagement's details before use. The `Known IOCs` and `Incident Timeline` tables start as
> scaffolding — populate them only with artifacts you confirm through Camel, citing each finding's
> `[audit] invocation=<id>` handle.

---

## Start here — Camel session bootstrap

1. Read the SDK references `camel://sdk/core` then `camel://sdk/schema`.
2. `SetCaseId("srl-rd01")` (use a case id meaningful to this engagement).
3. Drive the investigation with `ExecuteJavaScript`. Prefer workflows; cite audit handles.

---

## Case Overview

| Field | Value |
|-------|-------|
| **Client** | Stark Research Labs (SRL) |
| **Domain** | SHIELDBASE (Windows Server 2022, 2022 DFL) |
| **Threat Actor** | CRIMSON OSPREY (state-level APT) |
| **Incident Declared** | 2023-01-24 |
| **Your Role** | External IR consultant |
| **Initial Responders** | Roger Sydow (IT Admin), Clint Barton (IT Security Analyst) |

---

## Evidence Files

| File (path on SIFT) | System | Notes |
|---------------------|--------|-------|
| `/cases/srl/base-dc-cdrive.E01` | dc01 — Domain Controller | C: drive (~12.5 GB) |
| `/cases/srl/base-rd01-cdrive.E01` | rd01 — Remote Desktop Server | C: drive (~16.6 GB) — **primary compromise host** |
| `/cases/memory/rd01-memory.img` | rd01 | RAM capture (5 GB, primary analysis image) |
| `/cases/srl/base-rd_memory.img` | rd01 | RAM capture (3 GB, baseline-era image) |
| `/cases/srl/base-dc_memory.img` | dc01 | RAM capture (5 GB) |

**Read-only — Camel mounts and reads evidence read-only; never modify these files.**
Write your own analysis only to `./analysis/`, `./exports/`, or `./reports/` (relative to the case dir).

---

## Camel recipes for this case

Paths below are on the SIFT workstation. These are starting points — consult `camel://sdk/core` for
the full method list and exact signatures, and check `IsSuccess` / `null` on every result.

### Disk → mount → triage timeline → anomaly pivots (rd01)

```js
// Mount the rd01 C: drive read-only, then build a triage super-timeline and let the
// anomaly engine surface the high-signal pivots in surrounding context.
const mount = await DiskAnalysisWorkflow.MountEwfImageAsync(
  "/cases/srl/base-rd01-cdrive.E01", "/mnt/ewf_rd01");
if (!mount.IsSuccess) { error(mount.Message); }
else {
  const fs = await DiskAnalysisWorkflow.MountFileSystemAsync(
    mount.Result, /* offset */ mount.Result.Partitions[0].StartSector, "/mnt/rd01");
  const tl = await TimelineAnalysisWorkflow.CreateTriageTimelineAsync("/mnt/rd01", "/cases/srl/rd01.plaso");
  if (tl.IsSuccess) {
    const piv = await TimelineAnalysisWorkflow.AutoPivotExpansionAsync("/cases/srl/rd01.plaso", 200, 10, 5, true);
    log(piv.Message);
    for (const p of piv.Result.Pivots)
      log(`${p.Pivot.Time} ${p.Pivot.EventType} [${p.Pivot.Bits.toFixed(0)} bits] — ${p.SurroundingCount} events`);
  }
}
```

### Memory — full malware hunt (rd01)

```js
const r = await MemoryAnalysisWorkflow.FindMalwareAsync("/cases/memory/rd01-memory.img", "/cases/srl/dumps");
if (r.IsSuccess)
  for (const s of r.Result.HighConfidenceSuspects)
    log(`${s.Process} (PID ${s.Pid}) [${s.Categories.join(", ")}] ${s.Signals.join("; ")}`);
```

### Windows host artifacts (from the mounted rd01 volume)

```js
// Execution evidence, persistence, lateral movement — see WindowsAnalysisWorkflow in camel://sdk/core.
const exec = await WindowsAnalysisWorkflow.AnalyzeExecutionEvidenceAsync(
  "/mnt/rd01/Windows/System32/config/SYSTEM",
  "/mnt/rd01/Windows/AppCompat/Programs/Amcache.hve");
if (exec.IsSuccess) log(`${exec.Result.Entries.length} execution artifacts`);

const lat = await WindowsAnalysisWorkflow.HuntLateralMovementAsync(
  "/mnt/rd01/Windows/System32/winevt/Logs/Security.evtx");
if (lat.IsSuccess) log(lat.Message);
```

### Targeted timeline keyword search / pivot

```js
const hits = await TimelineAnalysisWorkflow.SearchTimelineAsync(
  "/cases/srl/rd01.plaso", ["STUN.exe", "172.16.6.12", "msedge"]);
if (hits.IsSuccess) for (const h of hits.Result.Events) log(`${h.Time}  ${h.Description}`);
```

> Memory-image guidance for **pre-Win10** baselines: pass `legacyMode = true` to
> `FindMalwareAsync`. For very large DC event logs, prefer the scoped/triage workflow methods over
> whole-log passes (see `camel://sdk/core`).

---

## Network Topology

| Network | Subnet | Key Hosts |
|---------|--------|-----------|
| **Management** | 172.16.8.0/24 | log01, assess01/02, sft01, trust01, adusa01 (ELF01 syslog) |
| **Services** | 172.16.4.0/24 | dc01, file01, exchange01 (Exchange 2019), proxy01 (Squid), dev01, sql01 |
| **Business Line** | 172.16.7.0/24 | wksta01–wksta10 (Windows 11) |
| **R&D** | 172.16.6.0/24 | rd01–rd10 (Windows 11); lateral movement target: **172.16.6.12** |
| **DMZ** | 172.16.19.0/24 | dns01, ftp01, smtp01 |
| **VPN Client** | 172.16.30.0/24 | Remote workers |

**External attacker IP:** 172.15.1.20

---

## Domain Accounts

| Account | Role |
|---------|------|
| `rsydow-a` | Domain Admin — Roger Sydow (IT Admin) |
| `cbarton-a` | Domain Admin — Clint Barton (IT Security Analyst) |
| `srl.admin` | Emergency Domain Admin (break-glass) |
| `srladmin` | Local Admin — all workstations |

---

## Known IOCs

> Populate only with artifacts confirmed through Camel; cite each finding's audit invocation id.

### Confirmed Malware

| Indicator | Type | Detail |
|-----------|------|--------|
| `STUN.exe` | Malware binary | `C:\Windows\System32\STUN.exe`, PID 1912, parent svchost.exe PID 1244 |
| `msedge.exe` | Masquerading | 7 instances from STUN.exe + explorer.exe; Trojan:Win32/PowerRunner.A |
| `pssdnsvc.exe` | Suspicious service | `C:\Windows\` — name/path mismatch for PsShutdown |
| `atmfd.dll` | Missing driver | In Autoruns but absent from filesystem |

### Attacker Activity

| Indicator | Detail |
|-----------|--------|
| Lateral movement | `net use H: \\172.16.6.12\c$\Users` — net.exe PID 9128 |
| Execution | STUN.exe as scheduled task → svchost.exe → taskhostw.exe |
| Evasion | msedge.exe masquerading; Defender detected + terminated repeatedly |

---

## Incident Timeline (UTC)

| Timestamp (UTC) | Event |
|-----------------|-------|
| 2023-01-24 | Incident declared; F-Response agents deployed |
| 2023-01-25 14:52:04 | Lateral movement — `net use H: \\172.16.6.12\c$\Users` |
| 2023-01-25 14:56:42–15:04:43 | msedge.exe PIDs spawned |
| 2023-01-25 15:00:56 | msedge.exe PID 2524 active at memory capture time |
| 2023-01-29 12:23:16 | Kansa post-intrusion collection (Autorunsc timestamp) |

---

## Notes

- **Kansa Autorunsc CSVs** (`rd01/dc01/file01/hunt01`) are on the Windows forensic workstation at `G:\SRL_Evidence\kansa\kansa-post-intrusion\Output_20230129122316\Autorunsc\` — not on this SIFT instance.
- **MemProcFS** is not installed on this SIFT instance.
- **VSCMount** is Windows-only — do not use on SIFT.
- Timestamps: always report in UTC.
- Reports: write your report as Markdown to `./reports/` with the Write tool. (PDF rendering via
  `generate_pdf_report.py` needs the shell, which is denied — it's an optional manual post-step for
  the operator, not something you run.)
