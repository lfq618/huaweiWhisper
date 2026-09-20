import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  static StorageService get instance => _instance;

  StorageService._internal();

  File? _configFile;
  Map<String, dynamic> _data = {};

  static const String _keyBaseUrl = 'server_base_url';
  static const String _keyNeedPolish = 'need_polish';
  static const String _keySelectedLang = 'selected_lang';
  static const String _keyVibrationFeedback = 'vibration_feedback';

  /// 应用程序启动时调用，加载所有本地持久化配置
  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _configFile = File('${dir.path}${Platform.pathSeparator}app_settings.json');

      if (await _configFile!.exists()) {
        final content = await _configFile!.readAsString();
        if (content.isNotEmpty) {
          _data = jsonDecode(content) as Map<String, dynamic>;
        }
      }

      // BaseUrl 统一使用线上地址
      AppConfig.baseUrl = AppConfig.defaultBaseUrl;

      if (kDebugMode) {
        print('[StorageService] 加载本地配置成功: BaseUrl=${AppConfig.baseUrl}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[StorageService] 初始化配置异常: $e');
      }
    }
  }

  String get baseUrl => _data[_keyBaseUrl] as String? ?? AppConfig.baseUrl;

  Future<void> setBaseUrl(String url) async {
    final cleanUrl = url.trim();
    _data[_keyBaseUrl] = cleanUrl;
    AppConfig.baseUrl = cleanUrl;
    await _save();
  }

  bool get needPolish => _data[_keyNeedPolish] as bool? ?? true;

  Future<void> setNeedPolish(bool val) async {
    _data[_keyNeedPolish] = val;
    await _save();
  }

  String get selectedLang => _data[_keySelectedLang] as String? ?? 'zh';

  Future<void> setSelectedLang(String lang) async {
    _data[_keySelectedLang] = lang;
    await _save();
  }

  bool get vibrationFeedback => _data[_keyVibrationFeedback] as bool? ?? true;

  Future<void> setVibrationFeedback(bool val) async {
    _data[_keyVibrationFeedback] = val;
    await _save();
  }

  Future<void> _save() async {
    try {
      if (_configFile != null) {
        await _configFile!.writeAsString(jsonEncode(_data), flush: true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[StorageService] 写入配置失败: $e');
      }
    }
  }
}
