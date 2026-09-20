import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const String appName = '智聆转写';
  static const String appVersion = 'v1.0.0';

  // 统一后端 API 地址 (优先读取 .env 配置文件，其次读取编译期参数，最后使用兜底配置)
  static String get defaultBaseUrl {
    if (dotenv.isInitialized) {
      final envVal = dotenv.env['SERVER_BASE_URL']?.trim();
      if (envVal != null && envVal.isNotEmpty) {
        return envVal;
      }
    }
    const compileEnv = String.fromEnvironment('SERVER_BASE_URL');
    if (compileEnv.isNotEmpty) {
      return compileEnv;
    }
    return 'http://127.0.0.1:8080';
  }

  static String baseUrl = defaultBaseUrl;

  static const String apiTranscribe = '/api/transcribe';
  static const String apiTasks = '/api/tasks';
  static const String apiHealth = '/api/health';

  static const int pollIntervalSeconds = 2;
  static const int pollTimeoutSeconds = 600; // 10 minutes timeout
}
