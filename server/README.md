# Huawei Whisper Go Backend Service

基于 Go 语言开发的高可靠语音转写调度后端服务，专为低配置服务器（如 2核2G Linux/CentOS）设计。

## 核心特性

- **严格协议规范**：严格遵循方案设计文档 API 契约（`POST /api/transcribe`, `GET /api/transcribe/:task_id`, `POST /retry`, `DELETE`, `GET /stats`, `GET /health`）。
- **持久化与故障自动恢复 (Crash Recovery)**：原子落盘存储，服务重启或崩溃时**自动恢复未完成的任务（`queued`/`processing`）**继续消费，做到零丢失。
- **客户端幂等性**：支持 `client_trace_id` 过滤，防止网络抖动导致的重复提交。
- **DeepSeek 文本润色与纠错**：原生集成 DeepSeek 大模型（OpenAI 兼容接口），支持在转写后自动进行标点补全、语病修饰与同音错别字修正，且异常时平滑降级。
- **串行任务调度与自动重试**：单 Worker 内存队列严格防止 Whisper 并发 OOM；支持临时错误指数退避重试（默认 2 次）。
- **音频时长探测与防护**：集成 `ffprobe` 探测时长并实施最大时长限制（默认 30 分钟），防止大文件长时间独占队列。
- **全方位可观测性**：提供 `/api/stats` 与 `/api/health` 实时监控队列深度、处理吞吐量、平均耗时与底层组件健康度。

## 快速运行

```bash
# 1. 下载依赖
go mod tidy

# 2. 配置并运行服务 (默认端口 :8080)
go run ./cmd/server/main.go -config config.example.yaml
```

## 配置项与环境变量

| 配置项 | 环境变量 | 说明 |
|---|---|---|
| `server.port` | `PORT` | HTTP 监听端口（默认 8080） |
| `whisper.url` | `WHISPER_SERVER_URL` | 本地 Whisper Server 接口地址（默认 `http://127.0.0.1:8081`） |
| `deepseek.enabled` | - | 是否启用 DeepSeek 大模型润色 |
| `deepseek.api_key` | `DEEPSEEK_API_KEY` / `LLM_API_KEY` | DeepSeek API Key |
| `deepseek.base_url` | `DEEPSEEK_BASE_URL` | DeepSeek API 地址（默认 `https://api.deepseek.com/v1`） |
| `deepseek.model` | `DEEPSEEK_MODEL` | 润色模型名称（默认 `deepseek-chat`） |
| `transcribe.max_duration_sec`| - | 允许的最大音频时长（默认 1800 秒） |
| `transcribe.max_retries` | - | 失败自动重试次数（默认 2 次） |

## API 列表

| 方法 | 路径 | 描述 |
|---|---|---|
| `GET` | `/api/health` | 服务健康检查及 Whisper/DeepSeek/FFmpeg 连通状态 |
| `GET` | `/api/stats` | 服务器运行统计（队列长度、成功率、平均耗时等） |
| `POST` | `/api/transcribe` | 上传音频创建异步转写任务（支持 `need_polish` 与 `client_trace_id`） |
| `GET` | `/api/transcribe/:task_id` | 轮询/查询任务转写状态、文本结果及耗时 |
| `POST` | `/api/transcribe/:task_id/retry`| 手动重试失败的任务 |
| `DELETE` | `/api/transcribe/:task_id` | 取消/删除任务并清理源音频文件 |
| `GET` | `/api/tasks` | 查询历史任务列表（支持 `status` 筛选与分页） |
