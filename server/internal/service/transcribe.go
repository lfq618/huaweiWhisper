package service

import (
	"context"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"
	"time"

	"huawei-whisper-server/internal/audio"
	"huawei-whisper-server/internal/config"
	"huawei-whisper-server/internal/llm"
	"huawei-whisper-server/internal/model"
	"huawei-whisper-server/internal/queue"
	"huawei-whisper-server/internal/store"
	"huawei-whisper-server/internal/whisper"

	"github.com/google/uuid"
)

type TranscribeService struct {
	cfg       *config.Config
	store     store.TaskStore
	queue     *queue.TranscribeQueue
	converter *audio.AudioConverter
	whisper   *whisper.Client
	llm       llm.PolishClient
	startTime time.Time
}

func NewTranscribeService(
	cfg *config.Config,
	taskStore store.TaskStore,
	transcribeQueue *queue.TranscribeQueue,
	converter *audio.AudioConverter,
	whisperClient *whisper.Client,
	llmClient llm.PolishClient,
) *TranscribeService {
	return &TranscribeService{
		cfg:       cfg,
		store:     taskStore,
		queue:     transcribeQueue,
		converter: converter,
		whisper:   whisperClient,
		llm:       llmClient,
		startTime: time.Now(),
	}
}

// GenerateTaskID formats task id as asr_YYYYMMDD_XXXXXX
func GenerateTaskID() string {
	now := time.Now().Format("20060102")
	shortID := strings.ReplaceAll(uuid.New().String(), "-", "")[:8]
	return fmt.Sprintf("asr_%s_%s", now, shortID)
}

func (s *TranscribeService) CreateTask(
	ctx context.Context,
	fileHeader *multipart.FileHeader,
	lang string,
	needPolish bool,
	clientTraceID string,
	requestID string,
) (*model.TranscribeTask, int, bool, error) {
	// 1. 客户端幂等性检查 (Idempotency)
	if clientTraceID != "" {
		if existing, err := s.store.FindByTraceID(clientTraceID); err == nil && existing != nil {
			log.Printf("[Service] 命中客户端幂等 ID: %s (关联已有任务: %s, 状态: %s)", clientTraceID, existing.TaskID, existing.Status)
			return existing, model.CodeSuccess, true, nil
		}
	}

	// 2. 校验文件扩展名
	ext := strings.ToLower(filepath.Ext(fileHeader.Filename))
	if !s.cfg.IsFormatAllowed(ext) {
		return nil, model.CodeErrInvalidParam, false, fmt.Errorf("不支持的音频格式: %s (支持 %v)", ext, s.cfg.Transcribe.AllowedFormats)
	}

	// 3. 校验文件大小限制
	maxBytes := s.cfg.Transcribe.MaxFileSizeMB * 1024 * 1024
	if fileHeader.Size > maxBytes {
		return nil, model.CodeErrFileTooLarge, false, fmt.Errorf("音频文件大小 (%d 字节) 超过最大限制 %dMB", fileHeader.Size, s.cfg.Transcribe.MaxFileSizeMB)
	}

	// 4. 语言默认值
	if lang == "" {
		lang = "zh"
	}

	taskID := GenerateTaskID()
	savedFilename := fmt.Sprintf("%s%s", taskID, ext)
	savedPath := s.cfg.GetUploadFilePath(savedFilename)

	// 5. 保存上传的文件到持久化目录
	srcFile, err := fileHeader.Open()
	if err != nil {
		return nil, model.CodeErrInternal, false, fmt.Errorf("读取上传文件失败: %w", err)
	}
	defer srcFile.Close()

	destFile, err := os.Create(savedPath)
	if err != nil {
		return nil, model.CodeErrInternal, false, fmt.Errorf("创建存储文件失败: %w", err)
	}
	defer destFile.Close()

	if _, err := io.Copy(destFile, srcFile); err != nil {
		_ = os.Remove(savedPath)
		return nil, model.CodeErrInternal, false, fmt.Errorf("保存上传文件失败: %w", err)
	}

	// 6. 探测音频时长并校验
	var audioDurationSec float64 = 0
	if duration, probeErr := s.converter.ProbeAudioDuration(ctx, savedPath); probeErr == nil {
		audioDurationSec = duration
		if s.cfg.Transcribe.MaxDurationSec > 0 && duration > s.cfg.Transcribe.MaxDurationSec {
			_ = os.Remove(savedPath)
			return nil, model.CodeErrAudioTooLong, false, fmt.Errorf("音频时长 (%.1f 秒) 超过服务允许最大时长 (%.1f 秒)", duration, s.cfg.Transcribe.MaxDurationSec)
		}
	}

	// 7. 创建任务对象
	now := time.Now()
	task := &model.TranscribeTask{
		TaskID:           taskID,
		ClientTraceID:    clientTraceID,
		SourceFilePath:   savedPath,
		SourceFormat:     ext,
		FileSizeBytes:    fileHeader.Size,
		AudioDurationSec: audioDurationSec,
		Status:           model.StatusQueued,
		NeedPolish:       needPolish,
		Lang:             lang,
		MaxRetries:       s.cfg.Transcribe.MaxRetries,
		RequestID:        requestID,
		CreatedAt:        now,
		UpdatedAt:        now,
	}

	if err := s.store.Save(task); err != nil {
		_ = os.Remove(savedPath)
		return nil, model.CodeErrSaveResult, false, fmt.Errorf("任务保存失败: %w", err)
	}

	// 8. 推入串行任务队列
	if !s.queue.Enqueue(task) {
		_ = s.store.UpdateStatus(task.TaskID, model.StatusFailed, "", "", model.CodeErrQueueFull, "任务队列已满，请稍后重试", 0, 0)
		return nil, model.CodeErrQueueFull, false, fmt.Errorf("任务队列已满")
	}

	return task, model.CodeSuccess, false, nil
}

