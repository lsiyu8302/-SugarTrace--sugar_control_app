import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/shopping_monitor_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _dailyLimit = 50.0;
  bool _loading = true;
  bool _shoppingMonitorEnabled = false;

  final _monitor = ShoppingMonitorService.instance;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkMonitorPermissions();
  }

  Future<void> _checkMonitorPermissions() async {
    final accessibility = await _monitor.isAccessibilityEnabled();
    final overlay = await _monitor.hasOverlayPermission();
    if (mounted) {
      setState(() => _shoppingMonitorEnabled = accessibility && overlay);
    }
  }

  Future<void> _onMonitorToggle(bool value) async {
    if (!value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('关闭购物提醒'),
          content: const Text('确定关闭购物提醒？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确定')),
          ],
        ),
      );
      if (confirm != true) return;
      if (mounted) setState(() => _shoppingMonitorEnabled = false);
      return;
    }

    final accessibility = await _monitor.isAccessibilityEnabled();
    if (!accessibility) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('需要无障碍服务权限'),
          content: const Text('请在系统无障碍设置中找到"糖迹"并启用，以便检测购物页面内容。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _monitor.openAccessibilitySettings();
              },
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      await _checkMonitorPermissions();
      return;
    }

    final overlay = await _monitor.hasOverlayPermission();
    if (!overlay) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('需要悬浮窗权限'),
          content: const Text('请授予"糖迹"悬浮窗权限，用于显示糖分超标提醒。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _monitor.openOverlaySettings();
              },
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      await _checkMonitorPermissions();
      return;
    }

    if (mounted) setState(() => _shoppingMonitorEnabled = true);
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await ApiService.getSettings();
      if (mounted) {
        setState(() {
          _dailyLimit =
              double.tryParse(settings['daily_sugar_limit']?.toString() ?? '') ??
                  50.0;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onLimitChanged(double value) async {
    try {
      await ApiService.updateSettings(
          'daily_sugar_limit', value.toStringAsFixed(0));
    } catch (_) {}
  }

  Future<void> _clearTodayRecords() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要删除今天所有的摄入记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定删除',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await ApiService.clearTodayRecords();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('今日记录已全部清除')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清除失败：$e')));
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Section label above a card group
  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.textSecondary,
          ),
        ),
      );

  /// Consistent card shell
  Widget _card({required Widget child, EdgeInsets? padding}) => Card(
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.10)),
        ),
        child: padding != null ? Padding(padding: padding, child: child) : child,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                // ── 每日目标 ──────────────────────────────────────────
                _sectionLabel('每日目标'),
                _card(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.track_changes_rounded,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          const Text(
                            '每日糖分上限',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${_dailyLimit.toInt()}',
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'g / 天',
                            style: TextStyle(
                              fontSize: 15,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 18),
                        ),
                        child: Slider(
                          value: _dailyLimit,
                          min: 25,
                          max: 100,
                          divisions: 15,
                          label: '${_dailyLimit.toInt()}g',
                          activeColor: AppColors.primary,
                          inactiveColor:
                              AppColors.primary.withValues(alpha: 0.18),
                          onChanged: (v) =>
                              setState(() => _dailyLimit = v),
                          onChangeEnd: _onLimitChanged,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('25g',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                            Text('WHO建议 ≤ 50g/天',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w500)),
                            Text('100g',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── 智能提醒 ──────────────────────────────────────────
                _sectionLabel('智能提醒'),
                _card(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.shopping_cart_outlined,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '购物浏览提醒',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 1),
                                Text(
                                  '超标时自动检测购物页高糖食品',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _shoppingMonitorEnabled,
                            activeThumbColor: AppColors.primary,
                            onChanged: _onMonitorToggle,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 14,
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.7)),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                '需要开启无障碍服务与悬浮窗权限方可使用',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── 数据管理 ──────────────────────────────────────────
                _sectionLabel('数据管理'),
                _card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _clearTodayRecords,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.09),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: Colors.red.shade500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '清除今日记录',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.red.shade600,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                const Text(
                                  '删除今天所有摄入记录',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── 关于 ──────────────────────────────────────────────
                _sectionLabel('关于'),
                _card(
                  padding: const EdgeInsets.symmetric(
                      vertical: 28, horizontal: 20),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '糖迹',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'v1.0',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '拍照识糖 · 自动记录 · 超标提醒',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}