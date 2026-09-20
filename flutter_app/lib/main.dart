import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'models/transcribe_task.dart';
import 'providers/record_provider.dart';
import 'providers/transcribe_provider.dart';
import 'services/api_service.dart';
import 'services/audio_record_service.dart';
import 'services/notification_service.dart';
import 'services/share_intent_service.dart';
import 'services/storage_service.dart';
import 'views/home_page.dart';
import 'views/task_detail_page.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    // .env 未配置或不存在时优雅回退
  }
  await StorageService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late final ApiService _apiService;
  late final AudioRecordService _recordService;
  late final ShareIntentService _shareIntentService;
  late final TranscribeProvider _transcribeProvider;
  late final RecordProvider _recordProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService();
    _recordService = AudioRecordService();
    _shareIntentService = ShareIntentService();

    _transcribeProvider = TranscribeProvider(_apiService);
    _recordProvider = RecordProvider(_recordService);

    // 1. 初始化系统本地通知服务与点击直达
    NotificationService.instance.init(
      onNotificationTap: (taskId) {
        final task = _transcribeProvider.allTasks.firstWhere(
          (t) => t.taskId == taskId,
          orElse: () => TranscribeTask(taskId: taskId),
        );
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => TaskDetailPage(task: task),
          ),
        );
      },
    );
    NotificationService.instance.requestPermissions();

    // 2. 监听系统录音机分享接收 (Share Intent)
    _shareIntentService.init(
      onSharedFile: (filePath) {
        if (filePath.isNotEmpty) {
          _transcribeProvider.uploadAudioFile(filePath);
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 当 App 从后台切回前台（resumed）时，立即同步正在转写或历史任务
    if (state == AppLifecycleState.resumed) {
      _transcribeProvider.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareIntentService.dispose();
    _recordProvider.dispose();
    _transcribeProvider.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: _apiService),
        Provider<AudioRecordService>.value(value: _recordService),
        ChangeNotifierProvider<TranscribeProvider>.value(value: _transcribeProvider),
        ChangeNotifierProvider<RecordProvider>.value(value: _recordProvider),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: AppConfig.appName,
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: const HomePage(),
      ),
    );
  }
}
