@echo off
setlocal

set "ROOT=%~dp0"
set "API_DIR=%ROOT%deepforge-api"
set "WEB_DIR=%ROOT%deepforge-web"

if not exist "%API_DIR%\app\main.py" (
  echo [ERROR] Backend entry not found: "%API_DIR%\app\main.py"
  exit /b 1
)

if not exist "%WEB_DIR%\package.json" (
  echo [ERROR] Frontend package.json not found: "%WEB_DIR%\package.json"
  exit /b 1
)

echo [1/3] Stopping existing services on ports 8000 and 5173...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ports = @(8000, 5173); " ^
  "$pids = Get-NetTCPConnection -LocalPort $ports -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique; " ^
  "foreach ($procId in $pids) { " ^
  "  try { Stop-Process -Id $procId -Force -ErrorAction Stop; Write-Host ('Stopped PID ' + $procId) } " ^
  "  catch { Write-Host ('Skip PID ' + $procId + ': ' + $_.Exception.Message) } " ^
  "}"

timeout /t 1 /nobreak >nul

echo [2/3] Starting backend...
start "DeepForge API" powershell -NoExit -ExecutionPolicy Bypass -Command "Set-Location -LiteralPath '%API_DIR%'; if (Test-Path '.venv\Scripts\python.exe') { & '.\.venv\Scripts\python.exe' -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000 } elseif (Get-Command python -ErrorAction SilentlyContinue) { python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000 } elseif (Get-Command py -ErrorAction SilentlyContinue) { py -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000 } else { Write-Host 'Python not found.' -ForegroundColor Red; Read-Host 'Press Enter to exit' }"

echo [3/3] Starting frontend...
start "DeepForge Web" cmd /k "cd /d ""%WEB_DIR%"" && npm run dev"

echo.
echo DeepForge restart command dispatched.
echo Backend:  http://127.0.0.1:8000/health
echo Frontend: http://127.0.0.1:5173/
echo.
echo Two new terminal windows should open for API and Web logs.

endlocal
