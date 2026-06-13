#!/usr/bin/env bash
# protocol-sift-camel install script
# Wires Claude Code on a SANS SIFT Workstation to the Camel code-mode MCP server.
#
# Usage:
#   bash install.sh                       # auto-detect Camel at /opt/camel/Camel.CLI.dll
#   CAMEL_DLL=/path/Camel.CLI.dll bash install.sh
#   bash install.sh /path/Camel.CLI.dll
set -euo pipefail

REPO_URL="https://github.com/allisterb/protocol-sift-camel.git"
CLAUDE_DIR="${HOME}/.claude"
TMPDIR_PREFIX="protocol-sift-camel-install"

# Path to the published Camel CLI assembly that hosts the MCP server.
# Override with the CAMEL_DLL env var or the first positional argument.
CAMEL_DLL="${CAMEL_DLL:-${1:-/opt/camel/Camel.CLI.dll}}"

# Optional: drive a REMOTE SIFT workstation over SSH (e.g. running this fork on Windows against a
# remote Linux SIFT box). Set CAMEL_SSH_HOST to enable; the connection flags are baked into the
# generated .mcp.json so Camel starts in SSH mode. Leave unset for a local SIFT install.
CAMEL_SSH_HOST="${CAMEL_SSH_HOST:-}"
CAMEL_SSH_USER="${CAMEL_SSH_USER:-}"
CAMEL_SSH_PASS="${CAMEL_SSH_PASS:-}"
CAMEL_SSH_PORT="${CAMEL_SSH_PORT:-}"

# ── helpers ──────────────────────────────────────────────────────────────────

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ ok ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
die()   { printf '\033[1;31m[fail]\033[0m  %s\n' "$*" >&2; exit 1; }

backup_if_exists() {
    local target="$1"
    if [[ -e "$target" ]]; then
        local bak="${target}.bak-$(date +%Y%m%d%H%M%S)"
        mv "$target" "$bak"
        warn "Backed up existing $(basename "$target") → $bak"
    fi
}

# ── preflight ────────────────────────────────────────────────────────────────

command -v curl >/dev/null 2>&1 || die "curl is required but not found. Install curl and retry."
command -v git  >/dev/null 2>&1 || die "git is required but not found. Install git and retry."

info "protocol-sift-camel — Camel code-mode DFIR installer"
echo

# ── Claude Code ───────────────────────────────────────────────────────────────

if command -v claude >/dev/null 2>&1; then
    ok "Claude Code already installed: $(command -v claude)"
else
    info "Claude Code not found — running official installer…"
    CLAUDE_INSTALLER="$(mktemp -t claude-install.XXXXXX.sh)"
    curl -fsSL https://claude.ai/install.sh -o "$CLAUDE_INSTALLER"
    bash "$CLAUDE_INSTALLER"
    rm -f "$CLAUDE_INSTALLER"
    for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc"; do
        # shellcheck disable=SC1090
        [[ -f "$profile" ]] && source "$profile" 2>/dev/null || true
    done
    command -v claude >/dev/null 2>&1 || \
        warn "Claude Code installed but 'claude' not yet in PATH. Open a new shell after this script finishes."
    ok "Claude Code installed."
fi
echo

# ── .NET runtime (Camel targets .NET 9) ───────────────────────────────────────

if command -v dotnet >/dev/null 2>&1; then
    DOTNET_MAJOR="$(dotnet --list-runtimes 2>/dev/null \
        | sed -n 's/^Microsoft\.NETCore\.App \([0-9]*\)\..*/\1/p' | sort -rn | head -1)"
    if [[ -n "${DOTNET_MAJOR:-}" && "${DOTNET_MAJOR}" -ge 9 ]]; then
        ok ".NET runtime ${DOTNET_MAJOR}.x found."
    else
        warn "Camel needs the .NET 9 runtime, but the highest installed is '${DOTNET_MAJOR:-none}'."
        warn "Install it before launching the server:  https://dotnet.microsoft.com/download/dotnet/9.0"
    fi
