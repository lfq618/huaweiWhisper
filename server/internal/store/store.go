package store

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"huawei-whisper-server/internal/model"

	_ "modernc.org/sqlite"
)

var (
	ErrTaskNotFound = errors.New("task not found")
)

type TaskStore interface {
	Save(task *model.TranscribeTask) error
	Get(taskID string) (*model.TranscribeTask, error)
	FindByTraceID(traceID string) (*model.TranscribeTask, error)
	UpdateStatus(taskID string, status model.TaskStatus, text string, polishedText string, errCode int, errMsg string, durationMs int64, retryCount int) error
	List(limit int, offset int, statusFilter string) ([]*model.TranscribeTask, int, error)
	Delete(taskID string) error
	GetUnfinishedTasks() ([]*model.TranscribeTask, error)
	GetStats() (total int, success int, failed int, processing int, queued int, avgDurationMs int64)
	Close() error
}

type SQLiteTaskStore struct {
	db     *sql.DB
	dbPath string
}

func NewSQLiteTaskStore(dbPath string) (*SQLiteTaskStore, error) {
	if dbPath == "" {
		dbPath = "./data/tasks.db"
	}

	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("创建存储目录失败: %w", err)
	}

	// Enable WAL mode & busy timeout for high concurrency
	dsn := fmt.Sprintf("file:%s?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)", filepath.ToSlash(dbPath))
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("打开 SQLite 数据库失败: %w", err)
	}

	db.SetMaxOpenConns(1) // SQLite single-writer safe
	db.SetMaxIdleConns(1)

	store := &SQLiteTaskStore{
		db:     db,
		dbPath: dbPath,
	}

	if err := store.initSchema(); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("初始化 SQLite 表结构失败: %w", err)
	}

	// 自动数据迁移：如果从 tasks.json 升级，自动迁移已有数据到 SQLite
	store.migrateFromJSONIfExists()

	var count int
	_ = db.QueryRow("SELECT COUNT(*) FROM transcribe_tasks").Scan(&count)
	log.Printf("[Store] SQLite 数据库已连接 (%s), 当前已存储 %d 条任务记录", dbPath, count)

	return store, nil
}

// initSchema creates table and indexes if not exists
func (s *SQLiteTaskStore) initSchema() error {
	schema := `
	CREATE TABLE IF NOT EXISTS transcribe_tasks (
		task_id TEXT PRIMARY KEY,
		client_trace_id TEXT,
		source_file_path TEXT NOT NULL,
		source_format TEXT NOT NULL,
		file_size_bytes INTEGER NOT NULL,
		audio_duration_sec REAL DEFAULT 0,
		status TEXT NOT NULL,
		text TEXT DEFAULT '',
		polished_text TEXT DEFAULT '',
		need_polish INTEGER DEFAULT 0,
		lang TEXT DEFAULT 'zh',
		error_code INTEGER DEFAULT 0,
		error_msg TEXT DEFAULT '',
		duration_ms INTEGER DEFAULT 0,
		retry_count INTEGER DEFAULT 0,
		max_retries INTEGER DEFAULT 2,
		request_id TEXT DEFAULT '',
		created_at TIMESTAMP NOT NULL,
		updated_at TIMESTAMP NOT NULL,
		started_at TIMESTAMP,
		finished_at TIMESTAMP
	);

	CREATE INDEX IF NOT EXISTS idx_tasks_client_trace_id ON transcribe_tasks(client_trace_id);
	CREATE INDEX IF NOT EXISTS idx_tasks_status ON transcribe_tasks(status);
	CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON transcribe_tasks(created_at DESC);
	`
	_, err := s.db.Exec(schema)
	return err
}

