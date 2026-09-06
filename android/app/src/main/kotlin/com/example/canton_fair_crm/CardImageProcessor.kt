package com.example.canton_fair_crm

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.util.Base64
import android.os.SystemClock
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

    private data class CardCandidate(
        val points: Array<Point>, val score: Double, val method: String
    )

    // Clockwise ordering remains stable for rotated cards, unlike independent
    // min/max corner selection, which can select the same corner twice.
    private fun ordered(vertices: Array<Point>): Array<Point> {
        val cx = vertices.map { it.x }.average()
        val cy = vertices.map { it.y }.average()
        val around = vertices.sortedBy { atan2(it.y - cy, it.x - cx) }
        val first = around.indices.minBy { around[it].x + around[it].y }
        return Array(4) { around[(first + it) % 4] }
    }

    private fun candidate(vertices: Array<Point>, color: Mat, method: String): CardCandidate? {
        val points = ordered(vertices)
        val polygon = MatOfPoint(*points)
        val area: Double
        try {
            if (!Imgproc.isContourConvex(polygon)) return null
            area = Imgproc.contourArea(polygon) / (color.cols().toDouble() * color.rows())
        } finally { polygon.release() }
        if (area !in 0.025..0.92) return null
        if (points.any { it.x < 2 || it.y < 2 || it.x > color.cols() - 3 || it.y > color.rows() - 3 }) return null
        val lengths = DoubleArray(4) { i ->
            hypot(points[i].x - points[(i + 1) % 4].x, points[i].y - points[(i + 1) % 4].y)
        }
        if (lengths.min() < 25) return null
        val w = (lengths[0] + lengths[2]) / 2
        val h = (lengths[1] + lengths[3]) / 2
        if (max(w, h) / min(w, h) > 3.5) return null
        if (lengths[0] / lengths[2] !in 0.4..2.5 || lengths[1] / lengths[3] !in 0.4..2.5) return null
        var angleError = 0.0
        for (i in 0..3) {
            val a = points[(i + 3) % 4]
            val b = points[i]
            val c = points[(i + 1) % 4]
            val cosine = abs(((a.x - b.x) * (c.x - b.x) + (a.y - b.y) * (c.y - b.y)) /
                (lengths[(i + 3) % 4] * lengths[i]))
            if (cosine > 0.72) return null
            angleError += cosine / 4
        }
        // Sample across every proposed edge. Internal text boxes and random
        // texture contours should not win purely because they are rectangular.
        var evidence = 0.0
        val offset = (min(w, h) * 0.035).coerceIn(3.0, 12.0)
        for (i in 0..3) {
            val a = points[i]
            val b = points[(i + 1) % 4]
            val nx = -(b.y - a.y) / lengths[i] * offset
            val ny = (b.x - a.x) / lengths[i] * offset
            var strong = 0
            var contrast = 0.0
            for (sample in 1..16) {
                val t = sample / 17.0
                val x = a.x + (b.x - a.x) * t
                val y = a.y + (b.y - a.y) * t
                val inside = color.get((y + ny).toInt().coerceIn(0, color.rows() - 1),
                    (x + nx).toInt().coerceIn(0, color.cols() - 1))
                val outside = color.get((y - ny).toInt().coerceIn(0, color.rows() - 1),
                    (x - nx).toInt().coerceIn(0, color.cols() - 1))
                val difference = (0..2).maxOf { abs(inside[it] - outside[it]) }
                contrast += difference
                if (difference >= 14) strong++
            }
            if (strong < 7 || contrast / 16 < 12) return null
            evidence += min(1.0, contrast / 16 / 60) / 4
        }
        val score = 0.65 * evidence + 0.30 * (1 - angleError) + 0.05 * min(1.0, area / 0.25)
        return CardCandidate(points.map { Point(it.x / (color.cols() - 1), it.y / (color.rows() - 1)) }.toTypedArray(), score, method)
    }

    private fun detect(image: Mat): List<CardCandidate> {
        val candidates = ArrayList<CardCandidate>()
        val deadline = SystemClock.elapsedRealtime() + 8000
        for (size in listOf(720, 1200)) {
            val small = Mat()
            val channel = Mat()
            val smooth = Mat()
            val binary = Mat()
            val hierarchy = Mat()
            val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(5.0, 5.0))
            try {
                val scale = min(1.0, size.toDouble() / max(image.cols(), image.rows()))
                Imgproc.resize(image, small, Size(), scale, scale, Imgproc.INTER_AREA)
                for (component in -1..2) {
                    if (component == -1) Imgproc.cvtColor(small, channel, Imgproc.COLOR_RGBA2GRAY)
                    else Core.extractChannel(small, channel, component)
                    Imgproc.bilateralFilter(channel, smooth, 9, 60.0, 7.0)
                    for (pass in 0..4) {
                        if (SystemClock.elapsedRealtime() > deadline) return candidates
                        when (pass) {
                            0 -> Imgproc.Canny(smooth, binary, 25.0, 75.0)
                            1 -> Imgproc.Canny(smooth, binary, 60.0, 160.0)
                            2 -> Imgproc.threshold(smooth, binary, 0.0, 255.0, Imgproc.THRESH_BINARY or Imgproc.THRESH_OTSU)
                            3 -> Imgproc.threshold(smooth, binary, 0.0, 255.0, Imgproc.THRESH_BINARY_INV or Imgproc.THRESH_OTSU)
                            else -> Imgproc.adaptiveThreshold(smooth, binary, 255.0,
                                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C, Imgproc.THRESH_BINARY, 51, 5.0)
                        }
                        Imgproc.morphologyEx(binary, binary, Imgproc.MORPH_CLOSE, kernel)
                        val contours = ArrayList<MatOfPoint>()
                        try {
                            Imgproc.findContours(binary, contours, hierarchy, Imgproc.RETR_LIST, Imgproc.CHAIN_APPROX_SIMPLE)
                            // Bound work on woven fabrics and other high-frequency surfaces.
                            val largest = contours.sortedByDescending { Imgproc.contourArea(it) }.take(60)
                            for (contour in largest) {
                                if (SystemClock.elapsedRealtime() > deadline) return candidates
                                if (Imgproc.contourArea(contour) < small.total() * 0.02) continue
                                val curve = MatOfPoint2f(*contour.toArray())
                                val approx = MatOfPoint2f()
                                try {
                                    val perimeter = Imgproc.arcLength(curve, true)
                                    for (epsilon in listOf(0.015, 0.025, 0.04)) {
                                        Imgproc.approxPolyDP(curve, approx, epsilon * perimeter, true)
                                        if (approx.total() != 4L) continue
                                        val found = candidate(approx.toArray(), small, "$size/$component/$pass")
                                        if (found != null) { candidates.add(found); break }
                                    }
                                } finally { curve.release(); approx.release() }
                            }
                        } finally { contours.forEach { it.release() } }
                    }
                }
            } finally {
                small.release(); channel.release(); smooth.release(); binary.release()
                hierarchy.release(); kernel.release()
            }
        }
        return candidates
    }

    private fun prepare(file: File): Map<String, Any> {
        check(OpenCVLoader.initLocal())
        val image = bitmap(file, 2400)
        val rgba = Mat()
        try {
            Utils.bitmapToMat(image, rgba)
            val candidates = detect(rgba)
            fun similar(a: CardCandidate, b: CardCandidate): Boolean = (0..3).any { shift ->
                (0..3).all { i ->
                    val p = a.points[i]; val q = b.points[(i + shift) % 4]
                    hypot(p.x - q.x, p.y - q.y) < 0.035
                }
            }
            val ranked = candidates.map { c ->
                // Color channels, inverted masks and alternate thresholds are
                // correlated evidence, not independent confirmations.
                val evidence = candidates.filter { similar(c, it) }.map {
                    val parts = it.method.split('/')
                    val family = if (parts[2].toInt() <= 1) "edge" else "region"
                    Pair(parts[0], family)
                }.toSet()
                val diverse = evidence.map { it.first }.toSet().size >= 2 &&
                    evidence.map { it.second }.toSet().size >= 2
                val votes = if (diverse) evidence.size else 0
                Triple(c, votes, c.score + min(0.15, (votes - 1) * 0.03))
            }.sortedByDescending { it.third }
            val best = ranked.firstOrNull()
            val rival = if (best == null) null else ranked.firstOrNull { !similar(best.first, it.first) }
            // Heuristic score, not a calibrated accuracy probability. Abstain
            // when detectors disagree or two plausible cards compete.
            val detected = best != null && best.second >= 3 && best.third >= 0.60 &&
                (rival == null || best.third - rival.third >= 0.08)
            val normalized = if (detected) {
                val points = best!!.first.points
                val cx = points.map { it.x }.average()
                val cy = points.map { it.y }.average()
                // Small safety margin protects text printed near card edges.
                points.map { listOf((cx + (it.x - cx) * 1.025).coerceIn(0.0, 1.0),
                    (cy + (it.y - cy) * 1.025).coerceIn(0.0, 1.0)) }
            }
                else listOf(listOf(0.0, 0.0), listOf(1.0, 0.0), listOf(1.0, 1.0), listOf(0.0, 1.0))
            val preview = save(image, file.parentFile!!, "card_preview_")
            return mapOf("path" to preview.path, "width" to image.width, "height" to image.height,
                "corners" to normalized, "detected" to detected,
                "detector" to "multi-pass-v2", "agreement" to (best?.second ?: 0))
        } finally {
            image.recycle(); rgba.release()
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
