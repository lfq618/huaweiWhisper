import 'dart:io';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../models/api_response.dart';
import '../models/server_stats.dart';
import '../models/transcribe_task.dart';
import 'storage_service.dart';

class ApiService {
  late final Dio _dio;

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
        },
      ),
    );
  }

  void updateBaseUrl(String newBaseUrl) {
    AppConfig.baseUrl = newBaseUrl;
    _dio.options.baseUrl = newBaseUrl;
    StorageService.instance.setBaseUrl(newBaseUrl);
  }

  /// 获取服务端音频流 URL (GET /api/transcribe/:task_id/audio)
  String getAudioUrl(String taskId) {
    final base = AppConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
    return '$base/api/transcribe/$taskId/audio';
  }

  /// 上传音频并创建转写任务 (POST /api/transcribe)
  Future<ApiResponse<TranscribeTask>> uploadAndCreateTask({
    required String filePath,
    String lang = 'zh',
    bool needPolish = false,
    String? clientTraceId,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('音频文件不存在: $filePath');
      }

      final fileName = filePath.split(Platform.pathSeparator).last;
      final map = <String, dynamic>{
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        'lang': lang,
        'need_polish': needPolish ? 'true' : 'false',
      };
      if (clientTraceId != null && clientTraceId.isNotEmpty) {
        map['client_trace_id'] = clientTraceId;
      }

      final formData = FormData.fromMap(map);

      final response = await _dio.post(
        AppConfig.apiTranscribe,
        data: formData,
      );

      final apiResp = ApiResponse<TranscribeTask>.fromJson(
        response.data,
        (data) => TranscribeTask.fromJson(
          data as Map<String, dynamic>,
          localFilePath: filePath,
          fileName: fileName,
        ),
      );

      return apiResp;
    } on DioException catch (e) {
      if (e.response?.data != null && e.response?.data is Map<String, dynamic>) {
        return ApiResponse.fromJson(e.response!.data, null);
      }
      return ApiResponse(
        code: -1,
        message: '网络请求失败: ${e.message}',
      );
    } catch (e) {
      return ApiResponse(
        code: -1,
        message: '发生未知错误: $e',
      );
    }
  }

  /// 轮询/查询转写任务状态 (GET /api/transcribe/:task_id)
  Future<ApiResponse<TranscribeTask>> queryTaskStatus(String taskId) async {
    try {
      final response = await _dio.get('${AppConfig.apiTranscribe}/$taskId');
      return ApiResponse<TranscribeTask>.fromJson(
        response.data,
        (data) => TranscribeTask.fromJson(data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      if (e.response?.data != null && e.response?.data is Map<String, dynamic>) {
        return ApiResponse.fromJson(e.response!.data, null);
      }
      return ApiResponse(code: -1, message: '查询状态失败: ${e.message}');
    } catch (e) {
      return ApiResponse(code: -1, message: '查询状态异常: $e');
    }
  }

  /// 手动重试失败任务 (POST /api/transcribe/:task_id/retry)
  Future<ApiResponse<TranscribeTask>> retryTask(String taskId) async {
    try {
      final response = await _dio.post('${AppConfig.apiTranscribe}/$taskId/retry');
      return ApiResponse<TranscribeTask>.fromJson(
        response.data,
        (data) => TranscribeTask.fromJson(data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      if (e.response?.data != null && e.response?.data is Map<String, dynamic>) {
        return ApiResponse.fromJson(e.response!.data, null);
      }
      return ApiResponse(code: -1, message: '重试任务失败: ${e.message}');
    } catch (e) {
      return ApiResponse(code: -1, message: '重试任务异常: $e');
    }
  }

  /// 删除任务及音频 (DELETE /api/transcribe/:task_id)
  Future<bool> deleteTask(String taskId) async {
    try {
      final response = await _dio.delete('${AppConfig.apiTranscribe}/$taskId');
      return response.statusCode == 200 && response.data['code'] == 0;
    } catch (_) {
      return false;
    }
  }

  /// 获取历史任务列表 (GET /api/tasks)
  Future<List<TranscribeTask>> listHistoryTasks({int limit = 50, int offset = 0, String? status}) async {
    try {
      final query = <String, dynamic>{'limit': limit, 'offset': offset};
      if (status != null && status.isNotEmpty) {
        query['status'] = status;
      }
      final response = await _dio.get(
        AppConfig.apiTasks,
        queryParameters: query,
      );
      if (response.data != null && response.data['data'] != null) {
        final list = response.data['data']['list'] as List<dynamic>?;
        if (list != null) {
          return list.map((item) => TranscribeTask.fromJson(item as Map<String, dynamic>)).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 获取服务端统计指标 (GET /api/stats)
  Future<ServerStats?> fetchStats() async {
    try {
      final response = await _dio.get(
        '/api/stats',
        options: Options(receiveTimeout: const Duration(seconds: 4)),
      );
      if (response.statusCode == 200 && response.data['code'] == 0 && response.data['data'] != null) {
        return ServerStats.fromJson(response.data['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 服务端与 Whisper 健康检查 (GET /api/health)
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get(
        AppConfig.apiHealth,
        options: Options(receiveTimeout: const Duration(seconds: 4)),
      );
      return response.statusCode == 200 && response.data['code'] == 0;
    } catch (_) {
      return false;
    }
  }
}
