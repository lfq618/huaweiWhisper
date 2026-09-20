package model

// Standard Error Codes defined in design doc
const (
	CodeSuccess         = 0
	CodeErrInvalidParam = 40001
	CodeErrFileTooLarge = 40002
	CodeErrAudioTooLong = 40003
	CodeErrTaskNotFound = 40401
	CodeErrQueueFull    = 42901
	CodeErrInternal     = 50000
	CodeErrTranscode    = 50001
	CodeErrWhisperInfer = 50002
	CodeErrSaveResult   = 50003
	CodeErrTimeout      = 50004
	CodeErrLLMPolish    = 50005
)

type APIResponse struct {
	Code      int         `json:"code"`
	Message   string      `json:"message"`
	Data      interface{} `json:"data"`
	RequestID string      `json:"request_id"`
}

func Success(data interface{}, requestID string) APIResponse {
	return APIResponse{
		Code:      CodeSuccess,
		Message:   "ok",
		Data:      data,
		RequestID: requestID,
	}
}

func Accepted(data interface{}, requestID string) APIResponse {
	return APIResponse{
		Code:      CodeSuccess,
		Message:   "accepted",
		Data:      data,
		RequestID: requestID,
	}
}

func Error(code int, message string, requestID string) APIResponse {
	return APIResponse{
		Code:      code,
		Message:   message,
		Data:      nil,
		RequestID: requestID,
	}
}

type ServerStats struct {
	UptimeSec       int64   `json:"uptime_sec"`
	QueueLength     int     `json:"queue_length"`
	ActiveWorkers   int     `json:"active_workers"`
	TotalTasks      int     `json:"total_tasks"`
	SuccessTasks    int     `json:"success_tasks"`
	FailedTasks     int     `json:"failed_tasks"`
	ProcessingTasks int     `json:"processing_tasks"`
	QueuedTasks     int     `json:"queued_tasks"`
	AvgDurationMs   int64   `json:"avg_duration_ms"`
	WhisperHealthy  bool    `json:"whisper_healthy"`
	LLMHealthy      bool    `json:"llm_healthy"`
	FFmpegAvailable bool    `json:"ffmpeg_available"`
}
