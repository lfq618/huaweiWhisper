package api

import (
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

func SetupRouter(handler *Handler, mode string) *gin.Engine {
	if mode != "" {
		gin.SetMode(mode)
	}

	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(RequestIDMiddleware())
	r.Use(LoggerMiddleware())

	// CORS Setup
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept", "Authorization", "X-Request-ID"},
		ExposeHeaders:    []string{"Content-Length", "X-Request-ID"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	// API Routes
	apiGroup := r.Group("/api")
	{
		apiGroup.GET("/health", handler.HealthCheck)
		apiGroup.GET("/stats", handler.GetStats)

		// Transcribe Task Management
		apiGroup.POST("/transcribe", handler.CreateTranscribeTask)
		apiGroup.GET("/transcribe/:task_id", handler.GetTranscribeTask)
		apiGroup.GET("/transcribe/:task_id/audio", handler.GetTranscribeAudio)
		apiGroup.POST("/transcribe/:task_id/retry", handler.RetryTranscribeTask)
		apiGroup.DELETE("/transcribe/:task_id", handler.DeleteTranscribeTask)

		// Task List
		apiGroup.GET("/tasks", handler.ListTasks)
	}

	return r
}
