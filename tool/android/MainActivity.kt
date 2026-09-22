package com.qinghe.qinghe_timetable

import android.app.Activity
import android.content.Intent
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "com.qinghe.timetable/ringtones"
    private val requestAudio = 6205
    private var pendingResult: MethodChannel.Result? = null
    private var player: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "importLocal" -> openAudio(result)
                    "preview" -> preview(call.argument("resourceName"), call.argument("contentUri"), result)
                    "stop" -> { stopPlayer(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openAudio(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("picker_busy", "文件选择器正在使用", null)
            return
        }
        pendingResult = result
        startActivityForResult(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                type = "audio/*"
                addCategory(Intent.CATEGORY_OPENABLE)
            },
            requestAudio,
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestAudio) return
        val result = pendingResult ?: return
        pendingResult = null
        val source = data?.data
        if (resultCode != Activity.RESULT_OK || source == null) {
            result.success(null)
            return
        }
        try {
            val name = displayName(source)
            val id = UUID.randomUUID().toString().replace("-", "")
            val directory = File(filesDir, "ringtones").apply { mkdirs() }
            val temporary = File(directory, ".$id.tmp")
            contentResolver.openInputStream(source).use { input ->
                requireNotNull(input) { "无法读取音频" }
                temporary.outputStream().use { output ->
                    val buffer = ByteArray(8192)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > 20L * 1024L * 1024L) {
                            throw IllegalArgumentException("音频不能超过20MB")
                        }
                        output.write(buffer, 0, count)
                    }
                }
            }
            val target = File(directory, id)
            check(temporary.renameTo(target)) { "保存音频失败" }
            validateAudio(Uri.fromFile(target))
            val uri = Uri.parse("content://com.qinghe.timetable.ringtones/$id")
            result.success(mapOf("id" to "local-$id", "name" to name, "contentUri" to uri.toString()))
        } catch (error: Exception) {
            result.error("audio_import_failed", error.message ?: "添加本地音乐失败", null)
        }
    }

    private fun displayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0) ?: "本地音乐"
        }
        return "本地音乐"
    }

    private fun validateAudio(uri: Uri) {
        MediaPlayer().apply {
            setDataSource(this@MainActivity, uri)
            prepare()
            release()
        }
    }

    private fun preview(resourceName: String?, contentUri: String?, result: MethodChannel.Result) {
        try {
            stopPlayer()
            val uri = when {
                contentUri != null -> Uri.parse(contentUri)
                resourceName != null -> {
                    val id = resources.getIdentifier(resourceName, "raw", packageName)
                    require(id != 0) { "铃声资源不存在" }
                    Uri.parse("android.resource://$packageName/$id")
                }
                else -> android.provider.Settings.System.DEFAULT_NOTIFICATION_URI
            }
            player = MediaPlayer().apply {
                setDataSource(this@MainActivity, uri)
                setOnCompletionListener { stopPlayer() }
                prepare()
                start()
            }
            result.success(null)
        } catch (error: Exception) {
            stopPlayer()
            result.error("preview_failed", error.message ?: "无法试听", null)
        }
    }

    private fun stopPlayer() {
        player?.runCatching { stop() }
        player?.release()
        player = null
    }

    override fun onDestroy() {
        stopPlayer()
        super.onDestroy()
    }
}
