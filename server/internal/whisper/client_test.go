package whisper

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestWhisperClient_Transcribe_Success(t *testing.T) {
	// Mock whisper.cpp HTTP server
	mockServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/inference" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if r.Method != http.MethodPost {
			t.Fatalf("unexpected method: %s", r.Method)
		}

		err := r.ParseMultipartForm(10 << 20)
		if err != nil {
			t.Fatalf("failed to parse multipart form: %v", err)
		}

		file, header, err := r.FormFile("file")
		if err != nil {
			t.Fatalf("failed to get file from form: %v", err)
		}
		defer file.Close()

		if header.Filename != "test.wav" {
			t.Errorf("expected filename 'test.wav', got '%s'", header.Filename)
		}
		if r.FormValue("response_format") != "json" {
			t.Errorf("expected response_format 'json', got '%s'", r.FormValue("response_format"))
		}
		if r.FormValue("temperature") != "0.0" {
			t.Errorf("expected temperature '0.0', got '%s'", r.FormValue("temperature"))
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"text":"你好，这是Whisper语音转写测试。"}`))
	}))
	defer mockServer.Close()

	tempFile := filepath.Join(t.TempDir(), "test.wav")
	if err := os.WriteFile(tempFile, []byte("RIFF mock wav audio data"), 0644); err != nil {
		t.Fatalf("failed to create temp test wav: %v", err)
	}

	client := NewClient(mockServer.URL, 1, 0.0)
	text, err := client.Transcribe(context.Background(), tempFile, "zh")
	if err != nil {
		t.Fatalf("Transcribe failed: %v", err)
	}

	expected := "你好，这是Whisper语音转写测试。"
	if text != expected {
		t.Errorf("expected text '%s', got '%s'", expected, text)
	}
}

func TestWhisperClient_Transcribe_Non200(t *testing.T) {
	mockServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`Invalid request: unsupported format`))
	}))
	defer mockServer.Close()

	tempFile := filepath.Join(t.TempDir(), "test.wav")
	_ = os.WriteFile(tempFile, []byte("mock audio"), 0644)

	client := NewClient(mockServer.URL, 1, 0.0)
	_, err := client.Transcribe(context.Background(), tempFile, "zh")
	if err == nil {
		t.Fatalf("expected error for HTTP 400, got nil")
	}
}
