package com.example.diary

import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        requestHighRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) requestHighRefreshRate()
    }

    override fun onPause() {
        val params = window.attributes
        params.preferredRefreshRate = 0f
        window.attributes = params
        super.onPause()
    }

    @Suppress("DEPRECATION")
    private fun requestHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val screen = window.decorView.display ?: return
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        val currentMode = screen.mode
        val refreshRate = if (powerManager.isPowerSaveMode) 0f else {
            screen.supportedModes
                .filter { it.physicalWidth == currentMode.physicalWidth &&
                    it.physicalHeight == currentMode.physicalHeight }
                .maxOfOrNull { it.refreshRate } ?: screen.refreshRate
        }
        val params = window.attributes
        if (params.preferredRefreshRate != refreshRate) {
            // A window-local preference: the OS retains control over power,
            // thermal limits and the user's display settings. No resolution lock.
            params.preferredRefreshRate = refreshRate
            window.attributes = params
        }
    }
}