else
    warn "dotnet not found. Camel needs the .NET 9 runtime to host the MCP server."
    warn "Install it before launching:  https://dotnet.microsoft.com/download/dotnet/9.0"
fi

# ── locate the Camel CLI assembly ─────────────────────────────────────────────

if [[ -f "$CAMEL_DLL" ]]; then
    CAMEL_DLL="$(cd "$(dirname "$CAMEL_DLL")" && pwd)/$(basename "$CAMEL_DLL")"   # absolute
    ok "Camel CLI assembly: $CAMEL_DLL"
else
    warn "Camel CLI assembly not found at: $CAMEL_DLL"
    warn "Publish Camel and re-run with the correct path, e.g.:"
    warn "    CAMEL_DLL=/opt/camel/Camel.CLI.dll bash install.sh"
    warn "Continuing — the generated .mcp.json will still point at this path."
fi
echo

# ── locate repo files ─────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/global/CLAUDE.md" && -f "$SCRIPT_DIR/global/settings.json" ]]; then
    info "Running from local repo/archive — skipping clone."
    REPO_DIR="$SCRIPT_DIR"
    WORK_DIR=""
else
    WORK_DIR="$(mktemp -d -t "${TMPDIR_PREFIX}.XXXXXX")"
    trap 'rm -rf "$WORK_DIR"' EXIT
    info "Cloning protocol-sift-camel into temp directory…"
    git clone --depth=1 --quiet "$REPO_URL" "$WORK_DIR/repo"
    REPO_DIR="$WORK_DIR/repo"
    ok "Clone complete."
fi
echo

# ── create ~/.claude if missing ───────────────────────────────────────────────

mkdir -p "$CLAUDE_DIR"

# ── global config files ───────────────────────────────────────────────────────

info "Installing global config files…"
for f in CLAUDE.md settings.json; do
    src="$REPO_DIR/global/$f"
    dst="$CLAUDE_DIR/$f"
    if [[ ! -f "$src" ]]; then
        warn "Source not found, skipping: global/$f"
        continue
    fi
    backup_if_exists "$dst"
    cp "$src" "$dst"
    ok "  global/$f → $dst"
done
echo

# ── case template + Camel MCP registration (.mcp.json) ────────────────────────

info "Installing case template and Camel MCP registration…"
mkdir -p "$CLAUDE_DIR/case-templates"

src="$REPO_DIR/case-templates/CLAUDE.md"
if [[ -f "$src" ]]; then
    cp "$src" "$CLAUDE_DIR/case-templates/CLAUDE.md"
    ok "  case-templates/CLAUDE.md → $CLAUDE_DIR/case-templates/CLAUDE.md"
else
    warn "  case-templates/CLAUDE.md not found, skipping."
fi

# Generate the .mcp.json that registers the `camel` stdio MCP server Claude Code launches itself.
# Builds the args array for `dotnet <CAMEL_DLL> server [--ssh --host … --user … --pass … --port …]`,
# adding the SSH flags only when CAMEL_SSH_HOST is set (remote SIFT over SSH).
# Pure-bash JSON string escaping (no external tool / sed-dialect dependency): double every backslash,
# then escape every double-quote. Verified on GNU bash (the SIFT target). On Windows, pass CAMEL_DLL
# with forward slashes (dotnet accepts C:/camel/…) or run under WSL — MSYS bash mangles backslashes.
json_escape() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '%s' "$s"; }

MCP_ARGS="\"$(json_escape "$CAMEL_DLL")\", \"server\""
if [[ -n "$CAMEL_SSH_HOST" ]]; then
    MCP_ARGS="${MCP_ARGS}, \"--ssh\", \"--host\", \"$(json_escape "$CAMEL_SSH_HOST")\""
    [[ -n "$CAMEL_SSH_USER" ]] && MCP_ARGS="${MCP_ARGS}, \"--user\", \"$(json_escape "$CAMEL_SSH_USER")\""
    [[ -n "$CAMEL_SSH_PASS" ]] && MCP_ARGS="${MCP_ARGS}, \"--pass\", \"$(json_escape "$CAMEL_SSH_PASS")\""
    [[ -n "$CAMEL_SSH_PORT" ]] && MCP_ARGS="${MCP_ARGS}, \"--port\", \"$(json_escape "$CAMEL_SSH_PORT")\""
