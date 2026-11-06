@echo off
python "%~dp0build_catalog.py" --local-labels
if errorlevel 1 (
    pause
    exit /b 1
)
echo Open http://127.0.0.1:8765/ in your browser. Press Ctrl+C to stop.
python -m http.server 8765 --bind 127.0.0.1 --directory "%~dp0dist"
if errorlevel 1 pause
