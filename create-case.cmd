@echo off
REM create-case.cmd - scaffold a Camel case directory for a new investigation (Windows).
REM
REM Creates <cases-dir>\<case-id>\{analysis,exports,reports}, copies the per-case Claude files
REM (CLAUDE.md + .mcp.json) and the PDF report helper from THIS repo, and sets CASE / CASE_DIR.
REM
REM Usage:  create-case.cmd <cases-dir> <case-id>
REM
REM Existing CLAUDE.md / .mcp.json in the case dir are left untouched (re-running won't clobber edits
REM or SSH settings). Edit the copied .mcp.json to point at your Camel.CLI.dll and add the SSH
REM options for a remote SIFT (see the README). Typically used on Windows to drive a remote SIFT.

setlocal
set "REPO_DIR=%~dp0"
set "CASES_DIR=%~1"
set "CASE_ID=%~2"

if "%CASES_DIR%"=="" goto :usage
if "%CASE_ID%"=="" goto :usage

REM The case id becomes a directory name, the SetCaseId value, and the audit-<caseId>.clef filename,
REM so restrict it to a safe identifier (letters, digits, dot, underscore, dash).
echo(%CASE_ID%| findstr /r /c:"^[A-Za-z0-9._-][A-Za-z0-9._-]*$" >nul || goto :badid

set "TMPL_DIR=%REPO_DIR%case-templates"
if not exist "%TMPL_DIR%\CLAUDE.md"  goto :notmpl
if not exist "%TMPL_DIR%\.mcp.json"  goto :notmpl

set "CASE_DIR=%CASES_DIR%\%CASE_ID%"
if not exist "%CASE_DIR%\analysis" mkdir "%CASE_DIR%\analysis"
if not exist "%CASE_DIR%\exports"  mkdir "%CASE_DIR%\exports"
if not exist "%CASE_DIR%\reports"  mkdir "%CASE_DIR%\reports"

if exist "%CASE_DIR%\CLAUDE.md" (
    echo note: %CASE_DIR%\CLAUDE.md already exists - leaving it untouched.
) else (
    REM Copy the template, substituting __CASE_ID__ with this case id so SetCaseId("...") is pre-filled.
    powershell -NoProfile -Command "[IO.File]::WriteAllText('%CASE_DIR%\CLAUDE.md', ([IO.File]::ReadAllText('%TMPL_DIR%\CLAUDE.md')).Replace('__CASE_ID__','%CASE_ID%'))"
)

if exist "%CASE_DIR%\.mcp.json" (
    echo note: %CASE_DIR%\.mcp.json already exists - leaving it untouched.
) else (
    copy /y "%TMPL_DIR%\.mcp.json" "%CASE_DIR%\.mcp.json" >nul
)

if exist "%REPO_DIR%analysis-scripts\generate_pdf_report.py" (
    copy /y "%REPO_DIR%analysis-scripts\generate_pdf_report.py" "%CASE_DIR%\analysis\" >nul
)

echo Created case '%CASE_ID%' at %CASE_DIR%
echo   CLAUDE.md + .mcp.json in place; analysis\ exports\ reports\ created.
echo.
echo Next:
echo   1. Edit %CASE_DIR%\CLAUDE.md with the case details.
echo   2. Set your Camel.CLI.dll path (and SSH options for a remote SIFT) in %CASE_DIR%\.mcp.json.
echo   3. cd /d "%CASE_DIR%" ^&^& claude
echo.
echo (CASE and CASE_DIR are now set in this shell.)
endlocal & set "CASE=%CASE_ID%" & set "CASE_DIR=%CASES_DIR%\%CASE_ID%"
exit /b 0

:usage
echo usage: create-case.cmd ^<cases-dir^> ^<case-id^>
endlocal & exit /b 2

:badid
echo error: case id '%CASE_ID%' must contain only letters, digits, dot, underscore, or dash.
endlocal & exit /b 2

:notmpl
echo error: case template not found in %REPO_DIR%case-templates - run this from the protocol-sift-camel repo.
endlocal & exit /b 1
