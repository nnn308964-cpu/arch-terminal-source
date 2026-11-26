package com.example.arch_terminal

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Plain Android view hierarchy so startup evidence stays available without Flutter. */
class CrashReportActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val report = StartupDiagnostics.report(this)
        val padding = (16 * resources.displayMetrics.density).toInt()
        val logView = TextView(this).apply {
            text = report
            setTextIsSelectable(true)
            setPadding(padding, padding, padding, padding)
        }
        val copy = Button(this).apply {
            text = "نسخ السجل / Copy"
            setOnClickListener {
                getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText("Arch Terminal startup diagnostics", report))
            }
        }
        val share = Button(this).apply {
            text = "مشاركة السجل / Share"
            setOnClickListener {
                startActivity(
                    Intent.createChooser(
                        Intent(Intent.ACTION_SEND)
                            .setType("text/plain")
                            .putExtra(Intent.EXTRA_TEXT, report),
                        "Share startup diagnostics",
                    ),
                )
            }
        }
        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(padding, padding, padding, padding)
                addView(TextView(this@CrashReportActivity).apply {
                    text = "تشخيص إقلاع Arch Terminal / Startup diagnostics"
                    textSize = 18f
                    gravity = Gravity.CENTER_HORIZONTAL
                })
                addView(copy)
                addView(share)
                addView(ScrollView(this@CrashReportActivity).apply { addView(logView) }, LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f,
                ))
            },
        )
    }
}
