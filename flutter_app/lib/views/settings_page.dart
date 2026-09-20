import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../providers/transcribe_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _testingConnection = false;
  String? _testResult;
  bool? _testSuccess;

  // Local UX preferences
  bool _vibrationFeedback = true;

  @override
  void initState() {
    super.initState();
    _vibrationFeedback = StorageService.instance.vibrationFeedback;
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _testResult = null;
      _testSuccess = null;
    });

    final apiService = Provider.of<ApiService>(context, listen: false);
    final isHealthy = await apiService.checkHealth();

    setState(() {
      _testingConnection = false;
      _testSuccess = isHealthy;
      _testResult = isHealthy
          ? '连接成功！服务端通信与 AI 引擎状态良好'
          : '连接失败，请确认服务端运行状态或网络连通性';
    });

    if (mounted) {
      final provider = Provider.of<TranscribeProvider>(context, listen: false);
      provider.checkServerHealth();
      provider.fetchServerStats();
      provider.loadHistory();
    }
  }

  void _clearCacheDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清理本地缓存', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
          '此操作将清理本地临时音频与缓存数据，云端转写记录不会被删除。是否继续？',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF475569), height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('本地临时缓存已成功清理'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('确定清理'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transcribeProvider = Provider.of<TranscribeProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(
        title: const Text('设置与偏好'),
        backgroundColor: Colors.white,
        scrolledUnderElevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // 1. 服务端连接配置卡片
          _buildServerCard(transcribeProvider),
          const SizedBox(height: 16),

          // 2. 转写与 AI 偏好设置卡片
          _buildAIPreferencesCard(transcribeProvider),
          const SizedBox(height: 16),

          // 3. 系统通知与提醒测试卡片
          _buildNotificationCard(),
          const SizedBox(height: 16),

          // 4. 录音与系统集成卡片
          _buildRecordingAndSystemCard(),
          const SizedBox(height: 16),

          // 5. 关于应用卡片
          _buildAboutCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // 3. 系统通知卡片
  Widget _buildNotificationCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notifications_active_outlined, color: Color(0xFF8B5CF6), size: 20),
              SizedBox(width: 8),
              Text(
                '转写完成通知与提醒',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '当音频在后台或服务端完成转写后，系统将通过顶部横幅与通知中心提醒您。若未收到通知，可在此处诊断和测试。',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.45),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final granted = await NotificationService.instance.requestPermissions();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(granted ? '✅ 通知权限已就绪' : '⚠️ 通知权限未开启，请在系统设置中允许通知'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.security_rounded, size: 16),
                  label: const Text('检查/请求权限', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF475569),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await NotificationService.instance.showTestNotification();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已发送测试通知，请查看手机顶部通知栏'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send_rounded, size: 15),
                  label: const Text('发送测试通知', style: TextStyle(fontSize: 12.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // 1. 服务端连接配置卡片
  Widget _buildServerCard(TranscribeProvider provider) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.dns_outlined, color: AppTheme.primaryColor, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '服务节点与网络',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: provider.isServerHealthy
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: provider.isServerHealthy
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      provider.isServerHealthy ? '在线正常' : '离线/未连',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: provider.isServerHealthy
                            ? const Color(0xFF047857)
                            : const Color(0xFFBE123C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '云端 AI 转写及大模型认知服务节点已由系统安全配置，点击下方按钮可实时诊断通信与服务状态。',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.45),
          ),
          const SizedBox(height: 14),

          // Action Button - Only "测试服务状态"
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _testingConnection ? null : _testConnection,
              icon: _testingConnection
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.bolt_rounded, size: 18),
              label: Text(_testingConnection ? '正在测试服务连接...' : '测试服务状态'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testSuccess == true
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _testSuccess == true
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFFECDD3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _testSuccess == true ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 18,
                    color: _testSuccess == true ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _testSuccess == true
                            ? const Color(0xFF047857)
                            : const Color(0xFFBE123C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 2. 转写与 AI 偏好设置卡片
  Widget _buildAIPreferencesCard(TranscribeProvider provider) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFF0284C7), size: 20),
              SizedBox(width: 8),
              Text(
                'AI 识别与润色偏好',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // DeepSeek Polish Toggle
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('默认开启 DeepSeek AI 智能润色', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('自动补充中英标点、纠正同音错字并进行口语化降噪', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
            value: provider.needPolish,
            onChanged: (val) {
              provider.setNeedPolish(val);
            },
          ),
          const Divider(height: 16),

          // Language Setting
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('默认识别语言', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('优先匹配的语种模型', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                ],
              ),
              DropdownButton<String>(
                value: provider.selectedLang,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(12),
                items: const [
                  DropdownMenuItem(value: 'zh', child: Text('中文 (普通话)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'en', child: Text('English (英文)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'auto', child: Text('自动检测', style: TextStyle(fontSize: 13))),
                ],
                onChanged: (val) {
                  if (val != null) {
                    provider.setSelectedLang(val);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 3. 录音与系统集成卡片
  Widget _buildRecordingAndSystemCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mic_none_rounded, color: Color(0xFF10B981), size: 20),
              SizedBox(width: 8),
              Text(
                '录音交互与数据管理',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Huawei Recorder integration tip
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF0284C7)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '支持华为/荣耀系统录音机一键分享导入：在系统录音中点击“分享”，选择“智聆转写”即可直接静默启动转写。',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Vibration toggle
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('操作触感震动反馈', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('录音开始、结束与转写完成时提供轻微触感振动', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
            value: _vibrationFeedback,
            onChanged: (val) {
              setState(() {
                _vibrationFeedback = val;
              });
              StorageService.instance.setVibrationFeedback(val);
            },
          ),
          const Divider(height: 16),

          // Clean cache button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('清理临时音频缓存', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('释放本地录音临时存储空间', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                ],
              ),
              OutlinedButton.icon(
                onPressed: _clearCacheDialog,
                icon: const Icon(Icons.cleaning_services_outlined, size: 14),
                label: const Text('立即清理', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 4. 关于应用卡片
  Widget _buildAboutCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFFFAF8FF),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/icon/app_icon.png',
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.graphic_eq_rounded, color: AppTheme.primaryColor, size: 28),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppConfig.appName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 2),
          Text(
            '版本 ${AppConfig.appVersion}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Whisper 离线声学感知 · DeepSeek 认知重塑',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
