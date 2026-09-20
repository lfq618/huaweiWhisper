# 智聆转写后端服务 Linux 部署指南

本目录包含了已交叉编译构建完成的 **Linux x86_64 / amd64** 独立二进制运行包。

---

## 📦 目录文件清单

| 文件 | 说明 |
| :--- | :--- |
| `whisper-server` | Linux 64位无依赖独立可执行文件 |
| `config.yaml` | 生产环境配置文件（已将 whisper 地址设为 `http://127.0.0.1:8081`） |
| `start.sh` | 脚本启动（后台 nohup 运行） |
| `stop.sh` | 脚本停止 |
| `restart.sh` | 脚本重启 |
| `whisper-server.service` | Linux Systemd 系统服务配置文件（推荐） |

---

## 🚀 部署步骤

### 步骤 1：安装 Linux 系统依赖 (ffmpeg)
音频上传后需要 ffmpeg 进行格式转码与探测，请在 Linux 服务器上安装：
```bash
# Ubuntu / Debian
sudo apt update && sudo apt install -y ffmpeg

# CentOS / RHEL / Rocky Linux / AlmaLinux
sudo yum install -y epel-release && sudo yum install -y ffmpeg
```
验证安装：
```bash
ffmpeg -version
ffprobe -version
```

---

### 步骤 2：上传发布包到 Linux 服务器
将 `deploy` 目录下的所有文件上传到服务器的部署目录（例如 `/opt/whisper-server`）：
```bash
# 在 Linux 服务器上创建部署目录
sudo mkdir -p /opt/whisper-server

# 通过 scp 上传（在本地终端执行）：
# scp -r d:/scysWorks/huaweiWhisper/server/deploy/* root@<服务器IP>:/opt/whisper-server/
```

进入服务器目录并赋予执行权限：
```bash
cd /opt/whisper-server
chmod +x whisper-server *.sh
```

---

### 步骤 3：启动服务

#### 方式 A：使用 Systemd 系统服务托管（推荐，开机自启、崩溃自愈）
1. 复制 service 文件至系统目录：
   ```bash
   sudo cp whisper-server.service /etc/systemd/system/
   sudo systemctl daemon-reload
   ```
2. 启动服务并设置开机自启：
   ```bash
   sudo systemctl enable whisper-server
   sudo systemctl start whisper-server
   ```
3. 查看运行状态与日志：
   ```bash
   sudo systemctl status whisper-server
   journalctl -u whisper-server -f
   ```

#### 方式 B：使用 Shell 脚本启动
```bash
# 启动
./start.sh

# 停止
./stop.sh

# 重启
./restart.sh

# 查看日志
tail -f server.log
```

---

### 步骤 4：防火墙放行端口
请在服务器防火墙及云厂商安全组中放行 **`8080`** 端口：
```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 8080/tcp

# Firewalld (CentOS/RHEL)
sudo firewall-cmd --zone=public --add-port=8080/tcp --permanent
sudo firewall-cmd --reload
```

---

### 步骤 5：验证服务健康状态
在终端或浏览器中访问健康检查接口：
```bash
curl http://127.0.0.1:8080/api/health
```
响应示例：
```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "server": "ok",
    "ffmpeg": "available",
    "whisper_asr": "healthy",
    "deepseek_llm": "healthy",
    "queue_length": 0
  }
}
```
验证成功后，即可在手机端「智聆转写」App 设置中填入您的服务器外网 IP（例如 `http://<服务器外网IP>:8080`）完成连接！
