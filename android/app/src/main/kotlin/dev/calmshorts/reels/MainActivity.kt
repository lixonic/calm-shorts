package dev.calmshorts.reels

import android.app.ActivityManager
import android.os.Debug
import android.system.Os
import android.system.OsConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Available only to debug/profile device tests, removed from release by R8.
        if (!BuildConfig.DEBUG) return
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.calmshorts/performance")
            .setMethodCallHandler { call, result ->
                if (call.method != "memory") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val status = File("/proc/self/status").readLines().mapNotNull { line ->
                    val fields = line.trim().split(Regex("\\s+"))
                    if (fields.size >= 2) fields[1].toLongOrNull()?.let { fields[0].removeSuffix(":") to it }
                    else null
                }.toMap()
                val memory = Debug.MemoryInfo()
                Debug.getMemoryInfo(memory)
                val device = ActivityManager.MemoryInfo()
                (getSystemService(ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(device)
                result.success(mapOf(
                    "pageSizeBytes" to Os.sysconf(OsConstants._SC_PAGESIZE),
                    "deviceRamBytes" to device.totalMem,
                    "rssAnonKb" to status["RssAnon"],
                    "swapKb" to status["VmSwap"],
                    "rssKb" to status["VmRSS"],
                    "totalPssKb" to memory.totalPss,
                    "nativeHeapBytes" to Debug.getNativeHeapAllocatedSize()
                ))
            }
    }
}
