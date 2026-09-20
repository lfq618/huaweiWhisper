# Huawei Whisper Flutter Client App

基于 Flutter 构建的高品质语音转写与 AI 智能润色移动端应用，专为 HarmonyOS 4.x / Android 设计。

## 核心特性

- **现代科技风 UI**：
  - 精致的 Indigo/Slate 质感渐变、圆角卡片与状态流转徽标。
  - 现场录音时提供**实时音频波形振幅动效 (Waveform Visualizer)** 与呼吸脉冲动画。
  - **双栏视图设计**：智能转写主面板 + 2核2G 串行队列服务大盘监控。
- **DeepSeek AI 智能润色**：
  - 首页一键开启/关闭：`✨ DeepSeek AI 智能润色（自动加标点、同音纠错、段落排版）`。
  - 任务详情页提供 **DeepSeek 润色文本 vs Whisper 原文** 双 Tab 对比与分段复制。
- **三种音频输入渠道**：
  1. **现场录音**：直录 16,000Hz 单声道 WAV，支持录音暂停/继续/取消。
  2. **华为系统录音机分享接收**：通过 Android Share Intent 接收录音机外发文件，即刻上传。
  3. **本地文件导入**：支持 WAV, MP3, M4A, AAC, OGG, FLAC, AMR 常见格式。
- **全生命周期任务管理**：
  - 实时状态自动轮询（每 2 秒一次）。
  - 任务关键词搜索与状态筛选（全部 / 处理中 / 已完成 / 失败）。
  - 失败任务一键重新转写（`/retry`）。
  - 任务及关联音频一键清理（`/delete`）。
- **服务大盘与网络预设**：
  - 实时监控服务器状态、Whisper 连通性、DeepSeek 润色状态、队列长度、平均耗时与成功率。
  - 提供本机 (127.0.0.1)、Android 模拟器 (10.0.2.2)、局域网 IP 快捷切换与一键连通性测试。

## 运行与出包

```bash
# 获取依赖
flutter pub get

# 代码静态检查与自动化测试
flutter analyze
flutter test

# 运行调试 (Windows / Android)
flutter run

# 构建发布 APK (兼容 HarmonyOS 4.x / Android)
flutter build apk --release
```
