package com.moyichat.moyichat

import android.app.ActivityManager
import android.net.Uri
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

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
                    val text = if (textTask.isSuccessful) textTask.result.text else null
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

    override fun onDestroy() {
        imageLoader.shutdown()
        super.onDestroy()
    }
}
