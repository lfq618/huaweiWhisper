package whisper

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type Client struct {
	baseURL     string
	httpClient  *http.Client
	temperature float64
}

type InferenceResponse struct {
	Text string `json:"text"`
}

func NewClient(baseURL string, timeoutMin int, temperature float64) *Client {
	if envURL := os.Getenv("WHISPER_SERVER_URL"); envURL != "" {
		baseURL = envURL
	} else if baseURL == "" {
		baseURL = "http://127.0.0.1:8081"
	}
	baseURL = strings.TrimRight(baseURL, "/")

	timeout := 10 * time.Minute
	if timeoutMin > 0 {
		timeout = time.Duration(timeoutMin) * time.Minute
	}

	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: timeout,
		},
		temperature: temperature,
	}
}

// Transcribe sends the audio file to whisper-server /inference endpoint
func (c *Client) Transcribe(ctx context.Context, filePath string, lang string) (string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("打开音频文件失败: %w", err)
	}
	defer file.Close()

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	part, err := writer.CreateFormFile("file", filepath.Base(filePath))
	if err != nil {
		return "", fmt.Errorf("创建表单文件字段失败: %w", err)
	}
	if _, err := io.Copy(part, file); err != nil {
		return "", fmt.Errorf("读取音频数据失败: %w", err)
	}

	// Parameters for whisper-server
	_ = writer.WriteField("response_format", "json")
	_ = writer.WriteField("temperature", fmt.Sprintf("%.1f", c.temperature))
	if lang != "" {
		_ = writer.WriteField("language", lang)
	} else {
		_ = writer.WriteField("language", "zh")
	}

	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("构建表单失败: %w", err)
	}

	targetURL := c.baseURL + "/inference"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, targetURL, body)
	if err != nil {
		return "", fmt.Errorf("创建请求失败: %w", err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("请求 whisper-server 失败 (%s): %w", targetURL, err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("读取响应内容失败: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("whisper-server 返回 HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	var result InferenceResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		// Fallback: try raw text if response was not json
		trimmed := strings.TrimSpace(string(respBody))
		if trimmed != "" {
			return trimmed, nil
		}
		return "", fmt.Errorf("解析 whisper-server 响应失败: %w, 原始返回: %s", err, string(respBody))
	}

	return strings.TrimSpace(result.Text), nil
}

// CheckHealth checks if whisper-server is reachable
func (c *Client) CheckHealth(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/", nil)
	if err != nil {
		return err
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}
