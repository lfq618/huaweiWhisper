# Go后端自动转码后调用Whisper固定流程

> 适用场景：客户端上传 `m4a/mp3/aac/wav` 等音频，Go 后端统一先转码，再调用 `whisper-server` 转写。  
> 目标：避免直接上传压缩音频到 `whisper-server` 出现 `Invalid request`。

---

## 1. 固定流程（必须按顺序）

1. 接收上传文件，落盘到临时目录（保留原始后缀）
2. 用 `ffmpeg` 转为 `16kHz + 单声道 + pcm_s16le + wav`
3. 调 `POST /inference` 上传转码后的 wav 文件
4. 解析 `{"text":"..."}`，写入业务结果
5. 清理临时文件（原文件 + 转码文件）

---

## 2. 转码标准（统一口径）

- 采样率：`16000`
- 声道：`1`
- 编码：`pcm_s16le`
- 封装：`wav`

等价命令：

```bash
ffmpeg -y -i input.m4a -ar 16000 -ac 1 -c:a pcm_s16le output.wav
```

---

## 3. Whisper请求标准（统一口径）

- 地址：`http://127.0.0.1:8081/inference`（推荐 Go 与 whisper 同机走本地回环）
- 方法：`POST`
- 类型：`multipart/form-data`
- 字段：
  - `file=@xxx.wav`
  - `temperature=0.0`
  - `response_format=json`

示例：

```bash
curl -sS -X POST "http://127.0.0.1:8081/inference" \
  -F "file=@/tmp/test.wav" \
  -F "temperature=0.0" \
  -F "response_format=json"
```

---

## 4. Go实现模板（可直接迁移）

```go
package asr

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

type WhisperResponse struct {
	Text string `json:"text"`
}

func ConvertToWav(ctx context.Context, inputPath, outputPath string) error {
	cmd := exec.CommandContext(ctx, "ffmpeg",
		"-y",
		"-i", inputPath,
		"-ar", "16000",
		"-ac", "1",
		"-c:a", "pcm_s16le",
		outputPath,
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("ffmpeg转码失败: %w, output=%s", err, string(out))
	}
	return nil
}

func CallWhisper(ctx context.Context, whisperURL, wavPath string) (string, error) {
	file, err := os.Open(wavPath)
	if err != nil {
		return "", fmt.Errorf("打开wav失败: %w", err)
	}
	defer file.Close()

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	part, err := writer.CreateFormFile("file", filepath.Base(wavPath))
	if err != nil {
		return "", err
	}
	if _, err := io.Copy(part, file); err != nil {
		return "", err
	}
	_ = writer.WriteField("temperature", "0.0")
	_ = writer.WriteField("response_format", "json")

	if err := writer.Close(); err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", whisperURL+"/inference", body)
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	client := &http.Client{Timeout: 10 * time.Minute}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("请求whisper失败: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("whisper返回非200: status=%d body=%s", resp.StatusCode, string(respBody))
	}

	var result WhisperResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("解析whisper响应失败: %w body=%s", err, string(respBody))
	}
	return result.Text, nil
}

// ProcessUploadedAudio 固定流程入口：先转码，再调用whisper
func ProcessUploadedAudio(inputPath string) (string, error) {
	whisperURL := os.Getenv("WHISPER_SERVER_URL")
	if whisperURL == "" {
		whisperURL = "http://127.0.0.1:8081"
	}

	wavPath := inputPath + ".16k.wav"
	defer os.Remove(wavPath)

	convertCtx, cancelConvert := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancelConvert()
	if err := ConvertToWav(convertCtx, inputPath, wavPath); err != nil {
		return "", err
	}

	asrCtx, cancelASR := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancelASR()
	return CallWhisper(asrCtx, whisperURL, wavPath)
}
```

---

## 5. 错误码建议（后端对外）

- 转码失败：`50001`（含 ffmpeg 输出日志）
- Whisper失败：`50002`（含 status code + body）
- 超时：`50004`

---

## 6. 运行前检查清单

- `ffmpeg -version` 可执行
- `curl http://127.0.0.1:8081/` 可访问
- 服务器磁盘有临时文件空间
- Go 服务账号对临时目录有写权限

---

## 7. 常见坑位

- 直接把 `m4a/mp3` 传给 `/inference`，可能返回 `Invalid request`
- 用错路径（`/interface`），正确是 `/inference`
- Go 服务改走公网地址调用本机 whisper，增加失败点（优先 `127.0.0.1`）
- 没做临时文件清理，导致磁盘逐步写满