fi

cat > "$CLAUDE_DIR/case-templates/.mcp.json" <<EOF
{
  "mcpServers": {
    "camel": {
      "type": "stdio",
      "command": "dotnet",
      "args": [${MCP_ARGS}],
      "env": {}
    }
  }
}
EOF

if [[ -n "$CAMEL_SSH_HOST" ]]; then
    ok "  case-templates/.mcp.json → $CLAUDE_DIR/case-templates/.mcp.json (camel → SSH ${CAMEL_SSH_USER:+${CAMEL_SSH_USER}@}${CAMEL_SSH_HOST}${CAMEL_SSH_PORT:+:${CAMEL_SSH_PORT}})"
else
    ok "  case-templates/.mcp.json → $CLAUDE_DIR/case-templates/.mcp.json (camel → local, $CAMEL_DLL)"
fi
echo

# ── analysis-scripts (kept in ~/.claude for reuse across cases) ───────────────

info "Installing analysis scripts…"
mkdir -p "$CLAUDE_DIR/analysis-scripts"
src="$REPO_DIR/analysis-scripts/generate_pdf_report.py"
if [[ -f "$src" ]]; then
    cp "$src" "$CLAUDE_DIR/analysis-scripts/generate_pdf_report.py"
    ok "  generate_pdf_report.py → $CLAUDE_DIR/analysis-scripts/"
else
    warn "  analysis-scripts/generate_pdf_report.py not found, skipping."
fi
echo

# ── optional: WeasyPrint (PDF reports) ────────────────────────────────────────

if [[ -t 0 ]]; then
    read -rp "Install WeasyPrint PDF dependency now? (pip3 install weasyprint) [y/N] " yn
else
    yn="n"
fi

if [[ "$yn" =~ ^[Yy]$ ]]; then
    info "Installing WeasyPrint…"
    if pip3 install weasyprint; then
        ok "WeasyPrint installed."
    else
        warn "pip3 install failed. Try manually:"
        warn "  pip3 install weasyprint"
        warn "  sudo apt-get install -y python3-gi python3-gi-cairo gir1.2-gtk-3.0 libpango-1.0-0"
    fi
else
    info "Skipping WeasyPrint. Install it manually when needed:"
    echo "    pip3 install weasyprint"
    echo "    # if that fails:"
    echo "    sudo apt-get install -y python3-gi python3-gi-cairo gir1.2-gtk-3.0 libpango-1.0-0"
fi
echo

# ── done ─────────────────────────────────────────────────────────────────────

ok "Installation complete."
echo
echo "── Next steps ────────────────────────────────────────────────────────────"
echo
echo "  Start a new case:"
echo
echo "    export CASE=CLIENT-IR-2025-001"
echo "    mkdir -p /cases/\${CASE}/{analysis,exports,reports}"
echo "    cp \${HOME}/.claude/case-templates/CLAUDE.md   /cases/\${CASE}/CLAUDE.md"
echo "    cp \${HOME}/.claude/case-templates/.mcp.json   /cases/\${CASE}/.mcp.json"
echo "    cp \${HOME}/.claude/analysis-scripts/generate_pdf_report.py \\"
echo "       /cases/\${CASE}/analysis/"
echo "    nano /cases/\${CASE}/CLAUDE.md   # fill in case details"
echo "    cd /cases/\${CASE} && claude"
echo
echo "  In the session, Claude reads camel://sdk/core + camel://sdk/schema,"
echo "  calls SetCaseId, then drives the case with ExecuteJavaScript."
echo
echo "  Camel CLI assembly registered (stdio):  $CAMEL_DLL"
echo "  Sanity-check it runs:  dotnet \"$CAMEL_DLL\" server --help"
echo "──────────────────────────────────────────────────────────────────────────"
