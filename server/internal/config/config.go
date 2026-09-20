package config

import (
	"os"
	"path/filepath"
	"strconv"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server     ServerConfig     `yaml:"server"`
	Whisper    WhisperConfig    `yaml:"whisper"`
	DeepSeek   DeepSeekConfig   `yaml:"deepseek"`
	Transcribe TranscribeConfig `yaml:"transcribe"`
}

type ServerConfig struct {
	Port            int    `yaml:"port"`
	Mode            string `yaml:"mode"`
	ReadTimeoutSec  int    `yaml:"read_timeout_sec"`
	WriteTimeoutSec int    `yaml:"write_timeout_sec"`
}

type WhisperConfig struct {
	URL         string  `yaml:"url"`
	TimeoutMin  int     `yaml:"timeout_min"`
	Temperature float64 `yaml:"temperature"`
}

type DeepSeekConfig struct {
	Enabled     bool    `yaml:"enabled"`
	BaseURL     string  `yaml:"base_url"`
	APIKey      string  `yaml:"api_key"`
	Model       string  `yaml:"model"`
	TimeoutSec  int     `yaml:"timeout_sec"`
	Temperature float64 `yaml:"temperature"`
}

type TranscribeConfig struct {
	DataDir           string   `yaml:"data_dir"`
	UploadDir         string   `yaml:"upload_dir"`
	TempDir           string   `yaml:"temp_dir"`
	MaxFileSizeMB     int64    `yaml:"max_file_size_mb"`
	MaxDurationSec    float64  `yaml:"max_duration_sec"` // 0 means no limit, e.g. 1800 (30min)
	QueueCapacity     int      `yaml:"queue_capacity"`
	MaxRetries        int      `yaml:"max_retries"`
	FFmpegTimeoutSec  int      `yaml:"ffmpeg_timeout_sec"`
	AutoCleanupSource bool     `yaml:"auto_cleanup_source"`
	AllowedFormats    []string `yaml:"allowed_formats"`
}

func DefaultConfig() *Config {
	return &Config{
		Server: ServerConfig{
			Port:            8080,
			Mode:            "debug",
			ReadTimeoutSec:  60,
			WriteTimeoutSec: 600,
		},
		Whisper: WhisperConfig{
			URL:         "http://127.0.0.1:8081",
			TimeoutMin:  10,
			Temperature: 0.0,
		},
		DeepSeek: DeepSeekConfig{
			Enabled:     false,
			BaseURL:     "https://api.deepseek.com/v1",
			APIKey:      "",
			Model:       "deepseek-chat",
			TimeoutSec:  60,
			Temperature: 0.3,
		},
		Transcribe: TranscribeConfig{
			DataDir:           "./data",
			UploadDir:         "./data/uploads",
			TempDir:           "./data/temp",
			MaxFileSizeMB:     50,
			MaxDurationSec:    1800, // 30 minutes
			QueueCapacity:     100,
			MaxRetries:        2,
			FFmpegTimeoutSec:  180,
			AutoCleanupSource: false,
			AllowedFormats:    []string{".wav", ".mp3", ".m4a", ".aac", ".ogg", ".flac", ".amr"},
		},
	}
}

func LoadConfig(path string) (*Config, error) {
	cfg := DefaultConfig()

	if path != "" {
		if data, err := os.ReadFile(path); err == nil {
			if err := yaml.Unmarshal(data, cfg); err != nil {
				return nil, err
			}
		}
	}

	// Environment variable overrides
	if portStr := os.Getenv("PORT"); portStr != "" {
		if port, err := strconv.Atoi(portStr); err == nil {
			cfg.Server.Port = port
		}
	}
	if whisperURL := os.Getenv("WHISPER_SERVER_URL"); whisperURL != "" {
		cfg.Whisper.URL = whisperURL
	}
	if deepseekKey := os.Getenv("DEEPSEEK_API_KEY"); deepseekKey != "" {
		cfg.DeepSeek.APIKey = deepseekKey
		cfg.DeepSeek.Enabled = true
	} else if llmKey := os.Getenv("LLM_API_KEY"); llmKey != "" {
		cfg.DeepSeek.APIKey = llmKey
		cfg.DeepSeek.Enabled = true
	}
	if deepseekURL := os.Getenv("DEEPSEEK_BASE_URL"); deepseekURL != "" {
		cfg.DeepSeek.BaseURL = deepseekURL
	}
	if deepseekModel := os.Getenv("DEEPSEEK_MODEL"); deepseekModel != "" {
		cfg.DeepSeek.Model = deepseekModel
	}
	if uploadDir := os.Getenv("UPLOAD_DIR"); uploadDir != "" {
		cfg.Transcribe.UploadDir = uploadDir
	}
	if tempDir := os.Getenv("TEMP_DIR"); tempDir != "" {
		cfg.Transcribe.TempDir = tempDir
	}
	if mode := os.Getenv("GIN_MODE"); mode != "" {
		cfg.Server.Mode = mode
	}

	// Ensure directories exist
	_ = os.MkdirAll(cfg.Transcribe.DataDir, 0755)
	_ = os.MkdirAll(cfg.Transcribe.UploadDir, 0755)
	_ = os.MkdirAll(cfg.Transcribe.TempDir, 0755)

	return cfg, nil
}

func (c *Config) IsFormatAllowed(ext string) bool {
	for _, format := range c.Transcribe.AllowedFormats {
		if format == ext {
			return true
		}
	}
	return false
}

func (c *Config) GetUploadFilePath(filename string) string {
	return filepath.Join(c.Transcribe.UploadDir, filename)
}

func (c *Config) GetTempFilePath(filename string) string {
	return filepath.Join(c.Transcribe.TempDir, filename)
}

func (c *Config) GetTasksDbPath() string {
	return filepath.Join(c.Transcribe.DataDir, "tasks.db")
}
