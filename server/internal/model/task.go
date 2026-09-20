package model

import "time"

type TaskStatus string

const (
	StatusQueued     TaskStatus = "queued"
	StatusProcessing TaskStatus = "processing"
	StatusSuccess    TaskStatus = "success"
	StatusFailed     TaskStatus = "failed"
)

type TranscribeTask struct {
	TaskID           string     `json:"task_id"`
	ClientTraceID    string     `json:"client_trace_id,omitempty"`
	SourceFilePath   string     `json:"source_file_path"`
	SourceFormat     string     `json:"source_format"`
	FileSizeBytes    int64      `json:"file_size_bytes"`
	AudioDurationSec float64    `json:"audio_duration_sec,omitempty"`
	Status           TaskStatus `json:"status"`
	Text             string     `json:"text"`
	PolishedText     string     `json:"polished_text,omitempty"`
	NeedPolish       bool       `json:"need_polish"`
	Lang             string     `json:"lang"`
	ErrorCode        int        `json:"error_code,omitempty"`
	ErrorMsg         string     `json:"error_msg,omitempty"`
	DurationMs       int64      `json:"duration_ms"`
	RetryCount       int        `json:"retry_count"`
	MaxRetries       int        `json:"max_retries"`
	RequestID        string     `json:"request_id"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
	StartedAt        *time.Time `json:"started_at,omitempty"`
	FinishedAt       *time.Time `json:"finished_at,omitempty"`
}

type TranscribeTaskDTO struct {
	TaskID           string     `json:"task_id"`
	Status           TaskStatus `json:"status"`
	Text             string     `json:"text"`
	PolishedText     string     `json:"polished_text,omitempty"`
	AudioDurationSec float64    `json:"audio_duration_sec,omitempty"`
	ErrorCode        string     `json:"error_code"`
	ErrorMsg         string     `json:"error_msg"`
	DurationMs       int64      `json:"duration_ms"`
	RetryCount       int        `json:"retry_count"`
	CreatedAt        time.Time  `json:"created_at"`
	FinishedAt       *time.Time `json:"finished_at,omitempty"`
}

func (t *TranscribeTask) ToDTO() TranscribeTaskDTO {
	errCodeStr := ""
	if t.ErrorCode != 0 {
		errCodeStr = string(rune(t.ErrorCode))
	}
	// Return polished text in text field if available, or both
	displayText := t.Text
	if t.PolishedText != "" {
		displayText = t.PolishedText
	}

	return TranscribeTaskDTO{
		TaskID:           t.TaskID,
		Status:           t.Status,
		Text:             displayText,
		PolishedText:     t.PolishedText,
		AudioDurationSec: t.AudioDurationSec,
		ErrorCode:        errCodeStr,
		ErrorMsg:         t.ErrorMsg,
		DurationMs:       t.DurationMs,
		RetryCount:       t.RetryCount,
		CreatedAt:        t.CreatedAt,
		FinishedAt:       t.FinishedAt,
	}
}

type CreateTaskResult struct {
	TaskID        string     `json:"task_id"`
	Status        TaskStatus `json:"status"`
	IsExisting    bool       `json:"is_existing,omitempty"`
	ClientTraceID string     `json:"client_trace_id,omitempty"`
}
