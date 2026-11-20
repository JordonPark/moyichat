package com.moyichat.moyichat

import android.app.ActivityManager
import android.graphics.Rect
import android.net.Uri
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.min

class MainActivity : FlutterActivity() {
    private val imageLoader = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moyichat/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "memory") {
                    val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                    val memory = ActivityManager.MemoryInfo()
                    manager.getMemoryInfo(memory)
                    result.success(mapOf(
                        "total" to memory.totalMem,
                        "available" to memory.availMem,
                        "low" to memory.lowMemory
                    ))
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moyichat/photos")
            .setMethodCallHandler { call, result ->
                if (call.method != "analyze") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.arguments as? String
                if (path.isNullOrEmpty()) {
                    result.error("invalid_image", "An image path is required.", null)
                    return@setMethodCallHandler
                }

                imageLoader.execute { analyze(path, result) }
            }
    }

    private fun analyze(path: String, result: MethodChannel.Result) {
        try {
            val image = InputImage.fromFilePath(applicationContext, Uri.fromFile(File(path)))
            val recognizer = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
            val classifier = ImageLabeling.getClient(
                ImageLabelerOptions.Builder().setConfidenceThreshold(0.55f).build()
            )
            val textTask = recognizer.process(image)
            val labelTask = classifier.process(image)
            Tasks.whenAllComplete(textTask, labelTask).addOnCompleteListener {
                try {
                    val text = if (textTask.isSuccessful) readingOrder(textTask.result) else null
                    val labels = if (labelTask.isSuccessful) {
                        labelTask.result.sortedByDescending { it.confidence }.take(5).map { it.text }
                    } else null
                    if (text == null && labels == null) {
                        result.error("analysis_failed", "Image analysis failed.", null)
                    } else {
                        result.success(mapOf("text" to text, "labels" to labels))
                    }
                } finally {
                    recognizer.close()
                    classifier.close()
                }
            }
        } catch (_: Exception) {
            runOnUiThread {
                result.error("unreadable_image", "Could not open or process the image.", null)
            }
        }
    }

    private fun readingOrder(result: Text): String {
        val lines = result.textBlocks.flatMap { it.lines }.map { line ->
            val bounds = line.boundingBox ?: return result.text
            Pair(line.text, bounds)
        }.sortedBy { it.second.exactCenterY() }
        val rows = mutableListOf<MutableList<Pair<String, Rect>>>()
        for (line in lines) {
            val row = rows.lastOrNull()
            val reference = row?.firstOrNull()?.second
            if (row != null && reference != null &&
                abs(reference.exactCenterY() - line.second.exactCenterY()) <=
                    min(reference.height(), line.second.height()) * 0.55
            ) {
                row.add(line)
            } else {
                rows.add(mutableListOf(line))
            }
        }
        return rows.joinToString("\n") { row ->
            row.sortedBy { it.second.left }.joinToString(" ") { it.first }
        }
    }

    override fun onDestroy() {
        imageLoader.shutdown()
        super.onDestroy()
    }
}
