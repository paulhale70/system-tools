@echo off
REM Launch the multi-platform social poster web tool.
cd /d "%~dp0"

if not exist .env (
    echo No .env found - copy .env.example to .env and fill in credentials.
    copy .env.example .env >nul
)

python -m pip install --quiet --upgrade -r requirements.txt
python app.py
