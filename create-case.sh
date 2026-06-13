#!/usr/bin/env bash
# create-case.sh — scaffold a Camel case directory for a new investigation.
#
# Creates <cases-dir>/<case-id>/{analysis,exports,reports}, copies the per-case Claude files
# (CLAUDE.md + .mcp.json) and the PDF report helper from THIS repo, and exports CASE / CASE_DIR
# (as the README's flow describes).
#
# Usage:
#   ./create-case.sh <cases-dir> <case-id>            # creates the case; CASE persists only if sourced
#   . ./create-case.sh <cases-dir> <case-id>          # source it to keep $CASE set in your shell
#
# Existing CLAUDE.md / .mcp.json in the case dir are left untouched (so re-running won't clobber
# filled-in case details or SSH settings). Edit the copied .mcp.json to point at your Camel.CLI.dll
# (and add --ssh --host/--user/--pass for a remote SIFT) — see the README.

_create_case() {
    local repo_dir
    repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local cases_dir="$1" case_id="$2"

    if [ -z "$cases_dir" ] || [ -z "$case_id" ]; then
        echo "usage: create-case.sh <cases-dir> <case-id>" >&2
        return 2
    fi

    # The case id becomes a directory name, the SetCaseId value, and the audit-<caseId>.clef filename,
    # so restrict it to a safe identifier (also keeps the sed substitution below injection-free).
    case "$case_id" in
        *[!A-Za-z0-9._-]*)
            echo "error: case id '$case_id' must contain only letters, digits, dot, underscore, or dash." >&2
            return 2 ;;
    esac

    local tmpl_dir="$repo_dir/case-templates"
    if [ ! -f "$tmpl_dir/CLAUDE.md" ] || [ ! -f "$tmpl_dir/.mcp.json" ]; then
        echo "error: case template not found in $tmpl_dir — run this from the protocol-sift-camel repo." >&2
        return 1
    fi

    local case_dir="${cases_dir%/}/$case_id"
    mkdir -p "$case_dir/analysis" "$case_dir/exports" "$case_dir/reports" || return 1

    if [ -e "$case_dir/CLAUDE.md" ]; then
        echo "note: $case_dir/CLAUDE.md already exists — leaving it untouched."
    else
        # Copy the template, substituting the __CASE_ID__ placeholder with this case id (so the
        # agent's SetCaseId("...") call is pre-filled). case_id is validated above, so it is sed-safe.
        sed "s/__CASE_ID__/$case_id/g" "$tmpl_dir/CLAUDE.md" > "$case_dir/CLAUDE.md" || return 1
    fi

    if [ -e "$case_dir/.mcp.json" ]; then
        echo "note: $case_dir/.mcp.json already exists — leaving it untouched."
    else
        cp "$tmpl_dir/.mcp.json" "$case_dir/.mcp.json" || return 1
    fi

    if [ -f "$repo_dir/analysis-scripts/generate_pdf_report.py" ]; then
        cp "$repo_dir/analysis-scripts/generate_pdf_report.py" "$case_dir/analysis/" || return 1
    fi

    export CASE="$case_id"
    export CASE_DIR="$case_dir"

    echo "Created case '$case_id' at $case_dir"
    echo "  CLAUDE.md + .mcp.json in place; analysis/ exports/ reports/ created."
    echo "  CASE=$CASE  CASE_DIR=$CASE_DIR"
    echo
    echo "Next:"
    echo "  1. Edit $case_dir/CLAUDE.md with the case details."
    echo "  2. Set your Camel.CLI.dll path (and SSH options for a remote SIFT) in $case_dir/.mcp.json."
    echo "  3. cd \"$case_dir\" && claude"
}

_create_case "$@"
