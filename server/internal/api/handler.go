package api

import (
	"errors"
	"net/http"
	"os"
	"strconv"

	"huawei-whisper-server/internal/model"
	"huawei-whisper-server/internal/service"
	"huawei-whisper-server/internal/store"

	"github.com/gin-gonic/gin"
)

type Handler struct {
	transcribeService *service.TranscribeService
}

func NewHandler(svc *service.TranscribeService) *Handler {
	return &Handler{
		transcribeService: svc,
	}
}

// CreateTranscribeTask handles POST /api/transcribe
func (h *Handler) CreateTranscribeTask(c *gin.Context) {
	reqID := GetRequestID(c)

	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, model.Error(model.CodeErrInvalidParam, "缺少必填参数: file (音频文件)", reqID))
		return
	}

	lang := c.DefaultPostForm("lang", "zh")
	needPolishStr := c.DefaultPostForm("need_polish", "false")
	needPolish := needPolishStr == "true" || needPolishStr == "1"
	clientTraceID := c.PostForm("client_trace_id")

	task, errCode, isExisting, err := h.transcribeService.CreateTask(c.Request.Context(), file, lang, needPolish, clientTraceID, reqID)
	if err != nil {
		httpStatus := http.StatusInternalServerError
		if errCode == model.CodeErrInvalidParam || errCode == model.CodeErrFileTooLarge || errCode == model.CodeErrAudioTooLong {
			httpStatus = http.StatusBadRequest
		} else if errCode == model.CodeErrQueueFull {
			httpStatus = http.StatusTooManyRequests
		}
		c.JSON(httpStatus, model.Error(errCode, err.Error(), reqID))
		return
	}

	result := model.CreateTaskResult{
		TaskID:        task.TaskID,
		Status:        task.Status,
		IsExisting:    isExisting,
		ClientTraceID: clientTraceID,
	}
	c.JSON(http.StatusOK, model.Accepted(result, reqID))
}

// GetTranscribeTask handles GET /api/transcribe/:task_id
func (h *Handler) GetTranscribeTask(c *gin.Context) {
	reqID := GetRequestID(c)
	taskID := c.Param("task_id")

	if taskID == "" {
		c.JSON(http.StatusBadRequest, model.Error(model.CodeErrInvalidParam, "缺少 task_id 参数", reqID))
		return
	}

	task, err := h.transcribeService.GetTask(taskID)
	if err != nil {
		if errors.Is(err, store.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, model.Error(model.CodeErrTaskNotFound, "任务不存在", reqID))
			return
		}
		c.JSON(http.StatusInternalServerError, model.Error(model.CodeErrInternal, err.Error(), reqID))
		return
	}

	dto := task.ToDTO()
	c.JSON(http.StatusOK, model.Success(dto, reqID))
}

// GetTranscribeAudio handles GET /api/transcribe/:task_id/audio
func (h *Handler) GetTranscribeAudio(c *gin.Context) {
	reqID := GetRequestID(c)
	taskID := c.Param("task_id")

	if taskID == "" {
		c.JSON(http.StatusBadRequest, model.Error(model.CodeErrInvalidParam, "缺少 task_id 参数", reqID))
		return
	}

	task, err := h.transcribeService.GetTask(taskID)
	if err != nil {
		if errors.Is(err, store.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, model.Error(model.CodeErrTaskNotFound, "任务不存在", reqID))
			return
		}
		c.JSON(http.StatusInternalServerError, model.Error(model.CodeErrInternal, err.Error(), reqID))
		return
	}

	if task.SourceFilePath == "" {
		c.JSON(http.StatusNotFound, model.Error(model.CodeErrTaskNotFound, "音频文件路径不存在", reqID))
		return
	}

	if _, err := os.Stat(task.SourceFilePath); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, model.Error(model.CodeErrTaskNotFound, "音频文件已不存在或已被清理", reqID))
		return
	}

	c.File(task.SourceFilePath)
}

// RetryTranscribeTask handles POST /api/transcribe/:task_id/retry
func (h *Handler) RetryTranscribeTask(c *gin.Context) {
	reqID := GetRequestID(c)
	taskID := c.Param("task_id")

	if taskID == "" {
		c.JSON(http.StatusBadRequest, model.Error(model.CodeErrInvalidParam, "缺少 task_id 参数", reqID))
		return
	}

	task, err := h.transcribeService.RetryTask(taskID)
	if err != nil {
		if errors.Is(err, store.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, model.Error(model.CodeErrTaskNotFound, "任务不存在", reqID))
			return
		}
		c.JSON(http.StatusInternalServerError, model.Error(model.CodeErrInternal, err.Error(), reqID))
		return
	}

	c.JSON(http.StatusOK, model.Accepted(task.ToDTO(), reqID))
}

// DeleteTranscribeTask handles DELETE /api/transcribe/:task_id
func (h *Handler) DeleteTranscribeTask(c *gin.Context) {
	reqID := GetRequestID(c)
	taskID := c.Param("task_id")

	if taskID == "" {
		c.JSON(http.StatusBadRequest, model.Error(model.CodeErrInvalidParam, "缺少 task_id 参数", reqID))
		return
	}

	if err := h.transcribeService.DeleteTask(taskID); err != nil {
		if errors.Is(err, store.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, model.Error(model.CodeErrTaskNotFound, "任务不存在", reqID))
			return
		}
		c.JSON(http.StatusInternalServerError, model.Error(model.CodeErrInternal, err.Error(), reqID))
		return
	}

	c.JSON(http.StatusOK, model.Success(gin.H{"deleted": true, "task_id": taskID}, reqID))
}

// ListTasks handles GET /api/tasks
func (h *Handler) ListTasks(c *gin.Context) {
	reqID := GetRequestID(c)

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	statusFilter := c.Query("status")

	tasks, total, err := h.transcribeService.ListTasks(limit, offset, statusFilter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, model.Error(model.CodeErrInternal, err.Error(), reqID))
		return
	}

	dtos := make([]model.TranscribeTaskDTO, 0, len(tasks))
	for _, t := range tasks {
		dtos = append(dtos, t.ToDTO())
	}

	c.JSON(http.StatusOK, model.Success(gin.H{
		"total":  total,
		"limit":  limit,
		"offset": offset,
		"list":   dtos,
	}, reqID))
}

// GetStats handles GET /api/stats
func (h *Handler) GetStats(c *gin.Context) {
	reqID := GetRequestID(c)
	stats := h.transcribeService.GetStats(c.Request.Context())
	c.JSON(http.StatusOK, model.Success(stats, reqID))
}

// HealthCheck handles GET /api/health
func (h *Handler) HealthCheck(c *gin.Context) {
	reqID := GetRequestID(c)
	healthInfo := h.transcribeService.CheckHealth(c.Request.Context())
	c.JSON(http.StatusOK, model.Success(healthInfo, reqID))
}
