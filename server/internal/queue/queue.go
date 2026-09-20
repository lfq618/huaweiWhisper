package queue

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"huawei-whisper-server/internal/audio"
	"huawei-whisper-server/internal/config"
	"huawei-whisper-server/internal/llm"
	"huawei-whisper-server/internal/model"
	"huawei-whisper-server/internal/store"
	"huawei-whisper-server/internal/whisper"
)

type TranscribeQueue struct {
	tasksChan chan *model.TranscribeTask
	cfg       *config.Config
	store     store.TaskStore
	converter *audio.AudioConverter
	whisper   *whisper.Client
	llm       llm.PolishClient
	ctx       context.Context
	cancel    context.CancelFunc
	wg        sync.WaitGroup
	isWorking bool
	mu        sync.RWMutex
}

func NewTranscribeQueue(
	cfg *config.Config,
	store store.TaskStore,
	converter *audio.AudioConverter,
	whisperClient *whisper.Client,
	llmClient llm.PolishClient,
) *TranscribeQueue {
	ctx, cancel := context.WithCancel(context.Background())
	capacity := cfg.Transcribe.QueueCapacity
	if capacity <= 0 {
		capacity = 100
	}

	return &TranscribeQueue{
		tasksChan: make(chan *model.TranscribeTask, capacity),
		cfg:       cfg,
		store:     store,
		converter: converter,
		whisper:   whisperClient,
		llm:       llmClient,
		ctx:       ctx,
		cancel:    cancel,
	}
}

func (q *TranscribeQueue) Start() {
	q.wg.Add(1)
	go q.worker()
	log.Println("[Queue] 串行转写 Worker 已启动 (单 worker 模式，适配 2核2G 服务器)")
}

func (q *TranscribeQueue) Stop() {
	q.cancel()
	close(q.tasksChan)
	q.wg.Wait()
	log.Println("[Queue] 转写 Worker 已安全停止")
}

func (q *TranscribeQueue) Enqueue(task *model.TranscribeTask) bool {
	select {
	case q.tasksChan <- task:
		return true
	default:
		return false
	}
}

func (q *TranscribeQueue) EnqueueMany(tasks []*model.TranscribeTask) int {
	enqueued := 0
	for _, t := range tasks {
		if q.Enqueue(t) {
			enqueued++
		} else {
			log.Printf("[Queue] 队列已满，无法恢复任务 %s", t.TaskID)
		}
	}
	return enqueued
}

func (q *TranscribeQueue) GetQueueLength() int {
	return len(q.tasksChan)
}

func (q *TranscribeQueue) IsActive() bool {
	q.mu.RLock()
	defer q.mu.RUnlock()
	return q.isWorking
}

func (q *TranscribeQueue) setWorking(working bool) {
	q.mu.Lock()
	q.isWorking = working
	q.mu.Unlock()
}

func (q *TranscribeQueue) worker() {
	defer q.wg.Done()

	for {
		select {
		case <-q.ctx.Done():
			return
		case task, ok := <-q.tasksChan:
			if !ok {
				return
			}
			q.setWorking(true)
			q.processTaskWithRetry(task)
			q.setWorking(false)
		}
	}
}

func (q *TranscribeQueue) processTaskWithRetry(task *model.TranscribeTask) {
	maxRetries := task.MaxRetries
	if maxRetries <= 0 {
		maxRetries = q.cfg.Transcribe.MaxRetries
	}

	for attempt := task.RetryCount; attempt <= maxRetries; attempt++ {
		task.RetryCount = attempt
		success, shouldRetry := q.executeSingleTask(task)
		if success {
			return
		}

		if !shouldRetry || attempt >= maxRetries {
			log.Printf("[Worker] 任务 %s 达到最大重试次数 (%d/%d)，标记为失败", task.TaskID, attempt, maxRetries)
			return
		}

		// Exponential backoff: 2s, 4s, etc.
		backoff := time.Duration(1<<attempt) * time.Second
		log.Printf("[Worker] 任务 %s 执行失败，将在 %v 后进行第 %d 次重试...", task.TaskID, backoff, attempt+1)

		select {
		case <-q.ctx.Done():
			return
		case <-time.After(backoff):
		}
	}
}

