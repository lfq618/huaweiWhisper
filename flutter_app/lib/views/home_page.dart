import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/record_provider.dart';
import '../providers/transcribe_provider.dart';
import '../widgets/task_card.dart';
import '../widgets/waveform_visualizer.dart';
import 'server_monitor_view.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickAudioFile(BuildContext context) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'ogg', 'flac', 'amr'],
    );

    if (files.isNotEmpty && files.first.path != null) {
      final filePath = files.first.path!;
      if (context.mounted) {
        final transcribeProvider = Provider.of<TranscribeProvider>(context, listen: false);
        final task = await transcribeProvider.uploadAudioFile(filePath);
        if (task != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已创建转写任务: ${task.fileName ?? task.taskId}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleRecordToggle(BuildContext context) async {
    final recordProvider = Provider.of<RecordProvider>(context, listen: false);
    final transcribeProvider = Provider.of<TranscribeProvider>(context, listen: false);

    if (recordProvider.isRecording) {
      final filePath = await recordProvider.stopRecording();
      if (filePath != null && context.mounted) {
        final task = await transcribeProvider.uploadAudioFile(filePath);
        if (task != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('录音已完成，任务已提交转写: ${task.taskId}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      final started = await recordProvider.startRecording();
      if (!started && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('录音启动失败，请检查麦克风权限'),
            backgroundColor: AppTheme.statusFailed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final transcribeProvider = Provider.of<TranscribeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('智聆转写'),
        actions: [
          // Live Server status badge
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                await transcribeProvider.checkServerHealth();
                await transcribeProvider.loadHistory();
                if (!transcribeProvider.isServerHealthy && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsPage()),
                  );
                }
              },
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: transcribeProvider.isServerHealthy
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: transcribeProvider.isServerHealthy
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFFECDD3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: transcribeProvider.isServerHealthy
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      transcribeProvider.isServerHealthy ? '服务正常' : '未连接',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: transcribeProvider.isServerHealthy
                            ? const Color(0xFF047857)
                            : const Color(0xFFBE123C),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic_none_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('录音与转写'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.monitor_heart_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('服务大盘'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTranscribeTab(context),
          const ServerMonitorView(),
        ],
      ),
    );
  }

  Widget _buildTranscribeTab(BuildContext context) {
    final transcribeProvider = Provider.of<TranscribeProvider>(context);
    final recordProvider = Provider.of<RecordProvider>(context);

    return RefreshIndicator(
      onRefresh: () async {
        await transcribeProvider.checkServerHealth();
        await transcribeProvider.loadHistory();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Top Hero Audio Control Panel
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Status text
                    Text(
                      recordProvider.isRecording
                          ? (recordProvider.isPaused ? '录音已暂停' : '正在录音中...')
                          : '点击麦克风开始现场录音',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Duration or Hint
                    Text(
                      recordProvider.isRecording
                          ? recordProvider.formattedDuration
                          : '或从华为系统录音机分享音频到本 App',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: recordProvider.isRecording ? 32 : 12.5,
                        fontWeight: recordProvider.isRecording ? FontWeight.w800 : FontWeight.w400,
                        letterSpacing: recordProvider.isRecording ? 1.5 : 0,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Waveform Visualizer
                    WaveformVisualizer(
                      amplitudes: recordProvider.amplitudes,
                      isRecording: recordProvider.isRecording,
                      isPaused: recordProvider.isPaused,
                    ),
                    const SizedBox(height: 16),

                    // Main Controls Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Cancel button (only while recording)
                        if (recordProvider.isRecording) ...[
                          IconButton(
                            onPressed: () => recordProvider.cancelRecording(),
                            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                            tooltip: '放弃录音',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.18),
                              padding: const EdgeInsets.all(12),
                            ),
                          ),
                          const SizedBox(width: 20),
                        ],

                        // Record Button
                        GestureDetector(
                          onTap: () => _handleRecordToggle(context),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: recordProvider.isRecording
                                  ? AppTheme.statusFailed
                                  : Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (recordProvider.isRecording
                                          ? AppTheme.statusFailed
                                          : Colors.white)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 18,
                                  spreadRadius: recordProvider.isRecording ? 4 : 1,
                                ),
                              ],
                            ),
                            child: Icon(
                              recordProvider.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                              size: 38,
                              color: recordProvider.isRecording
                                  ? Colors.white
                                  : AppTheme.primaryColor,
                            ),
                          ),
                        ),

                        // Pause/Resume button (while recording)
                        if (recordProvider.isRecording) ...[
                          const SizedBox(width: 20),
                          IconButton(
                            onPressed: () {
                              if (recordProvider.isPaused) {
                                recordProvider.resumeRecording();
                              } else {
                                recordProvider.pauseRecording();
                              }
                            },
                            icon: Icon(
                              recordProvider.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            tooltip: recordProvider.isPaused ? '继续录音' : '暂停录音',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.18),
                              padding: const EdgeInsets.all(12),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(width: 20),
                          // Import audio file button
                          IconButton(
                            onPressed: () => _pickAudioFile(context),
                            icon: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 26),
                            tooltip: '选择导入外部音频',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.18),
                              padding: const EdgeInsets.all(14),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),

                    // DeepSeek Polish Toggle Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: Color(0xFF38BDF8), size: 18),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DeepSeek AI 智能润色',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '自动加标点、同音纠错、段落排版',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: transcribeProvider.needPolish,
                            activeTrackColor: const Color(0xFF38BDF8),
                            onChanged: (val) {
                              transcribeProvider.setNeedPolish(val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Search & Filter Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Bar
                  TextField(
                    controller: _searchController,
                    onChanged: (val) => transcribeProvider.setSearchQuery(val),
                    decoration: InputDecoration(
                      hintText: '搜索任务文件名或转写文本...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                transcribeProvider.setSearchQuery('');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(context, label: '全部', value: 'all'),
                        const SizedBox(width: 6),
                        _buildFilterChip(context, label: '处理中', value: 'processing'),
                        const SizedBox(width: 6),
                        _buildFilterChip(context, label: '已完成', value: 'success'),
                        const SizedBox(width: 6),
                        _buildFilterChip(context, label: '转写失败', value: 'failed'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Task List Section
          if (transcribeProvider.tasks.isEmpty)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(48),
                alignment: Alignment.center,
                child: const Column(
                  children: [
                    Icon(Icons.graphic_eq_rounded, size: 48, color: Color(0xFFCBD5E1)),
                    SizedBox(height: 12),
                    Text(
                      '暂无转写任务\n点击上方麦克风录音，或从录音机分享音频到本 App',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final task = transcribeProvider.tasks[index];
                  return TaskCard(task: task);
                },
                childCount: transcribeProvider.tasks.length,
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, {required String label, required String value}) {
    final provider = Provider.of<TranscribeProvider>(context);
    final isSelected = provider.filterStatus == value;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => provider.setFilterStatus(value),
      selectedColor: AppTheme.primaryColor.withValues(alpha: 0.12),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
      ),
    );
  }
}
