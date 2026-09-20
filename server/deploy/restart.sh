#!/bin/bash

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[*] 正在重启服务..."
bash "$APP_DIR/stop.sh"
sleep 1
bash "$APP_DIR/start.sh"
