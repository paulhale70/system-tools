#!/usr/bin/env bash
# Launch the multi-platform social poster web tool.
set -e
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "No .env found - copying .env.example to .env. Edit it to add credentials."
  cp .env.example .env
fi

python -m pip install --quiet --upgrade -r requirements.txt
exec python app.py
