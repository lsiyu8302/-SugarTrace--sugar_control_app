package com.sugarcontrol.sugar_control_app

import android.animation.ObjectAnimator
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.TranslateAnimation
import android.view.animation.AlphaAnimation
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Make the engine available to SugarMonitorService
        SugarMonitorService.flutterEngine = flutterEngine

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            SugarMonitorService.CHANNEL)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessibilityEnabled" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "hasOverlayPermission" -> {
                    result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                        Settings.canDrawOverlays(this)
                    )
                }
                "openOverlaySettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        startActivity(Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ))
                    }
                    result.success(null)
                }
                "showSugarWarning" -> {
                    val args = call.arguments as? Map<*, *>
                    val foodName    = args?.get("food_name") as? String ?: "高糖食品"
                    val dailyTotal  = (args?.get("daily_total") as? Number)?.toDouble() ?: 0.0
                    val limit       = (args?.get("limit") as? Number)?.toDouble() ?: 50.0
                    val overAmount  = dailyTotal - limit
                    val packageName = args?.get("package_name") as? String ?: ""
                    showOverlayWarning(foodName, dailyTotal, limit, overAmount, packageName)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Accessibility check ───────────────────────────────────────────

    private fun isAccessibilityServiceEnabled(): Boolean {
        val service = "$packageName/${SugarMonitorService::class.java.canonicalName}"
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { it.equals(service, ignoreCase = true) }
    }

    // ── Overlay warning window ────────────────────────────────────────

    private fun showOverlayWarning(
        foodName: String,
        dailyTotal: Double,
        limit: Double,
        overAmount: Double,
        packageName: String
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) return

        val wm = applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val displayMetrics = resources.displayMetrics
        val screenWidth = displayMetrics.widthPixels

        // ── Severity config ───────────────────────────────────────────
        val (bgColorStr, borderColorStr, icon, title, bodyText, isBold) = when {
            overAmount >= 50 -> Sextet(
                "#FFCDD2", "#C62828", "🔴", "严重超标！",
                "检测到您正在浏览 $foodName，今日糖分摄入已达 ${dailyTotal.toInt()}g，严重超标！\n立即停止高糖摄入，注意血糖风险！",
                true
            )
            overAmount >= 30 -> Sextet(
                "#FFE0B2", "#EF6C00", "🟠", "糖分超标警示",
                "检测到您正在浏览 $foodName，今日糖分摄入已达 ${dailyTotal.toInt()}g，严重超过建议阈值 ${limit.toInt()}g。\n继续食用将严重影响控糖目标。",
                false
            )
            else -> Sextet(
                "#FFF9C4", "#F9A825", "⚠️", "控糖提醒",
                "检测到您正在浏览 $foodName，今日糖分摄入已达 ${dailyTotal.toInt()}g，超过建议阈值 ${limit.toInt()}g。\n建议减少高糖食物摄入。",
                false
            )
        }

        val bgColor     = Color.parseColor(bgColorStr)
        val borderColor = Color.parseColor(borderColorStr)
        val cardWidth   = (screenWidth * 0.85).toInt()
        val dp          = displayMetrics.density

        val ctx = applicationContext

        // ── Build card view ───────────────────────────────────────────
        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding((20 * dp).toInt(), (20 * dp).toInt(), (20 * dp).toInt(), (20 * dp).toInt())
            setBackgroundColor(bgColor)
            elevation = 12f * dp
        }

        // Rounded + border via GradientDrawable
        val bg = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = 16 * dp
            setColor(bgColor)
            setStroke((2 * dp).toInt(), borderColor)
        }
        card.background = bg

        // Icon + Title row
        val titleRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        TextView(ctx).apply {
            text = icon
            textSize = 22f
            titleRow.addView(this, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).also { it.marginEnd = (8 * dp).toInt() })
        }
        TextView(ctx).apply {
            text = title
            textSize = 16f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.parseColor("#1A1A1A"))
            titleRow.addView(this)
        }
        card.addView(titleRow, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).also { it.bottomMargin = (8 * dp).toInt() })

        // Body text
        TextView(ctx).apply {
            text = bodyText
            textSize = 14f
            setTextColor(Color.parseColor("#333333"))
            if (isBold) setTypeface(null, Typeface.BOLD)
            lineHeight = (22 * dp).toInt()
            card.addView(this, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).also { it.bottomMargin = (12 * dp).toInt() })
        }

        // Dismiss button
        val dismissBtn = Button(ctx).apply {
            text = "我知道了"
            textSize = 14f
            setTextColor(Color.WHITE)
            val btnBg = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                cornerRadius = 8 * dp
                setColor(borderColor)
            }
            background = btnBg
        }
        card.addView(dismissBtn, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, (44 * dp).toInt()
        ))

        // ── Window layout params ──────────────────────────────────────
        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            cardWidth,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = (48 * dp).toInt()
        }

        wm.addView(card, params)

        // ── Slide-in animation ────────────────────────────────────────
        val slideIn = TranslateAnimation(0f, 0f, -(cardWidth.toFloat()), 0f).apply {
            duration = 300
        }
        card.startAnimation(slideIn)

        // ── Dismiss action ────────────────────────────────────────────
        dismissBtn.setOnClickListener {
            val fadeOut = AlphaAnimation(1f, 0f).apply { duration = 300 }
            card.startAnimation(fadeOut)
            card.postDelayed({ wm.removeView(card) }, 300)
            // Notify service to update throttle
            notifyServiceWarningShown(packageName)
        }
    }

    private fun notifyServiceWarningShown(pkg: String) {
        try {
            SugarMonitorService.runningInstance?.recordWarning(pkg)
        } catch (_: Exception) {}
    }

    // ── Simple data class ─────────────────────────────────────────────
    private data class Sextet(
        val bg: String, val border: String, val icon: String,
        val title: String, val body: String, val bold: Boolean
    )
}
