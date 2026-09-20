package api

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"huawei-whisper-server/internal/audio"
	"huawei-whisper-server/internal/config"
	"huawei-whisper-server/internal/llm"
	"huawei-whisper-server/internal/model"
	"huawei-whisper-server/internal/queue"
	"huawei-whisper-server/internal/service"
	"huawei-whisper-server/internal/store"
	"huawei-whisper-server/internal/whisper"
)

func setupTestServer(t *testing.T) (*httptest.Server, *service.TranscribeService, func()) {
	testDir := filepath.Join(os.TempDir(), "whisper_test_"+service.GenerateTaskID())
	_ = os.MkdirAll(testDir, 0755)

	cfg := config.DefaultConfig()
	cfg.Transcribe.DataDir = testDir
	cfg.Transcribe.UploadDir = filepath.Join(testDir, "uploads")
	cfg.Transcribe.TempDir = filepath.Join(testDir, "temp")
	_ = os.MkdirAll(cfg.Transcribe.UploadDir, 0755)
	_ = os.MkdirAll(cfg.Transcribe.TempDir, 0755)

	taskStore, err := store.NewSQLiteTaskStore(cfg.GetTasksDbPath())
	if err != nil {
		t.Fatalf("NewSQLiteTaskStore failed: %v", err)
	}

	converter := audio.NewAudioConverter(10)
	whisperClient := whisper.NewClient("http://127.0.0.1:8081", 1, 0.0)
	deepseekClient := llm.NewDeepSeekClient(cfg.DeepSeek)

	q := queue.NewTranscribeQueue(cfg, taskStore, converter, whisperClient, deepseekClient)
	q.Start()

	svc := service.NewTranscribeService(cfg, taskStore, q, converter, whisperClient, deepseekClient)
	handler := NewHandler(svc)
	router := SetupRouter(handler, "test")

	server := httptest.NewServer(router)

	cleanup := func() {
		server.Close()
		q.Stop()
		_ = os.RemoveAll(testDir)
	}

	return server, svc, cleanup
}

func TestHealthAndStatsAPI(t *testing.T) {
	ts, _, cleanup := setupTestServer(t)
	defer cleanup()

	// 1. Health API
	resp, err := http.Get(ts.URL + "/api/health")
	if err != nil {
		t.Fatalf("Health request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200, got %d", resp.StatusCode)
	}

	var res model.APIResponse
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
		t.Fatalf("Failed to decode json response: %v", err)
	}
	if res.Code != 0 {
		t.Errorf("Expected code 0, got %d", res.Code)
	}

	// 2. Stats API
	statsResp, err := http.Get(ts.URL + "/api/stats")
	if err != nil {
		t.Fatalf("Stats request failed: %v", err)
	}
	defer statsResp.Body.Close()

	if statsResp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200, got %d", statsResp.StatusCode)
	}
}

