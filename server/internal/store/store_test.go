package store

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"huawei-whisper-server/internal/model"
)

func TestSQLiteTaskStore_CRUD_And_Migration(t *testing.T) {
	testDir := filepath.Join(os.TempDir(), "sqlite_store_test_"+fmtSprintf("%d", time.Now().UnixNano()))
	_ = os.MkdirAll(testDir, 0755)
	defer os.RemoveAll(testDir)

	// 1. Prepare legacy tasks.json for migration testing
	legacyTasks := []*model.TranscribeTask{
		{
			TaskID:         "legacy_001",
			ClientTraceID:  "trace_legacy_001",
			SourceFilePath: "/path/legacy.wav",
			SourceFormat:   ".wav",
			Status:         model.StatusSuccess,
			Text:           "历史转写数据1",
			PolishedText:   "历史转写数据1（润色）",
			DurationMs:     1200,
			CreatedAt:      time.Now().Add(-1 * time.Hour),
		},
	}
	legacyJSON, _ := json.Marshal(legacyTasks)
	_ = os.WriteFile(filepath.Join(testDir, "tasks.json"), legacyJSON, 0644)

	// 2. Initialize SQLiteTaskStore (should trigger migration)
	dbPath := filepath.Join(testDir, "tasks.db")
	store, err := NewSQLiteTaskStore(dbPath)
	if err != nil {
		t.Fatalf("NewSQLiteTaskStore failed: %v", err)
	}
	defer store.Close()

	// 3. Verify migration
	migrated, err := store.Get("legacy_001")
	if err != nil {
		t.Fatalf("Failed to retrieve migrated task: %v", err)
	}
	if migrated.Text != "历史转写数据1" || migrated.PolishedText != "历史转写数据1（润色）" {
		t.Errorf("Migrated task content mismatch: %+v", migrated)
	}

	// 4. Test Save (Insert new task)
	now := time.Now()
	newTask := &model.TranscribeTask{
		TaskID:           "task_new_100",
		ClientTraceID:    "trace_100",
		SourceFilePath:   "/path/new.wav",
		SourceFormat:     ".wav",
		FileSizeBytes:    10240,
		AudioDurationSec: 5.5,
		Status:           model.StatusQueued,
		NeedPolish:       true,
		Lang:             "zh",
		CreatedAt:        now,
	}

	if err := store.Save(newTask); err != nil {
		t.Fatalf("Save failed: %v", err)
	}

	// 5. Test FindByTraceID
	found, err := store.FindByTraceID("trace_100")
	if err != nil || found.TaskID != "task_new_100" {
		t.Fatalf("FindByTraceID failed: %v, found: %+v", err, found)
	}

	// 6. Test UpdateStatus
	err = store.UpdateStatus(
		"task_new_100",
		model.StatusSuccess,
		"识别新文字",
		"润色新文字",
		0,
		"",
		3200,
		0,
	)
	if err != nil {
		t.Fatalf("UpdateStatus failed: %v", err)
	}

	updated, err := store.Get("task_new_100")
	if err != nil {
		t.Fatalf("Get updated failed: %v", err)
	}
	if updated.Status != model.StatusSuccess || updated.Text != "识别新文字" || updated.DurationMs != 3200 {
		t.Errorf("Updated fields mismatch: %+v", updated)
	}

	// 7. Test List
	list, total, err := store.List(10, 0, "")
	if err != nil || total != 2 || len(list) != 2 {
		t.Errorf("List failed: total=%d, len=%d, err=%v", total, len(list), err)
	}

	// 8. Test Stats
	totalStats, successStats, failedStats, procStats, qStats, avgDur := store.GetStats()
	if totalStats != 2 || successStats != 2 || failedStats != 0 || procStats != 0 || qStats != 0 {
		t.Errorf("GetStats counts mismatch: total=%d, success=%d", totalStats, successStats)
	}
	if avgDur != (1200+3200)/2 {
		t.Errorf("Expected avgDuration %d, got %d", (1200+3200)/2, avgDur)
	}

	// 9. Test Delete
	if err := store.Delete("task_new_100"); err != nil {
		t.Fatalf("Delete failed: %v", err)
	}
	_, err = store.Get("task_new_100")
	if !errors.Is(err, ErrTaskNotFound) {
		t.Errorf("Expected ErrTaskNotFound after deletion, got %v", err)
	}
}

func fmtSprintf(format string, a ...interface{}) string {
	return time.Now().Format("20060102150405.000")
}
