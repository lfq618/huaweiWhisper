package audio

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type AudioConverter struct {
	Timeout time.Duration
}

func NewAudioConverter(timeoutSec int) *AudioConverter {
	timeout := 180 * time.Second
	if timeoutSec > 0 {
		timeout = time.Duration(timeoutSec) * time.Second
	}
	return &AudioConverter{Timeout: timeout}
}

// ConvertToWav16kMono converts any input audio to 16000Hz mono pcm_s16le WAV format required by whisper.cpp
func (c *AudioConverter) ConvertToWav16kMono(ctx context.Context, inputPath, outputPath string) error {
	ctx, cancel := context.WithTimeout(ctx, c.Timeout)
	defer cancel()

	// 确保输出目录存在
	if err := os.MkdirAll(filepath.Dir(outputPath), 0755); err != nil {
		return fmt.Errorf("创建转码临时目录失败: %w", err)
	}

	// 等价于: ffmpeg -y -i <input> -ar 16000 -ac 1 -c:a pcm_s16le <output>
	cmd := exec.CommandContext(ctx, "ffmpeg", "-y", "-i", inputPath,
		"-ar", "16000",
		"-ac", "1",
		"-c:a", "pcm_s16le",
		outputPath,
	)

	out, err := cmd.CombinedOutput()
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return fmt.Errorf("ffmpeg 转码超时 (%v)", c.Timeout)
		}
		return fmt.Errorf("ffmpeg 转码失败: %w, output=%s", err, strings.TrimSpace(string(out)))
	}

	return nil
}

// ProbeAudioDuration probes audio duration in seconds using ffprobe
func (c *AudioConverter) ProbeAudioDuration(ctx context.Context, filePath string) (float64, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "ffprobe",
		"-v", "error",
		"-show_entries", "format=duration",
		"-of", "default=noprint_wrappers=1:nokey=1",
		filePath,
	)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		// If ffprobe is not available or fails, return 0 without blocking
		return 0, fmt.Errorf("ffprobe 获取时长失败: %w (stderr: %s)", err, strings.TrimSpace(stderr.String()))
	}

	outStr := strings.TrimSpace(stdout.String())
	if outStr == "" || outStr == "N/A" {
		return 0, nil
	}

	duration, err := strconv.ParseFloat(outStr, 64)
	if err != nil {
		return 0, fmt.Errorf("解析音频时长失败 (%s): %w", outStr, err)
	}

	return duration, nil
}

// CheckFFmpegAvailable verifies that ffmpeg is accessible on the system
func CheckFFmpegAvailable() bool {
	cmd := exec.Command("ffmpeg", "-version")
	return cmd.Run() == nil
}

// CheckFFprobeAvailable verifies that ffprobe is accessible on the system
func CheckFFprobeAvailable() bool {
	cmd := exec.Command("ffprobe", "-version")
	return cmd.Run() == nil
}