// migrateFromJSONIfExists reads tasks.json if present in data dir and imports into sqlite
func (s *SQLiteTaskStore) migrateFromJSONIfExists() {
	jsonPath := filepath.Join(filepath.Dir(s.dbPath), "tasks.json")
	if _, err := os.Stat(jsonPath); os.IsNotExist(err) {
		return
	}

	data, err := os.ReadFile(jsonPath)
	if err != nil || len(data) == 0 {
		return
	}

	var taskList []*model.TranscribeTask
	if err := json.Unmarshal(data, &taskList); err != nil {
		return
	}

	imported := 0
	for _, task := range taskList {
		if task == nil || task.TaskID == "" {
			continue
		}
		// If task not already in SQLite, insert it
		var exists int
		_ = s.db.QueryRow("SELECT COUNT(*) FROM transcribe_tasks WHERE task_id = ?", task.TaskID).Scan(&exists)
		if exists == 0 {
			if err := s.Save(task); err == nil {
				imported++
			}
		}
	}

	if imported > 0 {
		log.Printf("[Migration] 成功将 %d 条历史任务从 %s 迁移导入至 SQLite 数据库", imported, jsonPath)
	}
}

func (s *SQLiteTaskStore) Close() error {
	return s.db.Close()
}

func (s *SQLiteTaskStore) Save(task *model.TranscribeTask) error {
	now := time.Now()
	if task.CreatedAt.IsZero() {
		task.CreatedAt = now
	}
	task.UpdatedAt = now

	query := `
	INSERT INTO transcribe_tasks (
		task_id, client_trace_id, source_file_path, source_format, file_size_bytes,
		audio_duration_sec, status, text, polished_text, need_polish, lang,
		error_code, error_msg, duration_ms, retry_count, max_retries, request_id,
		created_at, updated_at, started_at, finished_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	ON CONFLICT(task_id) DO UPDATE SET
		client_trace_id=excluded.client_trace_id,
		source_file_path=excluded.source_file_path,
		source_format=excluded.source_format,
		file_size_bytes=excluded.file_size_bytes,
		audio_duration_sec=excluded.audio_duration_sec,
		status=excluded.status,
		text=excluded.text,
		polished_text=excluded.polished_text,
		need_polish=excluded.need_polish,
		lang=excluded.lang,
		error_code=excluded.error_code,
		error_msg=excluded.error_msg,
		duration_ms=excluded.duration_ms,
		retry_count=excluded.retry_count,
		max_retries=excluded.max_retries,
		request_id=excluded.request_id,
		updated_at=excluded.updated_at,
		started_at=excluded.started_at,
		finished_at=excluded.finished_at;
	`

	needPolishInt := 0
	if task.NeedPolish {
		needPolishInt = 1
	}

	var startedAtStr, finishedAtStr *string
	if task.StartedAt != nil {
		s := task.StartedAt.Format(time.RFC3339Nano)
		startedAtStr = &s
	}
	if task.FinishedAt != nil {
		s := task.FinishedAt.Format(time.RFC3339Nano)
		finishedAtStr = &s
	}

	_, err := s.db.Exec(
		query,
		task.TaskID,
		task.ClientTraceID,
		task.SourceFilePath,
		task.SourceFormat,
		task.FileSizeBytes,
		task.AudioDurationSec,
		string(task.Status),
		task.Text,
		task.PolishedText,
		needPolishInt,
		task.Lang,
		task.ErrorCode,
		task.ErrorMsg,
		task.DurationMs,
		task.RetryCount,
		task.MaxRetries,
		task.RequestID,
		task.CreatedAt.Format(time.RFC3339Nano),
		task.UpdatedAt.Format(time.RFC3339Nano),
		startedAtStr,
		finishedAtStr,
	)

	return err
}