func (s *TranscribeService) GetTask(taskID string) (*model.TranscribeTask, error) {
	return s.store.Get(taskID)
}

func (s *TranscribeService) ListTasks(limit, offset int, status string) ([]*model.TranscribeTask, int, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	if offset < 0 {
		offset = 0
	}
	return s.store.List(limit, offset, status)
}

func (s *TranscribeService) RetryTask(taskID string) (*model.TranscribeTask, error) {
	task, err := s.store.Get(taskID)
	if err != nil {
		return nil, err
	}

	// 重置任务状态并重试
	task.Status = model.StatusQueued
	task.ErrorCode = 0
	task.ErrorMsg = ""
	task.RetryCount = 0
	task.UpdatedAt = time.Now()

	if err := s.store.Save(task); err != nil {
		return nil, err
	}

	if !s.queue.Enqueue(task) {
		_ = s.store.UpdateStatus(task.TaskID, model.StatusFailed, "", "", model.CodeErrQueueFull, "任务队列已满", 0, 0)
		return nil, fmt.Errorf("任务队列已满，重试失败")
	}

	return task, nil
}

func (s *TranscribeService) DeleteTask(taskID string) error {
	task, err := s.store.Get(taskID)
	if err != nil {
		return err
	}

	// 清理源音频文件
	if task.SourceFilePath != "" {
		_ = os.Remove(task.SourceFilePath)
	}

	return s.store.Delete(taskID)
}

func (s *TranscribeService) GetStats(ctx context.Context) model.ServerStats {
	total, success, failed, processing, queued, avgDuration := s.store.GetStats()
	whisperErr := s.whisper.CheckHealth(ctx)
	llmErr := s.llm.CheckHealth(ctx)

	activeWorkers := 0
	if s.queue.IsActive() {
		activeWorkers = 1
	}

	return model.ServerStats{
		UptimeSec:       int64(time.Since(s.startTime).Seconds()),
		QueueLength:     s.queue.GetQueueLength(),
		ActiveWorkers:   activeWorkers,
		TotalTasks:      total,
		SuccessTasks:    success,
		FailedTasks:     failed,
		ProcessingTasks: processing,
		QueuedTasks:     queued,
		AvgDurationMs:   avgDuration,
		WhisperHealthy:  whisperErr == nil,
		LLMHealthy:      s.llm.IsEnabled() && llmErr == nil,
		FFmpegAvailable: audio.CheckFFmpegAvailable(),
	}
}

func (s *TranscribeService) CheckHealth(ctx context.Context) map[string]interface{} {
	whisperErr := s.whisper.CheckHealth(ctx)
	whisperStatus := "healthy"
	if whisperErr != nil {
		whisperStatus = fmt.Sprintf("unreachable: %v", whisperErr)
	}

	llmStatus := "disabled"
	if s.llm.IsEnabled() {
		if err := s.llm.CheckHealth(ctx); err != nil {
			llmStatus = fmt.Sprintf("unhealthy: %v", err)
		} else {
			llmStatus = "healthy"
		}
	}

	ffmpegStatus := "available"
	if !audio.CheckFFmpegAvailable() {
		ffmpegStatus = "missing"
	}

	return map[string]interface{}{
		"server":         "ok",
		"whisper":        whisperStatus,
		"deepseek_llm":   llmStatus,
		"ffmpeg":         ffmpegStatus,
		"uptime_seconds": int64(time.Since(s.startTime).Seconds()),
		"queue_length":   s.queue.GetQueueLength(),
		"time":           time.Now().Format(time.RFC3339),
	}
}

// RecoverUnfinishedTasks recovers queued or processing tasks upon server startup
func (s *TranscribeService) RecoverUnfinishedTasks() int {
	unfinished, err := s.store.GetUnfinishedTasks()
	if err != nil || len(unfinished) == 0 {
		return 0
	}

	log.Printf("[Recovery] 发现 %d 条未完成的任务，正在恢复到串行队列继续处理...", len(unfinished))
	return s.queue.EnqueueMany(unfinished)
}
