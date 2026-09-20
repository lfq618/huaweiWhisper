import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whisper_app/config/app_theme.dart';
import 'package:whisper_app/models/server_stats.dart';
import 'package:whisper_app/models/transcribe_task.dart';
import 'package:whisper_app/providers/record_provider.dart';
import 'package:whisper_app/providers/transcribe_provider.dart';
import 'package:whisper_app/services/api_service.dart';
import 'package:whisper_app/services/audio_record_service.dart';
import 'package:whisper_app/views/home_page.dart';
import 'package:whisper_app/views/task_detail_page.dart';

void main() {
  test('Model Serialization & DeepSeek Polish Test', () {
    final json = {
      'task_id': 'asr_20260918_0001',
      'source_file_path': '/data/uploads/meeting.wav',
      'status': 'success',
      'text': '今天下午两点开会',
      'polished_text': '今天下午两点开会。',
      'audio_duration_sec': 12.5,
      'duration_ms': 1500,
    };

    final task = TranscribeTask.fromJson(json);
    expect(task.taskId, 'asr_20260918_0001');
    expect(task.fileName, 'meeting.wav');
    expect(task.status, TaskStatus.success);
    expect(task.text, '今天下午两点开会');
    expect(task.polishedText, '今天下午两点开会。');
    expect(task.effectiveText, '今天下午两点开会。');
    expect(task.audioDurationSec, 12.5);
    expect(task.durationMs, 1500);
    expect(task.isCompleted, true);

    final statsJson = {
      'uptime_sec': 3600,
      'queue_length': 0,
      'total_tasks': 10,
      'success_tasks': 9,
      'failed_tasks': 1,
      'avg_duration_ms': 2500,
      'whisper_healthy': true,
      'llm_healthy': true,
      'ffmpeg_available': true,
    };
    final stats = ServerStats.fromJson(statsJson);
    expect(stats.successRate, 90.0);
    expect(stats.whisperHealthy, true);
    expect(stats.llmHealthy, true);
  });

  testWidgets('App smoke test - verifies modern home page and tabs load', (WidgetTester tester) async {
    final apiService = ApiService();
    final recordService = AudioRecordService();
    final transcribeProvider = TranscribeProvider(apiService, autoFetch: false);
    final recordProvider = RecordProvider(recordService);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: apiService),
          Provider<AudioRecordService>.value(value: recordService),
          ChangeNotifierProvider<TranscribeProvider>.value(value: transcribeProvider),
          ChangeNotifierProvider<RecordProvider>.value(value: recordProvider),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const HomePage(),
        ),
      ),
    );

    // Verify key UI elements render
    expect(find.text('智聆转写'), findsOneWidget);
    expect(find.text('录音与转写'), findsOneWidget);
    expect(find.text('服务大盘'), findsOneWidget);
    expect(find.text('DeepSeek AI 智能润色'), findsOneWidget);
    expect(find.text('点击麦克风开始现场录音'), findsOneWidget);

    transcribeProvider.dispose();
    recordProvider.dispose();
  });

  testWidgets('TaskDetailPage renders docs/ui design elements and tabs', (WidgetTester tester) async {
    final apiService = ApiService();
    final transcribeProvider = TranscribeProvider(apiService, autoFetch: false);

    final mockTask = TranscribeTask(
      taskId: 'asr_20260920_test01',
      status: TaskStatus.success,
      text: '这是原始转写文字内容。关于无人机机场架构。',
      polishedText: '这是经 DeepSeek 润色后的文字内容：关于无人机基地与起降塔台核心架构。',
      audioDurationSec: 488, // 08:08
      durationMs: 5500, // 5.5s
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: apiService),
          ChangeNotifierProvider<TranscribeProvider>.value(value: transcribeProvider),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: TaskDetailPage(task: mockTask),
        ),
      ),
    );

    // 1. Verify Header
    expect(find.text('转写详情'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);

    // 2. Verify Metadata bar
    expect(find.text('08:08'), findsWidgets);
    expect(find.text('耗时 5.5秒'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);

    // 3. Verify Audio Player controls
    expect(find.text('1.0x'), findsOneWidget);
    expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);

    // 4. Verify Segmented Switch
    expect(find.text('AI 润色稿'), findsOneWidget);
    expect(find.text('原始转写'), findsOneWidget);
    expect(find.text('复制全文'), findsOneWidget);

    // 5. Verify Polished text displayed
    expect(find.textContaining('经 DeepSeek 润色后的文字内容'), findsOneWidget);

    // 6. Test tab switch to raw text
    await tester.tap(find.text('原始转写'));
    await tester.pumpAndSettle();
    expect(find.textContaining('这是原始转写文字内容'), findsOneWidget);

    // 7. Test speed switch
    await tester.tap(find.text('1.0x'));
    await tester.pumpAndSettle();
    expect(find.text('1.25x'), findsOneWidget);

    transcribeProvider.dispose();
  });
}
