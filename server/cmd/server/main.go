package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"huawei-whisper-server/internal/api"
	"huawei-whisper-server/internal/audio"
	"huawei-whisper-server/internal/config"
	"huawei-whisper-server/internal/llm"
	"huawei-whisper-server/internal/queue"
	"huawei-whisper-server/internal/service"
	"huawei-whisper-server/internal/store"
	"huawei-whisper-server/internal/whisper"
)

func main() {
	configPath := flag.String("config", "config.yaml", "Path to configuration YAML file")
	flag.Parse()

	log.Println("==================================================")
	log.Println("    Huawei Whisper Go Backend Server v1.0.0       ")
	log.Println("==================================================")

	// 1. 加载配置
	cfg, err := config.LoadConfig(*configPath)
	if err != nil {
		log.Printf("[Warn] 读取配置文件 %s 失败 (%v)，使用默认配置", *configPath, err)
		cfg = config.DefaultConfig()
	}

	// 2. 检查 ffmpeg 与 ffprobe 依赖
	if !audio.CheckFFmpegAvailable() {
		log.Println("[Warning] 系统中未检测到 ffmpeg 命令，如果音频需要转码可能导致失败，请确保 ffmpeg 已安装并加入系统 PATH！")
	} else {
		log.Println("[Init] ffmpeg 依赖检查正常")
	}

	if !audio.CheckFFprobeAvailable() {
		log.Println("[Warning] 系统中未检测到 ffprobe 命令，音频时长探测功能将受到限制")
	} else {
		log.Println("[Init] ffprobe 依赖检查正常")
	}

	// 3. 初始化持久化存储层 (SQLiteTaskStore)
	taskStore, err := store.NewSQLiteTaskStore(cfg.GetTasksDbPath())
	if err != nil {
		log.Fatalf("[Error] 初始化 SQLite 任务持久化存储失败: %v", err)
	}
	defer taskStore.Close()

	// 4. 初始化音视频转码、ASR 客户端与 DeepSeek LLM 润色客户端
	audioConverter := audio.NewAudioConverter(cfg.Transcribe.FFmpegTimeoutSec)
	whisperClient := whisper.NewClient(cfg.Whisper.URL, cfg.Whisper.TimeoutMin, cfg.Whisper.Temperature)
	deepseekClient := llm.NewDeepSeekClient(cfg.DeepSeek)

	if deepseekClient.IsEnabled() {
		log.Printf("[Init] DeepSeek 文本润色模块已启用 (Model: %s, BaseURL: %s)", cfg.DeepSeek.Model, cfg.DeepSeek.BaseURL)
	} else {
		log.Println("[Init] DeepSeek 文本润色模块未启用 (未配置 APIKey)")
	}

	// 5. 启动串行任务队列与 Worker
	transcribeQueue := queue.NewTranscribeQueue(cfg, taskStore, audioConverter, whisperClient, deepseekClient)
	transcribeQueue.Start()
	defer transcribeQueue.Stop()

	// 6. 初始化业务编排服务
	transcribeService := service.NewTranscribeService(cfg, taskStore, transcribeQueue, audioConverter, whisperClient, deepseekClient)

	// 7. 故障自动恢复：恢复未完成的任务 (queued / processing)
	recoveredCount := transcribeService.RecoverUnfinishedTasks()
	if recoveredCount > 0 {
		log.Printf("[Init] 成功恢复 %d 个未完成任务至队列继续消费", recoveredCount)
	}

	// 8. 注册 HTTP 路由与中间件
	handler := api.NewHandler(transcribeService)
	router := api.SetupRouter(handler, cfg.Server.Mode)

	// 9. 启动 HTTP Server
	addr := fmt.Sprintf(":%d", cfg.Server.Port)
	srv := &http.Server{
		Addr:         addr,
		Handler:      router,
		ReadTimeout:  time.Duration(cfg.Server.ReadTimeoutSec) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.WriteTimeoutSec) * time.Second,
	}

	go func() {
		log.Printf("[Server] HTTP API 服务已在 http://0.0.0.0:%d 启动\n", cfg.Server.Port)
		log.Printf("[Server] Whisper Server 地址: %s\n", cfg.Whisper.URL)
		log.Printf("[Server] 任务数据存储路径: %s\n", cfg.GetTasksDbPath())
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[Error] 启动 HTTP 服务失败: %v\n", err)
		}
	}()

	// 10. 优雅停机监听 (SIGINT, SIGTERM)
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("[Server] 接收到停机信号，正在安全关闭服务...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("[Error] 服务强制关闭: %v\n", err)
	}

	log.Println("[Server] 服务已安全退出")
}
