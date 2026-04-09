import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'settings_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.refreshNotifier});

  final ValueNotifier<int>? refreshNotifier;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  double _dailyLimit = 50.0;

  // Daily detail
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _records = [];
  bool _loadingDay = false;

  // Chart
  String _chartMode = 'week'; // 'week' | 'month'
  Map<String, double> _chartData = {};
  bool _loadingChart = false;
  String? _chartError;

  // Calendar markers: date_key → 'normal' | 'over'
  final Map<String, String> _calendarMarkers = {};

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_onRefresh);
    _loadAll();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() => _loadAll();

  void _loadAll() {
    _loadSettings();
    _loadDayData(_selectedDay);
    _loadChartData();
    _loadMonthMarkers(_focusedDay);
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadSettings() async {
    try {
      final settings = await ApiService.getSettings();
      if (mounted) {
        setState(() {
          _dailyLimit =
              double.tryParse(settings['daily_sugar_limit']?.toString() ?? '') ??
                  50.0;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDayData(DateTime day) async {
    setState(() => _loadingDay = true);
    try {
      final summary = await ApiService.getDailySummary(_dateKey(day));
      if (mounted) {
        setState(() {
          _summary = summary;
          _records =
              List<Map<String, dynamic>>.from(summary['records'] as List? ?? []);
        });
      }
    } catch (_) {
      if (mounted) setState(() { _summary = null; _records = []; });
    } finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  Future<void> _loadChartData() async {
    setState(() => _loadingChart = true);
    final int days = _chartMode == 'week' ? 7 : 30;
    // Use selected day as anchor; don't go into the future
    final anchor = _selectedDay.isAfter(DateTime.now()) ? DateTime.now() : _selectedDay;
    final end = anchor;
    final start = end.subtract(Duration(days: days - 1));
    try {
      final rows = await ApiService.getRecordsRange(_dateKey(start), _dateKey(end));
      final Map<String, double> agg = {};
      for (final r in rows) {
        final k = r['date_key'] as String;
        agg[k] = (agg[k] ?? 0) + (r['sugar_g'] as num).toDouble();
      }
      if (mounted) setState(() { _chartData = agg; _chartError = null; });
    } catch (e) {
      if (mounted) setState(() { _chartData = {}; _chartError = e.toString(); });
    } finally {
      if (mounted) setState(() => _loadingChart = false);
    }
  }

  Future<void> _loadMonthMarkers(DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    try {
      final rows =
          await ApiService.getRecordsRange(_dateKey(start), _dateKey(end));
      final Map<String, double> agg = {};
      for (final r in rows) {
        final k = r['date_key'] as String;
        agg[k] = (agg[k] ?? 0) + (r['sugar_g'] as num).toDouble();
      }
      if (mounted) {
        setState(() {
          for (final entry in agg.entries) {
            _calendarMarkers[entry.key] =
                entry.value > _dailyLimit ? 'over' : 'normal';
          }
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('摄入统计'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _loadAll(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCalendar(),
              const SizedBox(height: 8),
              _buildDailyDetail(),
              const SizedBox(height: 8),
              _buildChart(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── 区域1：日历 ───────────────────────────────────────────────────────

  Widget _buildCalendar() {
    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.10)),
      ),
      child: TableCalendar(
        firstDay: DateTime.utc(2024, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selected, focused) {
          setState(() {
            _selectedDay = selected;
            _focusedDay = focused;
          });
          _loadDayData(selected);
          _loadChartData();
        },
        onPageChanged: (focused) {
          setState(() => _focusedDay = focused);
          _loadMonthMarkers(focused);
        },
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, day, events) {
            final key = _dateKey(day);
            final markerType = _calendarMarkers[key];
            if (markerType == null) return null;
            return Positioned(
              bottom: 4,
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: markerType == 'over'
                      ? Colors.red.shade400
                      : AppColors.primary,
                ),
              ),
            );
          },
        ),
        calendarStyle: CalendarStyle(
          selectedDecoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          todayDecoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          todayTextStyle: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
          weekendTextStyle: const TextStyle(color: Color(0xFFE57373)),
          defaultTextStyle: const TextStyle(fontSize: 13),
          selectedTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          outsideDaysVisible: false,
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.5,
            color: AppColors.textPrimary,
          ),
          leftChevronIcon: Icon(Icons.chevron_left_rounded,
              color: AppColors.primary, size: 26),
          rightChevronIcon: Icon(Icons.chevron_right_rounded,
              color: AppColors.primary, size: 26),
        ),
      ),
    );
  }

  // ── 区域2：当日明细 ────────────────────────────────────────────────────

  Widget _buildDailyDetail() {
    final day = _selectedDay;
    final label = '${day.month}月${day.day}日';
    final totalSugar =
        (_summary?['total_sugar_g'] as num?)?.toDouble() ?? 0.0;
    final isOver = totalSugar > _dailyLimit;
    final overColor = Colors.red.shade600;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section title ──────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  '$label 摄入记录',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingDay)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_records.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 32,
                          color: AppColors.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(height: 6),
                      const Text(
                        '当天暂无记录',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              ..._records.map((r) => _RecordRow(record: r)),
              const Divider(height: 20, thickness: 0.5),
              // ── Total row ──────────────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isOver
                      ? Colors.red.withValues(alpha: 0.07)
                      : AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      isOver
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 16,
                      color: isOver ? overColor : AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '当日合计',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color:
                            isOver ? overColor : AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${totalSugar.toStringAsFixed(1)} g',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isOver ? overColor : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 区域3：糖分趋势柱状图 ──────────────────────────────────────────────

  /// 将 rawMax 向上取整到最近的整十数，且至少比 limit 高一个刻度
  double _niceMax(double dataMax, double limit) {
    final raw = math.max(dataMax * 1.15, limit * 1.3);
    return math.max(((raw / 10).ceil() * 10).toDouble(), limit + 10);
  }

  Widget _buildChart() {
    final int days = _chartMode == 'week' ? 7 : 30;
    final anchor = _selectedDay.isAfter(DateTime.now()) ? DateTime.now() : _selectedDay;

    // ── 构建柱状数据 ───────────────────────────────────────────────────
    double dataMax = 0;
    final List<BarChartGroupData> barGroups = [];
    for (int i = 0; i < days; i++) {
      final d = anchor.subtract(Duration(days: days - 1 - i));
      final v = _chartData[_dateKey(d)] ?? 0.0;
      if (v > dataMax) dataMax = v;
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: v,
            color: const Color(0xFF29B6F6), // 天蓝色
            width: _chartMode == 'week' ? 22.0 : 7.0,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ));
    }

    // ── Y 轴：取整到十，保证刻度为整数 ──────────────────────────────
    final maxY = _niceMax(dataMax, _dailyLimit);
    final interval = math.max(10.0, ((maxY / 4 / 10).ceil() * 10).toDouble());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.show_chart_rounded,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    const Text(
                      '糖分趋势',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 0.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _ChartModeButton(
                      label: '周',
                      selected: _chartMode == 'week',
                      onTap: () {
                        setState(() => _chartMode = 'week');
                        _loadChartData();
                      },
                    ),
                    const SizedBox(width: 6),
                    _ChartModeButton(
                      label: '月',
                      selected: _chartMode == 'month',
                      onTap: () {
                        setState(() => _chartMode = 'month');
                        _loadChartData();
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: _loadingChart
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _chartError != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off, color: AppColors.textSecondary),
                              const SizedBox(height: 6),
                              Text('加载失败，下拉刷新重试',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(_chartError!, style: const TextStyle(fontSize: 10, color: Colors.red)),
                            ],
                          ),
                        )
                      : BarChart(
                          BarChartData(
                            maxY: maxY,
                            minY: 0,
                            barGroups: barGroups,
                            // 红色虚线：每日上限
                            extraLinesData: ExtraLinesData(
                              horizontalLines: [
                                HorizontalLine(
                                  y: _dailyLimit,
                                  color: Colors.red.withValues(alpha: 0.7),
                                  strokeWidth: 1.5,
                                  dashArray: [6, 4],
                                ),
                              ],
                            ),
                            gridData: FlGridData(
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (_) =>
                                  FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  interval: interval,
                                  getTitlesWidget: (v, _) => Text(
                                    '${v.toInt()}g',
                                    style: const TextStyle(
                                        fontSize: 9, color: AppColors.textSecondary),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: _chartMode == 'week' ? 1 : 5,
                                  getTitlesWidget: (v, _) {
                                    final idx = v.toInt();
                                    if (_chartMode == 'month' && idx % 5 != 0) {
                                      return const SizedBox.shrink();
                                    }
                                    final d = anchor.subtract(
                                        Duration(days: days - 1 - idx));
                                    return Text(
                                      '${d.month}/${d.day}',
                                      style: const TextStyle(
                                          fontSize: 9, color: AppColors.textSecondary),
                                    );
                                  },
                                ),
                              ),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipColor: (_) =>
                                    Colors.white.withValues(alpha: 0.9),
                                getTooltipItem: (group, _, rod, _) {
                                  if (rod.toY == 0) return null;
                                  return BarTooltipItem(
                                    '${rod.toY.toStringAsFixed(0)}g',
                                    const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const _LegendDot(
                    color: Color(0xFF29B6F6), label: '实际摄入'),
                const SizedBox(width: 16),
                _LegendDot(
                  color: Colors.red.withValues(alpha: 0.7),
                  label: '每日上限(${_dailyLimit.toInt()}g)',
                  dashed: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 当日记录行 ────────────────────────────────────────────────────────────

class _RecordRow extends StatelessWidget {
  final Map<String, dynamic> record;
  const _RecordRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final timeStr = record['record_time'] as String? ?? '';
    final timePart =
        timeStr.length >= 16 ? timeStr.substring(11, 16) : timeStr;
    final foodName = record['food_name'] as String? ?? '';
    final servingSize = record['serving_size'] as String?;
    final sugarG = (record['sugar_g'] as num?)?.toDouble() ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Time chip
          Container(
            width: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              timePart,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 10),
          // Food name + serving size
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  foodName,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                if (servingSize != null)
                  Text(
                    servingSize,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          // Sugar badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${sugarG.toStringAsFixed(1)}g',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 图表模式切换按钮 ──────────────────────────────────────────────────────

class _ChartModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChartModeButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

// ── 图例 ──────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const _LegendDot(
      {required this.color, required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dashed)
          // Red dashed line: row of short segments
          Row(
            children: List.generate(3, (i) => Container(
              width: 5,
              height: 2,
              color: color,
              margin: EdgeInsets.only(right: i < 2 ? 2 : 0),
            )),
          )
        else
          // Sky-blue mini bar (like a tiny bar chart bar)
          Container(
            width: 10,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