func (s *SQLiteTaskStore) scanTask(scanner interface{ Scan(dest ...any) error }) (*model.TranscribeTask, error) {
	var task model.TranscribeTask
	var clientTraceID, polishedText, lang, errorMsg, requestID sql.NullString
	var createdAtStr, updatedAtStr sql.NullString
	var startedAtStr, finishedAtStr sql.NullString
	var needPolishInt int
	var statusStr string

	err := scanner.Scan(
		&task.TaskID,
		&clientTraceID,
		&task.SourceFilePath,
		&task.SourceFormat,
		&task.FileSizeBytes,
		&task.AudioDurationSec,
		&statusStr,
		&task.Text,
		&polishedText,
		&needPolishInt,
		&lang,
		&task.ErrorCode,
		&errorMsg,
		&task.DurationMs,
		&task.RetryCount,
		&task.MaxRetries,
		&requestID,
		&createdAtStr,
		&updatedAtStr,
		&startedAtStr,
		&finishedAtStr,
	)
	if err != nil {
		return nil, err
	}

	task.Status = model.TaskStatus(statusStr)
	task.ClientTraceID = clientTraceID.String
	task.PolishedText = polishedText.String
	task.NeedPolish = needPolishInt == 1
	task.Lang = lang.String
	task.ErrorMsg = errorMsg.String
	task.RequestID = requestID.String

	if createdAtStr.Valid {
		if t, err := time.Parse(time.RFC3339Nano, createdAtStr.String); err == nil {
			task.CreatedAt = t
		} else if t, err := time.Parse("2006-01-02 15:04:05", createdAtStr.String); err == nil {
			task.CreatedAt = t
		}
	}
	if updatedAtStr.Valid {
		if t, err := time.Parse(time.RFC3339Nano, updatedAtStr.String); err == nil {
			task.UpdatedAt = t
		} else if t, err := time.Parse("2006-01-02 15:04:05", updatedAtStr.String); err == nil {
			task.UpdatedAt = t
		}
	}
	if startedAtStr.Valid && startedAtStr.String != "" {
		if t, err := time.Parse(time.RFC3339Nano, startedAtStr.String); err == nil {
			task.StartedAt = &t
		} else if t, err := time.Parse("2006-01-02 15:04:05", startedAtStr.String); err == nil {
			task.StartedAt = &t
		}
	}
	if finishedAtStr.Valid && finishedAtStr.String != "" {
		if t, err := time.Parse(time.RFC3339Nano, finishedAtStr.String); err == nil {
			task.FinishedAt = &t
		} else if t, err := time.Parse("2006-01-02 15:04:05", finishedAtStr.String); err == nil {
			task.FinishedAt = &t
		}
	}

	return &task, nil
}

func (s *SQLiteTaskStore) Get(taskID string) (*model.TranscribeTask, error) {
	query := `
	SELECT
		task_id, client_trace_id, source_file_path, source_format, file_size_bytes,
		audio_duration_sec, status, text, polished_text, need_polish, lang,
		error_code, error_msg, duration_ms, retry_count, max_retries, request_id,
		created_at, updated_at, started_at, finished_at
	FROM transcribe_tasks
	WHERE task_id = ?
	LIMIT 1;
	`
	row := s.db.QueryRow(query, taskID)
	task, err := s.scanTask(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrTaskNotFound
		}
		return nil, err
	}
	return task, nil
}

func (s *SQLiteTaskStore) FindByTraceID(traceID string) (*model.TranscribeTask, error) {
	if traceID == "" {
		return nil, ErrTaskNotFound
	}
	query := `
	SELECT
		task_id, client_trace_id, source_file_path, source_format, file_size_bytes,
		audio_duration_sec, status, text, polished_text, need_polish, lang,
		error_code, error_msg, duration_ms, retry_count, max_retries, request_id,
		created_at, updated_at, started_at, finished_at
	FROM transcribe_tasks
	WHERE client_trace_id = ?
	LIMIT 1;
	`
	row := s.db.QueryRow(query, traceID)
	task, err := s.scanTask(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrTaskNotFound
		}
		return nil, err
	}
	return task, nil
}

