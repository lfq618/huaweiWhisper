package api

import (
	"fmt"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

const HeaderRequestID = "X-Request-ID"

func RequestIDMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		reqID := c.GetHeader(HeaderRequestID)
		if reqID == "" {
			reqID = "req_" + strings.ReplaceAll(uuid.New().String(), "-", "")[:8]
		}
		c.Set("request_id", reqID)
		c.Header(HeaderRequestID, reqID)
		c.Next()
	}
}

func LoggerMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		raw := c.Request.URL.RawQuery

		c.Next()

		latency := time.Since(start)
		clientIP := c.ClientIP()
		method := c.Request.Method
		statusCode := c.Writer.Status()
		reqID, _ := c.Get("request_id")

		if raw != "" {
			path = path + "?" + raw
		}

		fmt.Printf("[GIN] %v | %3d | %12v | %s | %-7s %s | req_id=%v\n",
			time.Now().Format("2006/01/02 - 15:04:05"),
			statusCode,
			latency,
			clientIP,
			method,
			path,
			reqID,
		)
	}
}

func GetRequestID(c *gin.Context) string {
	if val, exists := c.Get("request_id"); exists {
		if reqID, ok := val.(string); ok {
			return reqID
		}
	}
	return ""
}
