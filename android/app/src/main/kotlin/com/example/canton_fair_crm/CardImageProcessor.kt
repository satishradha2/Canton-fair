package com.example.canton_fair_crm

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.util.Base64
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.*

/** All outputs are separate app-private files. Originals are never rewritten. */
class CardImageProcessor(private val activity: Activity) {
    companion object {
        private val worker = Executors.newSingleThreadExecutor()
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "canton_fair_crm/card_image")
            .setMethodCallHandler { call, result ->
                if (call.method !in listOf("prepare", "crop", "upload")) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val corners = call.argument<List<List<Double>>>("corners")
                worker.execute {
                    try {
                        require(path != null)
                        val file = File(path).canonicalFile
                        val root = File(activity.applicationInfo.dataDir).canonicalPath + File.separator
                        require(file.path.startsWith(root) && file.isFile)
                        val response: Any = when (call.method) {
                            "upload" -> upload(file)
                            "prepare" -> prepare(file)
                            else -> crop(file, corners ?: error("Missing corners"))
                        }
                        activity.runOnUiThread { result.success(response) }
                    } catch (_: Exception) {
                        activity.runOnUiThread {
                            result.error("card_image_failed", "Could not process the card image. Original preserved.", null)
                        }
                    } catch (_: UnsatisfiedLinkError) {
                        activity.runOnUiThread {
                            result.error("card_image_unavailable", "Image processing is unavailable on this device.", null)
                        }
                    }
                }
            }
    }

    private fun bitmap(file: File, limit: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > limit * 2) sample *= 2
        val decoded = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }) ?: error("Cannot decode image")
        val exif = ExifInterface(file)
        val matrix = Matrix().apply {
            if (exif.isFlipped) postScale(-1f, 1f)
            postRotate(exif.rotationDegrees.toFloat())
        }
        val oriented = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        if (oriented !== decoded) decoded.recycle()
        val factor = min(1.0, limit.toDouble() / max(oriented.width, oriented.height))
        if (factor == 1.0) return oriented
        val scaled = Bitmap.createScaledBitmap(oriented,
            max(1, (oriented.width * factor).toInt()), max(1, (oriented.height * factor).toInt()), true)
        oriented.recycle()
        return scaled
    }

    private fun save(image: Bitmap, parent: File, prefix: String): File {
        val file = File.createTempFile(prefix, ".jpg", parent)
        file.outputStream().use { check(image.compress(Bitmap.CompressFormat.JPEG, 95, it)) }
        return file
    }

    private fun upload(file: File): String {
        val image = bitmap(file, 1800)
        try {
            val bytes = ByteArrayOutputStream().use { output ->
                check(image.compress(Bitmap.CompressFormat.JPEG, 90, output))
                output.toByteArray()
            }
            require(bytes.size <= 3 * 1024 * 1024)
            return "data:image/jpeg;base64," + Base64.encodeToString(bytes, Base64.NO_WRAP)
        } finally { image.recycle() }
    }

    private fun prepare(file: File): Map<String, Any> {
        check(OpenCVLoader.initLocal())
        val image = bitmap(file, 2400)
        val rgba = Mat()
        val gray = Mat()
        val edges = Mat()
        val hierarchy = Mat()
        val contours = ArrayList<MatOfPoint>()
        try {
            Utils.bitmapToMat(image, rgba)
            Imgproc.cvtColor(rgba, gray, Imgproc.COLOR_RGBA2GRAY)
            Imgproc.GaussianBlur(gray, gray, Size(5.0, 5.0), 0.0)
            Imgproc.Canny(gray, edges, 50.0, 150.0)
            Imgproc.findContours(edges, contours, hierarchy, Imgproc.RETR_LIST, Imgproc.CHAIN_APPROX_SIMPLE)
            var best: Array<Point>? = null
            var bestArea = image.width.toDouble() * image.height * 0.12
            for (contour in contours) {
                val curve = MatOfPoint2f(*contour.toArray())
                val approx = MatOfPoint2f()
                try {
                    Imgproc.approxPolyDP(curve, approx, 0.02 * Imgproc.arcLength(curve, true), true)
                    if (approx.total() == 4L) {
                        val polygon = MatOfPoint(*approx.toArray())
                        try {
                            val area = Imgproc.contourArea(polygon)
                            if (area > bestArea && Imgproc.isContourConvex(polygon)) {
                                best = approx.toArray()
                                bestArea = area
                            }
                        } finally { polygon.release() }
                    }
                } finally { curve.release(); approx.release() }
            }
            val points = best?.let { vertices ->
                arrayOf(vertices.minBy { it.x + it.y }, vertices.maxBy { it.x - it.y },
                    vertices.maxBy { it.x + it.y }, vertices.minBy { it.x - it.y })
            }
            val detected = points != null && points.map { Pair(it.x, it.y) }.toSet().size == 4
            val normalized = if (detected) points!!.map { listOf(it.x / image.width, it.y / image.height) }
                else listOf(listOf(0.0, 0.0), listOf(1.0, 0.0), listOf(1.0, 1.0), listOf(0.0, 1.0))
            val preview = save(image, file.parentFile!!, "card_preview_")
            return mapOf("path" to preview.path, "width" to image.width, "height" to image.height,
                "corners" to normalized, "detected" to detected)
        } finally {
            image.recycle(); rgba.release(); gray.release(); edges.release(); hierarchy.release()
            contours.forEach { it.release() }
        }
    }

    private fun crop(file: File, corners: List<List<Double>>): String {
        check(OpenCVLoader.initLocal())
        require(corners.size == 4 && corners.all { it.size == 2 && it.all { n -> n.isFinite() && n in 0.0..1.0 } })
        val image = bitmap(file, 2400)
        val source = Mat()
        val output = Mat()
        val points = corners.map { Point(it[0] * (image.width - 1), it[1] * (image.height - 1)) }
        val polygon = MatOfPoint(*points.toTypedArray())
        val from = MatOfPoint2f(*points.toTypedArray())
        val to = MatOfPoint2f()
        var transform: Mat? = null
        try {
            require(Imgproc.isContourConvex(polygon) && Imgproc.contourArea(polygon) > image.width * image.height * 0.01)
            fun distance(a: Point, b: Point) = hypot(a.x - b.x, a.y - b.y)
            val width = max(distance(points[0], points[1]), distance(points[3], points[2])).toInt().coerceIn(32, 2400)
            val height = max(distance(points[0], points[3]), distance(points[1], points[2])).toInt().coerceIn(32, 2400)
            to.fromArray(Point(0.0, 0.0), Point(width - 1.0, 0.0), Point(width - 1.0, height - 1.0), Point(0.0, height - 1.0))
            transform = Imgproc.getPerspectiveTransform(from, to)
            Utils.bitmapToMat(image, source)
            Imgproc.warpPerspective(source, output, transform, Size(width.toDouble(), height.toDouble()))
            val corrected = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            try {
                Utils.matToBitmap(output, corrected)
                return save(corrected, file.parentFile!!, "card_crop_").path
            } finally { corrected.recycle() }
        } finally {
            image.recycle(); source.release(); output.release(); polygon.release(); from.release(); to.release(); transform?.release()
        }
    }
}
