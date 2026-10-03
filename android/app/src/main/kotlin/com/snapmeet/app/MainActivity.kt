package com.snapmeet.app

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Discrétion : captures et enregistrements d'écran bloqués dans toute
        // l'appli (image noire), et aperçu masqué dans les applis récentes.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Découpe de vidéo pour les stories (comme le statut WhatsApp).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zamu/video")
            .setMethodCallHandler { call, result ->
                if (call.method != "decouper") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val entree = call.argument<String>("chemin")
                val debutMs = call.argument<Int>("debutMs") ?: 0
                val finMs = call.argument<Int>("finMs") ?: 0
                if (entree == null || finMs <= debutMs) {
                    result.error("arguments", "Arguments invalides", null)
                    return@setMethodCallHandler
                }
                val sortie = File(cacheDir, "story_${System.currentTimeMillis()}.mp4").path
                Thread {
                    try {
                        decouper(entree, sortie, debutMs * 1000L, finMs * 1000L)
                        runOnUiThread { result.success(sortie) }
                    } catch (e: Exception) {
                        File(sortie).delete()
                        runOnUiThread { result.error("decoupe", e.message, null) }
                    }
                }.start()
            }
    }

    /**
     * Copie le passage [debutUs, finUs] de la vidéo, sans la réencoder
     * (rapide, aucune perte de qualité). Le début est calé sur l'image clé
     * précédente : la vidéo peut commencer une fraction de seconde plus tôt.
     */
    private fun decouper(entree: String, sortie: String, debutUs: Long, finUs: Long) {
        val extracteur = MediaExtractor()
        extracteur.setDataSource(entree)
        val muxer = MediaMuxer(sortie, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            val pistes = HashMap<Int, Int>()
            var tailleMax = 1024 * 1024
            for (i in 0 until extracteur.trackCount) {
                val format = extracteur.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/") || mime.startsWith("audio/")) {
                    extracteur.selectTrack(i)
                    pistes[i] = muxer.addTrack(format)
                    if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                        tailleMax = maxOf(tailleMax, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                    }
                }
            }
            if (pistes.isEmpty()) throw IllegalStateException("Aucune piste vidéo")

            // Garde l'orientation (vidéo filmée en portrait)
            val infos = MediaMetadataRetriever()
            try {
                infos.setDataSource(entree)
                val rotation = infos.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION
                )?.toIntOrNull() ?: 0
                muxer.setOrientationHint(rotation)
            } finally {
                infos.release()
            }

            muxer.start()
            extracteur.seekTo(debutUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val tampon = ByteBuffer.allocate(tailleMax)
            val info = MediaCodec.BufferInfo()
            var origine = -1L
            while (true) {
                info.offset = 0
                info.size = extracteur.readSampleData(tampon, 0)
                if (info.size < 0) break
                val temps = extracteur.sampleTime
                if (temps > finUs) break
                if (origine < 0) origine = temps
                info.presentationTimeUs = temps - origine
                info.flags =
                    if (extracteur.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                        MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                pistes[extracteur.sampleTrackIndex]?.let {
                    muxer.writeSampleData(it, tampon, info)
                }
                extracteur.advance()
            }
            muxer.stop()
        } finally {
            muxer.release()
            extracteur.release()
        }
    }
}
