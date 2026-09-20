import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/transcribe_task.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  static NotificationService get instance => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  void Function(String taskId)? _onNotificationTap;

  static const String _channelId = 'whisper_transcribe_channel';
  static const String _channelName = '智聆转写通知';
  static const String _channelDescription = '转写任务完成及状态提醒通知';

  /// 初始化通知服务
  Future<void> init({void Function(String taskId)? onNotificationTap}) async {
    if (_isInitialized) return;
    _onNotificationTap = onNotificationTap;

    // Android 初始化设置（使用已生成的 app icon）
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS / Darwin 初始化设置
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _onNotificationTap?.call(payload);
        }
      },
    );

    // 在 Android 上创建最高优先级通知渠道 (Importance.max 用于顶部横幅提醒)
    if (Platform.isAndroid) {
      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        const channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );
        await androidImplementation.createNotificationChannel(channel);
      }
    }

    _isInitialized = true;
    if (kDebugMode) {
      print('[NotificationService] 本地通知服务初始化成功');
    }
  }

  /// 请求通知权限 (适配 Android 13+ 及 iOS)
  Future<bool> requestPermissions() async {
    bool isGranted = false;

    // 1. 优先通过 permission_handler 请求
    try {
      final status = await Permission.notification.status;
      if (status.isDenied || status.isLimited) {
        final reqStatus = await Permission.notification.request();
        isGranted = reqStatus.isGranted;
      } else if (status.isGranted) {
        isGranted = true;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[NotificationService] permission_handler 请求权限失败: $e');
      }
    }

    // 2. 补充调用 flutter_local_notifications 原生权限请求
    if (Platform.isAndroid) {
      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final localGranted = await androidImplementation.requestNotificationsPermission();
        if (localGranted != null) {
          isGranted = isGranted || localGranted;
        }
      }
    } else if (Platform.isIOS) {
      final iosImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (iosImplementation != null) {
        final localGranted = await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (localGranted != null) {
          isGranted = isGranted || localGranted;
        }
      }
    }
    return isGranted;
  }

  /// 检查通知权限是否已授予
  Future<bool> isPermissionGranted() async {
    return await Permission.notification.isGranted;
  }

  /// 发送测试通知
  Future<void> showTestNotification() async {
    if (!_isInitialized) {
      await init();
    }
    await requestPermissions();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: '智聆转写测试通知',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      999999,
      '🔔 智聆转写 - 通知测试',
      '恭喜！系统通知与横幅提醒已配置成功，转写完成时将自动在此提示。',
      details,
    );
  }

  /// 下发「转写完成」本地系统通知
  Future<void> showTaskCompletedNotification(TranscribeTask task) async {
    if (!_isInitialized) {
      await init();
    }

    final id = task.taskId.hashCode & 0x7FFFFFFF;
    final fileName = task.fileName ?? task.taskId;
    final elapsedSec = (task.durationMs / 1000).toStringAsFixed(1);
    final textLen = task.effectiveText.length;

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: '语音转写已完成',
      styleInformation: BigTextStyleInformation(
        '【$fileName】已成功转写完成（耗时 $elapsedSec秒，共 $textLen 字）\n内容摘要：${task.effectiveText.length > 60 ? '${task.effectiveText.substring(0, 60)}...' : task.effectiveText}',
        contentTitle: '🎉 语音转写已完成',
        summaryText: '智聆转写',
      ),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      id,
      '🎉 语音转写已完成',
      '【$fileName】已成功转写完成（耗时 $elapsedSec秒，共 $textLen 字）',
      details,
      payload: task.taskId,
    );
  }

  /// 下发「转写失败」本地系统通知
  Future<void> showTaskFailedNotification(TranscribeTask task) async {
    if (!_isInitialized) {
      await init();
    }

    final id = task.taskId.hashCode & 0x7FFFFFFF;
    final fileName = task.fileName ?? task.taskId;
    final errorReason = task.errorMsg ?? '转写遇到异常，点击查看详情';

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: '转写任务失败',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      id,
      '⚠️ 转写任务失败',
      '【$fileName】$errorReason',
      details,
      payload: task.taskId,
    );
  }
}

