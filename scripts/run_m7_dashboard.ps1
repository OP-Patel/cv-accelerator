$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot ".."))
py -3 -m streamlit run scripts/python/m7_dashboard.py
