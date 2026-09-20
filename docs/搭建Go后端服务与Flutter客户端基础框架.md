# 搭建 Go 后端服务与 Flutter 客户端基础框架

根据 @[d:\scysWorks\huaweiWhisper\docs\语音转文本自研方案.md] 的设计与技术选型，为项目创建并搭建 Go 服务和 Flutter 客户端两个子工程的基础框架。

## 目录结构设计

```
huaweiWhisper/
├── docs/                        # 方案与设计文档
├── server/                      # Go 后端服务子目录
│   ├── cmd/server/main.go       # 服务入口
│   ├── internal/
│   │   ├── api/                 # HTTP 路由、Handler、中间件（RequestID/Logger/CORS）
│   │   ├── config/              # 配置加载（环境变量与配置文件）
│   │   ├── model/               # 接口响应与任务模型定义
│   │   ├── queue/               # 串行异步任务队列与 Worker
│   │   ├── service/             # 业务编排（任务创建、查询）
│   │   ├── store/               # 任务持久化存储接口与实现（支持内存与 SQLite/本地文件）
│   │   ├── whisper/             # whisper-server HTTP 客户端封装
│   │   └── audio/               # ffmpeg 转码封装 (16kHz 单声道 wav)
│   ├── config.example.yaml
│   ├── go.mod
│   └── README.md
│
└── flutter_app/                 # Flutter 客户端子工程
    ├── pubspec.yaml             # 包含 dio, record, permission_handler, receive_sharing_intent, provider 等
    ├── android/                 # 配置麦克风录音权限、网络权限、音频文件分享接收 Intent-Filter
    ├── lib/
    │   ├── main.dart            # 应用入口与全局 Provider 注册
    │   ├── config/              # API 基础地址、全局常量与主题样式
    │   ├── models/              # 任务数据模型、API 响应模型
    │   ├── services/            # API 请求服务、录音管理服务、分享接收监听服务
    │   ├── providers/           # 任务列表与录音状态管理 (ChangeNotifier)
    │   ├── views/               # 主页面（录音转写主面板、历史记录页、设置页）
    │   └── widgets/             # 录音按钮、状态徽标、任务卡片等组件
    └── README.md
```

---

## User Review Required

> [!IMPORTANT]
> 1. **目录命名约定**：建议 Go 服务目录命名为 `server`，Flutter 客户端目录命名为 `flutter_app`（遵循 Dart 包名命名规范）。
> 2. **Go 后端框架选型**：使用轻量高效且业界标准的 **Gin** 框架，搭配串行 Channel 任务队列与 Worker 处理机制，完全契合 2核2G 内存限制。
> 3. **Flutter 客户端权限与功能**：基础框架预装 `record`（直接录制 16kHz wav）、`receive_sharing_intent`（系统录音机分享接收）、`dio`（轮询与上传），并在 AndroidManifest.xml 预置音频分享接收 intent-filter。

---

## Proposed Changes

### 1. Go 后端服务 (`server/`)

#### [NEW] `server/go.mod`
- 初始化 Go 模块 `huawei-whisper-server`，引入 `gin-gonic/gin`、`google/uuid` 等必要依赖。

#### [NEW] `server/config.example.yaml` & `server/internal/config/config.go`
- 配置项管理：服务端口（默认 8080）、whisper-server 地址（默认 `http://127.0.0.1:8081`）、音频临时目录、上传文件大小限制（50MB）、超时设置等。

#### [NEW] `server/internal/model/task.go` & `server/internal/model/response.go`
- 严格遵循文档第十节标准定义：
  - 任务状态：`queued`、`processing`、`success`、`failed`
  - 错误码规范：`40001`、`40002`、`40401`、`50001`、`50002` 等
  - 统一响应格式：`code`, `message`, `data`, `request_id`

#### [NEW] `server/internal/audio/converter.go`
- 封装 `ffmpeg` 命令行转换逻辑（检查或转码为 16kHz / mono / s16le wav）。

#### [NEW] `server/internal/whisper/client.go`
- 封装与 `whisper-server` (`/inference`) 的 multipart 表单 HTTP 交互。

#### [NEW] `server/internal/store/store.go`
- 提供任务元数据与结果的持久化/存取接口（内置线程安全的 MemoryStore 与 SQLite/文件存储扩展）。

#### [NEW] `server/internal/queue/worker.go`
- 串行 Task Queue 与单 worker 后台协程：从队列拉取任务 -> 转码 -> 调用 whisper.cpp -> 保存结果/错误 -> 更新状态机。

#### [NEW] `server/internal/api/` (handlers & router)
- 实现：
  - `POST /api/transcribe`（文件上传、入队、返回 `task_id`）
  - `GET /api/transcribe/:task_id`（状态查询与文本结果获取）
  - `GET /api/tasks`（任务历史列表查询）
  - `GET /api/health`（健康检查及后端 whisper-server 连通性）

#### [NEW] `server/cmd/server/main.go`
- 服务启动、优雅退出与生命周期管理。

---

### 2. Flutter 客户端工程 (`flutter_app/`)

#### [NEW] `flutter_app/` 初始化与 `pubspec.yaml`
- 使用 `flutter create` 初始化项目结构，引入依赖：
  - `dio: ^5.4.0`
  - `record: ^5.1.2`
  - `permission_handler: ^11.3.1`
  - `receive_sharing_intent: ^1.4.5`
  - `provider: ^6.1.2`
  - `path_provider: ^2.1.2`
  - `intl: ^0.19.0`

#### [NEW] `flutter_app/android/app/src/main/AndroidManifest.xml`
- 声明权限：`RECORD_AUDIO`, `INTERNET`, `READ_EXTERNAL_STORAGE`
- 配置 `SEND` / `SEND_MULTIPLE` 的 intent-filter，支持从华为系统录音机分享直接唤起 App 处理音频。

#### [NEW] `flutter_app/lib/` 基础业务架构
- `config/`：配置服务器 URL、API 路径与主题色彩。
- `models/`：转写任务模型、状态枚举。
- `services/`：
  - `api_service.dart`：上传、轮询任务状态（2s 间隔）、拉取历史。
  - `audio_service.dart`：麦克风录音控制（直接配置 16kHz/1channel wav）。
  - `share_service.dart`：监听外部分享文件流与冷启动接收。
- `providers/`：
  - `transcribe_provider.dart`：管理当前正在转写与历史任务列表。
  - `record_provider.dart`：管理实时录音状态、录音计时与波形反馈。
- `views/` & `widgets/`：
  - 现代化移动端 UI，包含录音主卡片、快捷操作（本地录音 / 外部导入 / 分享接收）、实时转写进度展示与历史记录抽屉/列表。

---

## Verification Plan

### Automated Tests & Compilations
1. **Go 后端构建与测试**：
   ```bash
   cd d:\scysWorks\huaweiWhisper\server
   go mod tidy
   go build -o bin/server.exe ./cmd/server
   go test ./...
   ```
2. **Flutter 客户端构建与静态检查**：
   ```bash
   cd d:\scysWorks\huaweiWhisper\flutter_app
   flutter pub get
   flutter analyze
   ```

### Manual Verification
- 验证 Go 后端启动，请求 `/api/health` 检查健康接口。
- 验证 Flutter 项目依赖解析无报错，代码目录清晰可用。
