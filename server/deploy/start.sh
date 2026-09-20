#!/bin/bash

# 获取脚本所在目录
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$APP_DIR" || exit 1

APP_NAME="whisper-server"
LOG_FILE="$APP_DIR/server.log"

# 检查是否已经在运行
PID=$(pgrep -f "$APP_DIR/$APP_NAME")
if [ -n "$PID" ]; then
    echo "[!] $APP_NAME 已经在运行中，PID: $PID"
    exit 0
fi

# 确保执行权限
chmod +x "$APP_DIR/$APP_NAME"

# 确保数据目录存在
mkdir -p "$APP_DIR/data/uploads" "$APP_DIR/data/temp"

echo "[*] 正在启动 $APP_NAME..."
nohup "$APP_DIR/$APP_NAME" -config "$APP_DIR/config.yaml" > "$LOG_FILE" 2>&1 &

sleep 1

PID=$(pgrep -f "$APP_DIR/$APP_NAME")
if [ -n "$PID" ]; then
    echo "[✓] $APP_NAME 启动成功！PID: $PID"
    echo "[*] 日志文件: $LOG_FILE"
    echo "[*] 可以通过 'tail -f $LOG_FILE' 查看实时日志"
else
    echo "[✗] 启动失败，请检查日志: $LOG_FILE"
    tail -n 20 "$LOG_FILE"
fi
