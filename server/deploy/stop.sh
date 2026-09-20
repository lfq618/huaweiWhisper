#!/bin/bash

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="whisper-server"

PID=$(pgrep -f "$APP_DIR/$APP_NAME")

if [ -z "$PID" ]; then
    echo "[!] $APP_NAME 未在运行"
    exit 0
fi

echo "[*] 正在停止 $APP_NAME (PID: $PID)..."
kill "$PID"

for i in {1..10}; do
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "[✓] $APP_NAME 已安全退出"
        exit 0
    fi
    sleep 1
done

echo "[!] 服务超时未退出，正在强制终止..."
kill -9 "$PID"
echo "[✓] $APP_NAME 已强制终止"
