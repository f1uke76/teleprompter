@echo off
chcp 65001 >nul
cd /d "%~dp0"

rem Build the GitHub Pages copy: docs\index.html <- index-online.html
rem ASCII only in this file on purpose (cmd reads it in the console codepage).

if not exist "docs" mkdir "docs"

if not exist "index-online.html" (
  echo [ERR] index-online.html not found.
  pause
  exit /b 1
)

copy /y "index-online.html" "docs\index.html" >nul
if errorlevel 1 (
  echo [ERR] copy failed.
  pause
  exit /b 1
)

rem demo document(s) next to the page, so the online build can fetch them
for %%f in (*.docx) do copy /y "%%f" "docs\" >nul

rem keep GitHub Pages from running Jekyll over the folder
if not exist "docs\.nojekyll" type nul > "docs\.nojekyll"

echo [OK] docs\index.html updated from index-online.html
echo      commit and push, Pages will rebuild automatically.
