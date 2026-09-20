import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/transcribe_provider.dart';
import 'settings_page.dart';

class ServerMonitorView extends StatelessWidget {
  const ServerMonitorView({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TranscribeProvider>(context);
    final stats = provider.serverStats;

    return RefreshIndicator(
      onRefresh: () async {
        await provider.checkServerHealth();
        await provider.fetchServerStats();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card with Base URL & Quick Configure
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.dns_rounded, color: AppTheme.primaryColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '当前连接服务端',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                        Text(
                          provider.isServerHealthy ? '云端转写主节点 (在线)' : '云端转写主节点 (未连接)',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: AppTheme.primaryColor),
                    tooltip: '设置与偏好',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Component Status Summary Grid
          const Text(
            '核心组件连通状态',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildComponentCard(
                  title: 'Go 后端服务',
                  isHealthy: provider.isServerHealthy,
                  icon: Icons.cloud_done_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildComponentCard(
                  title: 'Whisper 引擎',
                  isHealthy: stats?.whisperHealthy ?? provider.isServerHealthy,
                  icon: Icons.graphic_eq_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildComponentCard(
                  title: 'DeepSeek AI 润色',
                  isHealthy: stats?.llmHealthy ?? true,
                  icon: Icons.auto_awesome,
                  activeLabel: stats?.llmHealthy == true ? '已就绪' : '未开启',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildComponentCard(
                  title: 'FFmpeg 音频处理',
                  isHealthy: stats?.ffmpegAvailable ?? true,
                  icon: Icons.audiotrack_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Server Performance Metrics Grid
          const Text(
            '运行指标大盘 (2核2G 串行队列)',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),

          if (stats != null) ...[
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.5,
              children: [
                _buildMetricCard(
                  label: '队列等待任务',
                  value: '${stats.queueLength}',
                  unit: '条',
                  color: stats.queueLength > 0 ? AppTheme.statusQueued : AppTheme.primaryColor,
                  icon: Icons.hourglass_top_rounded,
                ),
                _buildMetricCard(
                  label: '成功转写总量',
                  value: '${stats.successTasks}',
                  unit: '条',
                  color: AppTheme.statusSuccess,
                  icon: Icons.check_circle_rounded,
                ),
                _buildMetricCard(
                  label: '平均转写耗时',
                  value: (stats.avgDurationMs / 1000).toStringAsFixed(1),
                  unit: '秒',
                  color: AppTheme.deepseekColor,
                  icon: Icons.timer_outlined,
                ),
                _buildMetricCard(
                  label: '转写成功率',
                  value: stats.successRate.toStringAsFixed(1),
                  unit: '%',
                  color: stats.successRate >= 95 ? AppTheme.statusSuccess : AppTheme.statusFailed,
                  icon: Icons.pie_chart_outline_rounded,
                ),
                _buildMetricCard(
                  label: '失败任务数',
                  value: '${stats.failedTasks}',
                  unit: '条',
                  color: stats.failedTasks > 0 ? AppTheme.statusFailed : AppTheme.textMuted,
                  icon: Icons.cancel_outlined,
                ),
                _buildMetricCard(
                  label: '服务在线运行时长',
                  value: stats.formattedUptime,
                  unit: '',
                  color: AppTheme.textSecondary,
                  icon: Icons.update_rounded,
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: const Column(
                children: [
                  Icon(Icons.cloud_off_rounded, size: 36, color: AppTheme.textMuted),
                  SizedBox(height: 8),
                  Text(
                    '无法连接到服务端监控指标\n请检查后端服务是否正在运行',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComponentCard({
    required String title,
    required bool isHealthy,
    required IconData icon,
    String? activeLabel,
  }) {
    final color = isHealthy ? AppTheme.statusSuccess : AppTheme.statusFailed;
    final statusText = activeLabel ?? (isHealthy ? '正常运行' : '未连接');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String unit,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              Icon(icon, size: 16, color: color.withValues(alpha: 0.8)),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: -0.5,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