func TestTranscribeLifecycle_Idempotency_And_Management(t *testing.T) {
	ts, _, cleanup := setupTestServer(t)
	defer cleanup()

	clientTraceID := "client_test_trace_12345"

	// 1. Create task with trace ID
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", "recording.wav")
	if err != nil {
		t.Fatalf("CreateFormFile error: %v", err)
	}
	part.Write([]byte("RIFFmockwavheader0000000000000000000000000000"))
	_ = writer.WriteField("lang", "zh")
	_ = writer.WriteField("client_trace_id", clientTraceID)
	_ = writer.Close()

	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/api/transcribe", body)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("POST /api/transcribe failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200, got %d", resp.StatusCode)
	}

	var createResp model.APIResponse
	if err := json.NewDecoder(resp.Body).Decode(&createResp); err != nil {
		t.Fatalf("Decode create resp failed: %v", err)
	}
	dataMap := createResp.Data.(map[string]interface{})
	taskID := dataMap["task_id"].(string)

	// 2. Idempotency test: submit again with SAME client_trace_id
	body2 := &bytes.Buffer{}
	writer2 := multipart.NewWriter(body2)
	part2, _ := writer2.CreateFormFile("file", "recording.wav")
	part2.Write([]byte("RIFFmockwavheader0000000000000000000000000000"))
	_ = writer2.WriteField("client_trace_id", clientTraceID)
	_ = writer2.Close()

	req2, _ := http.NewRequest(http.MethodPost, ts.URL+"/api/transcribe", body2)
	req2.Header.Set("Content-Type", writer2.FormDataContentType())

	resp2, err := client.Do(req2)
	if err != nil {
		t.Fatalf("Second POST failed: %v", err)
	}
	defer resp2.Body.Close()

	var createResp2 model.APIResponse
	_ = json.NewDecoder(resp2.Body).Decode(&createResp2)
	dataMap2 := createResp2.Data.(map[string]interface{})
	if dataMap2["task_id"] != taskID {
		t.Errorf("Expected idempotent task_id %s, got %s", taskID, dataMap2["task_id"])
	}
	if dataMap2["is_existing"] != true {
		t.Errorf("Expected is_existing == true for duplicate trace ID")
	}

	// 3. Query task
	getResp, err := http.Get(ts.URL + "/api/transcribe/" + taskID)
	if err != nil {
		t.Fatalf("GET /api/transcribe failed: %v", err)
	}
	defer getResp.Body.Close()
	if getResp.StatusCode != http.StatusOK {
		t.Errorf("Expected 200 for GET task, got %d", getResp.StatusCode)
	}

	// 4. List tasks
	listResp, err := http.Get(ts.URL + "/api/tasks")
	if err != nil {
		t.Fatalf("GET /api/tasks failed: %v", err)
	}
	defer listResp.Body.Close()
	if listResp.StatusCode != http.StatusOK {
		t.Errorf("Expected 200 for List tasks, got %d", listResp.StatusCode)
	}

	// 4.1 Test Audio endpoint
	audioResp, err := http.Get(ts.URL + "/api/transcribe/" + taskID + "/audio")
	if err != nil {
		t.Fatalf("GET /api/transcribe/:task_id/audio failed: %v", err)
	}
	defer audioResp.Body.Close()
	if audioResp.StatusCode != http.StatusOK {
		t.Errorf("Expected 200 for Audio endpoint, got %d", audioResp.StatusCode)
	}

	// 5. Delete task
	delReq, _ := http.NewRequest(http.MethodDelete, ts.URL+"/api/transcribe/"+taskID, nil)
	delResp, err := client.Do(delReq)
	if err != nil {
		t.Fatalf("DELETE task failed: %v", err)
	}
	defer delResp.Body.Close()
	if delResp.StatusCode != http.StatusOK {
		t.Errorf("Expected 200 for DELETE task, got %d", delResp.StatusCode)
	}
}

func TestPersistenceAndRecovery(t *testing.T) {
	testDir := filepath.Join(os.TempDir(), "whisper_recovery_test_"+service.GenerateTaskID())
	_ = os.MkdirAll(testDir, 0755)
	defer os.RemoveAll(testDir)

	dbPath := filepath.Join(testDir, "tasks.db")

	// 1. First run: create store and save tasks
	store1, err := store.NewSQLiteTaskStore(dbPath)
	if err != nil {
		t.Fatalf("store1 init failed: %v", err)
	}

	task1 := &model.TranscribeTask{
		TaskID:         "task_001",
		Status:         model.StatusQueued,
		SourceFilePath: "/tmp/test1.wav",
		SourceFormat:   ".wav",
	}
	task2 := &model.TranscribeTask{
		TaskID:         "task_002",
		Status:         model.StatusSuccess,
		Text:           "完成的内容",
		SourceFilePath: "/tmp/test2.wav",
		SourceFormat:   ".wav",
	}

	_ = store1.Save(task1)
	_ = store1.Save(task2)
	_ = store1.Close()

	// 2. Second run: simulate restart, create new store instance pointing to same file
	store2, err := store.NewSQLiteTaskStore(dbPath)
	if err != nil {
		t.Fatalf("store2 reload failed: %v", err)
	}
	defer store2.Close()

	retrieved, err := store2.Get("task_001")
	if err != nil || retrieved.Status != model.StatusQueued {
		t.Errorf("Failed to persist and reload task_001: %v", err)
	}

	unfinished, err := store2.GetUnfinishedTasks()
	if err != nil || len(unfinished) != 1 || unfinished[0].TaskID != "task_001" {
		t.Errorf("Expected 1 unfinished task (task_001), got: %v", unfinished)
	}
}
