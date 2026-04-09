import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';

/// Singleton that listens to the native SugarMonitorService via MethodChannel
/// and orchestrates the backend verification + overlay display.
class ShoppingMonitorService {
  ShoppingMonitorService._();
  static final instance = ShoppingMonitorService._();

  static const _channel = MethodChannel('sugar_monitor');

  void init() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'verify_shopping_intent') return;
    final args = Map<String, dynamic>.from(call.arguments as Map);

    // Guard: never trigger on our own app — chat/stats screens mention food keywords naturally
    final packageName = args['package_name'] as String? ?? '';
    if (packageName == 'com.sugarcontrol.sugar_control_app') {
      debugPrint('[ShoppingMonitor] 糖迹自身 app，跳过检测');
      return;
    }

    // Step 1: check today's intake — only proceed if already over limit
    try {
      final today = DateTime.now();
      final dateStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final summary = await ApiService.getDailySummary(dateStr);
      final double totalSugar = (summary['total_sugar_g'] as num?)?.toDouble() ?? 0.0;
      final double limitG     = (summary['daily_limit_g'] as num?)?.toDouble() ?? 50.0;
      debugPrint('[ShoppingMonitor] 今日糖分: ${totalSugar}g / 上限: ${limitG}g');
      if (totalSugar <= limitG) {
        debugPrint('[ShoppingMonitor] 未超标，跳过');
        return;
      }

      // Step 2: ask backend to confirm with VL model
      final screenshotB64 = args['screenshot_base64'] as String?;
      final screenText    = args['screen_text'] as String?;
      final foodKeywords  = (args['food_keywords'] as List?)
          ?.map((e) => e.toString())
          .toList() ?? [];
      debugPrint('[ShoppingMonitor] 已超标，正在验证购物意图，关键词: $foodKeywords');

      final result = await ApiService.verifyShoppingIntent(
        screenshotBase64: screenshotB64,
        screenText: screenText,
        foodKeywords: foodKeywords,
      );
      debugPrint('[ShoppingMonitor] verifyShoppingIntent 结果: $result');

      if (result['confirmed'] != true) {
        debugPrint('[ShoppingMonitor] 后端未确认购物意图，跳过弹窗');
        return;
      }

      // Step 3: show native overlay warning
      debugPrint('[ShoppingMonitor] 准备显示弹窗');
      await _channel.invokeMethod('showSugarWarning', {
        'food_name':   result['food_name'] ?? '高糖食品',
        'daily_total': totalSugar,
        'limit':       limitG,
        'package_name': packageName,
      });
    } catch (e, st) {
      debugPrint('[ShoppingMonitor] 错误: $e\n$st');
    }
  }

  // ── Permission helpers (called from settings screen) ─────────────

  Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) { return false; }
  }

  Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } catch (_) { return false; }
  }

  Future<void> openAccessibilitySettings() async {
    try { await _channel.invokeMethod('openAccessibilitySettings'); } catch (_) {}
  }

  Future<void> openOverlaySettings() async {
    try { await _channel.invokeMethod('openOverlaySettings'); } catch (_) {}
  }
}
