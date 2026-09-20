package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"huawei-whisper-server/internal/config"
)

type PolishClient interface {
	PolishText(ctx context.Context, rawText string, lang string) (string, error)
	IsEnabled() bool
	CheckHealth(ctx context.Context) error
}

type DeepSeekClient struct {
	cfg        config.DeepSeekConfig
	httpClient *http.Client
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatCompletionRequest struct {
	Model       string        `json:"model"`
	Messages    []chatMessage `json:"messages"`
	Temperature float64       `json:"temperature"`
}

type chatCompletionResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
		Type    string `json:"type"`
		Code    string `json:"code"`
	} `json:"error,omitempty"`
}

func NewDeepSeekClient(cfg config.DeepSeekConfig) *DeepSeekClient {
	timeout := time.Duration(cfg.TimeoutSec) * time.Second
	if timeout <= 0 {
		timeout = 60 * time.Second
	}

	return &DeepSeekClient{
		cfg: cfg,
		httpClient: &http.Client{
			Timeout: timeout,
		},
	}
}

func (c *DeepSeekClient) IsEnabled() bool {
	return c.cfg.Enabled && strings.TrimSpace(c.cfg.APIKey) != ""
}

const defaultSystemPrompt = `你是一个专业的语音转写文本后处理专家。你的任务是为语音识别（ASR）输出的原始文本添加合适的中文/英文标点符号，修正明显的同音错别字和口语断句，使其通顺易读。
必须严格遵守以下规则：
1. 严禁改变原句意思和事实。
2. 严禁遗漏原话中的任何有效信息，严禁扩写或添加原话中不存在的内容。
3. 严禁输出任何寒暄、解释、Markdown 引用前缀或额外说明（如“好的”、“这是修改后的文本”等）。
4. 仅直接输出润色加标点后的纯文本内容。`

func (c *DeepSeekClient) PolishText(ctx context.Context, rawText string, lang string) (string, error) {
	if !c.IsEnabled() {
		return rawText, nil
	}

	trimmed := strings.TrimSpace(rawText)
	if trimmed == "" {
		return "", nil
	}

	baseURL := strings.TrimRight(c.cfg.BaseURL, "/")
	targetURL := baseURL + "/chat/completions"

	reqBody := chatCompletionRequest{
		Model: c.cfg.Model,
		Messages: []chatMessage{
			{
				Role:    "system",
				Content: defaultSystemPrompt,
			},
			{
				Role:    "user",
				Content: fmt.Sprintf("请对以下语音转写文本进行标点添加与同音纠错：\n\n%s", trimmed),
			},
		},
		Temperature: c.cfg.Temperature,
	}

	data, err := json.Marshal(reqBody)
	if err != nil {
		return rawText, fmt.Errorf("序列化 DeepSeek 请求失败: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, targetURL, bytes.NewBuffer(data))
	if err != nil {
		return rawText, fmt.Errorf("创建 DeepSeek 请求失败: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.cfg.APIKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return rawText, fmt.Errorf("请求 DeepSeek API 失败: %w", err)
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return rawText, fmt.Errorf("读取 DeepSeek 响应失败: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return rawText, fmt.Errorf("DeepSeek API 返回 HTTP %d: %s", resp.StatusCode, string(bodyBytes))
	}

	var chatResp chatCompletionResponse
	if err := json.Unmarshal(bodyBytes, &chatResp); err != nil {
		return rawText, fmt.Errorf("解析 DeepSeek 响应失败: %w", err)
	}

	if chatResp.Error != nil {
		return rawText, fmt.Errorf("DeepSeek 错误: %s (%s)", chatResp.Error.Message, chatResp.Error.Code)
	}

	if len(chatResp.Choices) == 0 {
		return rawText, fmt.Errorf("DeepSeek 返回空 choices")
	}

	polished := strings.TrimSpace(chatResp.Choices[0].Message.Content)
	if polished == "" {
		return rawText, nil
	}

	return polished, nil
}

func (c *DeepSeekClient) CheckHealth(ctx context.Context) error {
	if !c.IsEnabled() {
		return nil
	}

	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	baseURL := strings.TrimRight(c.cfg.BaseURL, "/")
	targetURL := baseURL + "/models"

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, targetURL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.cfg.APIKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return nil
}
