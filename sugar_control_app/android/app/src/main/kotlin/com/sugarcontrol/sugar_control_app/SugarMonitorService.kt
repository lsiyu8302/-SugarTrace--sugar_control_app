package com.sugarcontrol.sugar_control_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SugarMonitorService : AccessibilityService() {

    companion object {
        const val CHANNEL = "sugar_monitor"
        private const val TAG = "SugarMonitor"
        private const val EVENT_THROTTLE_MS = 30_000L
        private const val WARNING_COOLDOWN_MS = 5 * 60_000L
        private const val MAX_DAILY_WARNINGS = 10

        var flutterEngine: FlutterEngine? = null
        var runningInstance: SugarMonitorService? = null

        private val HIGH_SUGAR_KEYWORDS = listOf(
            "奶茶","果茶","柠檬茶","奶盖","奶昔","冰沙","气泡水",
            "果汁","杨枝甘露","烧仙草","双皮奶","糖水","酸奶",
            "乳酸菌饮料","芋泥","珍珠","波波","芝士","椰椰",
            "多肉","满杯",
            "蛋糕","面包","可颂","蛋挞","曲奇","饼干","威化",
            "铜锣烧","班戟","瑞士卷","戚风蛋糕","千层蛋糕",
            "布朗尼","芝士蛋糕","提拉米苏","马卡龙","泡芙",
            "甜甜圈","华夫饼","吐司","牛角包",
            "甜品","冰淇淋","雪糕","冰棍","圣代","巧克力",
            "焦糖","蜂蜜","红豆","抹茶",
            "糖葫芦","桂花糕","绿豆糕","红豆沙","汤圆","元宵",
            "糯米糍","八宝饭","甜粽","驴打滚","豆沙",
            "年糕","麻薯","青团",
            "糖果","软糖","QQ糖","棒棒糖","巧克力棒","太妃糖",
            "牛轧糖","奶糖","果冻","布丁",
            "爆米花","蜜饯","果干","山楂片","果脯",
            "可乐","雪碧","芬达","美年达","脉动","冰红茶","冰糖雪梨",
            "全糖","半糖","多糖","少糖","七分糖","三分糖","正常糖","加糖","标准甜"
        )

        private val WHITELIST_KEYWORDS = listOf(
            "无糖","0糖","零糖","低糖","代糖","木糖醇","赤藓糖醇",
            "阿斯巴甜","不额外加糖","不另加糖","控糖","减糖",
            "糖尿病友好","生酮","低GI","低碳水"
        )

        private val BUY_KEYWORDS = listOf(
            "¥","￥","价格","原价","售价","到手价","折","优惠",
            "券","满减","秒杀","特价","限时","促销",
            "加入购物车","立即购买","立即下单","去结算","去支付",
            "选规格","选择规格","立即抢购",
            "已售","月销","销量","好评","评价","库存",
            "规格","口味","份","杯","盒",
            "配送","外卖","起送","配送费","预计送达","骑手",
            "自提","堂食"
        )
    }

    private var lastEventTimestamp = 0L
    private val lastWarningMap = HashMap<String, Long>()
    private var dailyWarningCount = 0
    private var dailyWarningDate = ""
    private var lastScreenTextHash = 0

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        runningInstance = this
        Log.d(TAG, "✅ 无障碍服务已启动")
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 500
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        serviceInfo = info
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val pkg = event.packageName?.toString() ?: return

        // ── Skip when user is inside 糖迹 itself ──────────────────────
        if (pkg == packageName) return

        // ── (a) Event throttle ────────────────────────────────────────
        val now = System.currentTimeMillis()
        if (now - lastEventTimestamp < EVENT_THROTTLE_MS) return

        // ── (b) Per-app warning cooldown ──────────────────────────────
        val lastWarn = lastWarningMap[pkg] ?: 0L
        if (now - lastWarn < WARNING_COOLDOWN_MS) return

        // ── (c) Daily cap ─────────────────────────────────────────────
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        if (today != dailyWarningDate) {
            dailyWarningDate = today
            dailyWarningCount = 0
        }
        if (dailyWarningCount >= MAX_DAILY_WARNINGS) return

        // ── (d) Page dedup ────────────────────────────────────────────
        val root = rootInActiveWindow ?: return
        val screenText = extractText(root)
        if (screenText.isBlank() || screenText.length < 20) return
        val hash = screenText.hashCode()
        if (hash == lastScreenTextHash) return

        lastEventTimestamp = now
        lastScreenTextHash = hash

        Log.d(TAG, "📱 检测到页面变化 pkg=$pkg, 文字长度=${screenText.length}")

        // ── (f) Whitelist passthrough ─────────────────────────────────
        if (WHITELIST_KEYWORDS.any { screenText.contains(it) }) {
            Log.d(TAG, "⬜ 白名单命中，跳过")
            return
        }

        // ── (g) High-sugar keyword filter ────────────────────────────
        val matchedFood = HIGH_SUGAR_KEYWORDS.filter { screenText.contains(it) }
        if (matchedFood.isEmpty()) {
            Log.d(TAG, "🔍 无高糖关键词命中")
            return
        }

        // ── (h) Purchase intent filter (≥2 keywords) ─────────────────
        val matchedBuy = BUY_KEYWORDS.filter { screenText.contains(it) }
        Log.d(TAG, "🍬 高糖关键词=$matchedFood, 购买关键词=$matchedBuy")
        if (matchedBuy.size < 2) {
            Log.d(TAG, "🛒 购买关键词不足2个，跳过")
            return
        }

        // ── (i) Screenshot ────────────────────────────────────────────
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(result: ScreenshotResult) {
                        val bitmap = Bitmap.wrapHardwareBuffer(
                            result.hardwareBuffer, result.colorSpace
                        )
                        result.hardwareBuffer.close()
                        val b64 = bitmap?.let { bmpToBase64(it) }
                        sendToFlutter(pkg, b64, screenText, matchedFood, matchedBuy)
                    }
                    override fun onFailure(errorCode: Int) {
                        sendToFlutter(pkg, null, screenText, matchedFood, matchedBuy)
                    }
                }
            )
        } else {
            Log.d(TAG, "📤 发送到Flutter (无截图)")
            sendToFlutter(pkg, null, screenText, matchedFood, matchedBuy)
        }
    }

    private fun bmpToBase64(bitmap: Bitmap): String {
        val sw = bitmap.width
        val sh = bitmap.height
        val maxSide = 1080
        val scaled = if (sw > maxSide || sh > maxSide) {
            val ratio = maxSide.toFloat() / maxOf(sw, sh)
            Bitmap.createScaledBitmap(bitmap, (sw * ratio).toInt(), (sh * ratio).toInt(), true)
        } else bitmap
        val baos = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 60, baos)
        return android.util.Base64.encodeToString(baos.toByteArray(), android.util.Base64.NO_WRAP)
    }

    private fun sendToFlutter(
        pkg: String,
        screenshotBase64: String?,
        screenText: String,
        foodKeywords: List<String>,
        buyKeywords: List<String>
    ) {
        val engine = flutterEngine
        if (engine == null) {
            Log.w(TAG, "⚠️ flutterEngine 为 null，Flutter 不可达")
            return
        }
        mainHandler.post {
            try {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("verify_shopping_intent", mapOf(
                        "action" to "verify_shopping_intent",
                        "package_name" to pkg,
                        "screenshot_base64" to screenshotBase64,
                        "screen_text" to screenText.take(500),
                        "food_keywords" to foodKeywords,
                        "buy_keywords" to buyKeywords
                    ))
                Log.d(TAG, "✅ 已调用 Flutter verify_shopping_intent")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 调用 Flutter 失败: $e")
            }
        }
    }

    fun recordWarning(pkg: String) {
        lastWarningMap[pkg] = System.currentTimeMillis()
        dailyWarningCount++
    }

    private fun extractText(node: AccessibilityNodeInfo): String {
        val sb = StringBuilder()
        fun traverse(n: AccessibilityNodeInfo?) {
            n ?: return
            n.text?.let { sb.append(it).append(' ') }
            n.contentDescription?.let { sb.append(it).append(' ') }
            for (i in 0 until n.childCount) traverse(n.getChild(i))
        }
        traverse(node)
        return sb.toString()
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        if (runningInstance === this) runningInstance = null
        super.onDestroy()
    }
}