// executeSingleTask returns (success, shouldRetry)
func (q *TranscribeQueue) executeSingleTask(task *model.TranscribeTask) (bool, bool) {
	startTime := time.Now()
	log.Printf("[Worker] 开始处理任务: %s (重试次数: %d, 文件: %s)", task.TaskID, task.RetryCount, task.SourceFilePath)

	// Update status -> processing
	_ = q.store.UpdateStatus(task.TaskID, model.StatusProcessing, "", "", 0, "", 0, task.RetryCount)

	// 检查源音频文件是否存在
	if _, err := os.Stat(task.SourceFilePath); os.IsNotExist(err) {
		durationMs := time.Since(startTime).Milliseconds()
		errMsg := fmt.Sprintf("源音频文件不存在: %s", task.SourceFilePath)
		log.Printf("[Worker] 任务 %s 失败: %s", task.TaskID, errMsg)
		_ = q.store.UpdateStatus(task.TaskID, model.StatusFailed, "", "", model.CodeErrInvalidParam, errMsg, durationMs, task.RetryCount)
		return false, false // 不重试
	}

	// Step 1: 转码 (统一转为 16kHz mono pcm_s16le WAV)
	wavFilename := fmt.Sprintf("%s.16k.wav", task.TaskID)
	wavPath := filepath.Join(q.cfg.Transcribe.TempDir, wavFilename)
	defer os.Remove(wavPath) // 无论成功或失败，及时清理临时 wav 文件

	err := q.converter.ConvertToWav16kMono(q.ctx, task.SourceFilePath, wavPath)
	if err != nil {
		durationMs := time.Since(startTime).Milliseconds()
		code := model.CodeErrTranscode
		if strings.Contains(err.Error(), "超时") {
			code = model.CodeErrTimeout
		}
		errMsg := fmt.Sprintf("音频转码失败: %v", err)
		log.Printf("[Worker] 任务 %s 转码失败 (code=%d): %s", task.TaskID, code, errMsg)
		_ = q.store.UpdateStatus(task.TaskID, model.StatusFailed, "", "", code, errMsg, durationMs, task.RetryCount)
		return false, true // 可重试
	}

	// Step 2: 调用 whisper.cpp HTTP 推理
	text, err := q.whisper.Transcribe(q.ctx, wavPath, task.Lang)
	if err != nil {
		durationMs := time.Since(startTime).Milliseconds()
		code := model.CodeErrWhisperInfer
		if strings.Contains(err.Error(), "timeout") || strings.Contains(err.Error(), "deadline") {
			code = model.CodeErrTimeout
		}
		errMsg := fmt.Sprintf("ASR 推理失败: %v", err)
		log.Printf("[Worker] 任务 %s 推理失败 (code=%d): %s", task.TaskID, code, errMsg)
		_ = q.store.UpdateStatus(task.TaskID, model.StatusFailed, "", "", code, errMsg, durationMs, task.RetryCount)
		return false, true // 可重试
	}

	polishedText := ""
	// Step 3: （可选）调用 DeepSeek 大模型进行文本润色与标点修复
	if task.NeedPolish && q.llm != nil && q.llm.IsEnabled() {
		log.Printf("[Worker] 任务 %s 正在调用 DeepSeek 进行标点添加与语法润色...", task.TaskID)
		polished, polishErr := q.llm.PolishText(q.ctx, text, task.Lang)
		if polishErr != nil {
			log.Printf("[Worker] DeepSeek 润色失败 (降级保留 Whisper 原文): %v", polishErr)
			// 平滑降级，不阻塞转写成果
			polishedText = text
		} else {
			polishedText = polished
			log.Printf("[Worker] 任务 %s DeepSeek 润色完成", task.TaskID)
		}
	}

	durationMs := time.Since(startTime).Milliseconds()
	log.Printf("[Worker] 任务 %s 转写成功 (总耗时: %dms, 文本字数: %d)", task.TaskID, durationMs, len([]rune(text)))

	_ = q.store.UpdateStatus(task.TaskID, model.StatusSuccess, text, polishedText, 0, "", durationMs, task.RetryCount)

	// Step 4: （可选）自动清理源文件
	if q.cfg.Transcribe.AutoCleanupSource {
		_ = os.Remove(task.SourceFilePath)
	}

	return true, false
}