func (s *SQLiteTaskStore) UpdateStatus(
	taskID string,
	status model.TaskStatus,
	text string,
	polishedText string,
	errCode int,
	errMsg string,
	durationMs int64,
	retryCount int,
) error {
	now := time.Now()
	nowStr := now.Format(time.RFC3339Nano)

	// Fetch current to handle started_at correctly
	existing, err := s.Get(taskID)
	if err != nil {
		return err
	}

	var startedAtStr, finishedAtStr *string
	if existing.StartedAt != nil {
		s := existing.StartedAt.Format(time.RFC3339Nano)
		startedAtStr = &s
	} else if status == model.StatusProcessing {
		startedAtStr = &nowStr
	}

	if status == model.StatusSuccess || status == model.StatusFailed {
		finishedAtStr = &nowStr
	} else if existing.FinishedAt != nil {
		s := existing.FinishedAt.Format(time.RFC3339Nano)
		finishedAtStr = &s
	}

	finalText := existing.Text
	finalPolished := existing.PolishedText
	finalErrCode := existing.ErrorCode
	finalErrMsg := existing.ErrorMsg
	finalDuration := existing.DurationMs

	if status == model.StatusSuccess || status == model.StatusFailed {
		finalText = text
		finalPolished = polishedText
		finalErrCode = errCode
		finalErrMsg = errMsg
		finalDuration = durationMs
	}

	query := `
	UPDATE transcribe_tasks SET
		status = ?,
		updated_at = ?,
		retry_count = ?,
		started_at = ?,
		finished_at = ?,
		text = ?,
		polished_text = ?,
		error_code = ?,
		error_msg = ?,
		duration_ms = ?
	WHERE task_id = ?;
	`

	res, err := s.db.Exec(
		query,
		string(status),
		nowStr,
		retryCount,
		startedAtStr,
		finishedAtStr,
		finalText,
		finalPolished,
		finalErrCode,
		finalErrMsg,
		finalDuration,
		taskID,
	)
	if err != nil {
		return err
	}

	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrTaskNotFound
	}
	return nil
}

func (s *SQLiteTaskStore) Delete(taskID string) error {
	res, err := s.db.Exec("DELETE FROM transcribe_tasks WHERE task_id = ?", taskID)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrTaskNotFound
	}
	return nil
}

func (s *SQLiteTaskStore) List(limit int, offset int, statusFilter string) ([]*model.TranscribeTask, int, error) {
	var total int
	countQuery := "SELECT COUNT(*) FROM transcribe_tasks"
	var countArgs []interface{}
	if statusFilter != "" {
		countQuery += " WHERE status = ?"
		countArgs = append(countArgs, statusFilter)
	}
	if err := s.db.QueryRow(countQuery, countArgs...).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := `
	SELECT
		task_id, client_trace_id, source_file_path, source_format, file_size_bytes,
		audio_duration_sec, status, text, polished_text, need_polish, lang,
		error_code, error_msg, duration_ms, retry_count, max_retries, request_id,
		created_at, updated_at, started_at, finished_at
	FROM transcribe_tasks
	`
	var args []interface{}
	if statusFilter != "" {
		query += " WHERE status = ?"
		args = append(args, statusFilter)
	}
	query += " ORDER BY created_at DESC LIMIT ? OFFSET ?;"
	args = append(args, limit, offset)

	rows, err := s.db.Query(query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	list := make([]*model.TranscribeTask, 0, limit)
	for rows.Next() {
		task, err := s.scanTask(rows)
		if err != nil {
			return nil, 0, err
		}
		list = append(list, task)
	}

	return list, total, nil
}

func (s *SQLiteTaskStore) GetUnfinishedTasks() ([]*model.TranscribeTask, error) {
	query := `
	SELECT
		task_id, client_trace_id, source_file_path, source_format, file_size_bytes,
		audio_duration_sec, status, text, polished_text, need_polish, lang,
		error_code, error_msg, duration_ms, retry_count, max_retries, request_id,
		created_at, updated_at, started_at, finished_at
	FROM transcribe_tasks
	WHERE status IN ('queued', 'processing')
	ORDER BY created_at ASC;
	`
	rows, err := s.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := make([]*model.TranscribeTask, 0)
	for rows.Next() {
		task, err := s.scanTask(rows)
		if err != nil {
			return nil, err
		}
		list = append(list, task)
	}

	return list, nil
}

func (s *SQLiteTaskStore) GetStats() (total int, success int, failed int, processing int, queued int, avgDurationMs int64) {
	query := `
	SELECT
		COUNT(*),
		COALESCE(SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN status = 'processing' THEN 1 ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN status = 'queued' THEN 1 ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN status = 'success' THEN duration_ms ELSE 0 END), 0)
	FROM transcribe_tasks;
	`
	var totalSuccessDuration int64
	err := s.db.QueryRow(query).Scan(&total, &success, &failed, &processing, &queued, &totalSuccessDuration)
	if err != nil {
		return 0, 0, 0, 0, 0, 0
	}

	if success > 0 {
		avgDurationMs = totalSuccessDuration / int64(success)
	}

	return total, success, failed, processing, queued, avgDurationMs
}
