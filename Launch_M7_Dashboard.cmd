@echo off
setlocal
cd /d "%~dp0"

py -3 -c "import streamlit, numpy, cv2, psutil" >nul 2>&1
if errorlevel 1 (
  echo.
  echo M7 dashboard dependencies are missing.
  echo Run this one-time setup command from the repository folder:
  echo.
  echo   py -3 -m pip install -r scripts/python/requirements-m7.txt
  echo.
  pause
  exit /b 1
)

py -3 -m streamlit run scripts/python/m7_dashboard.py
if errorlevel 1 (
  echo.
  echo The M7 dashboard stopped with an error.
  pause
)

endlocal
