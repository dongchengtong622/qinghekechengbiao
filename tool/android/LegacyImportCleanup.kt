package com.qinghe.qinghe_timetable

import java.io.File

/** Retires only exact app-owned files. Never traverses or deletes unknown content. */
object LegacyImportCleanup {
    private val retiredModels = listOf("PP-OCRv6_det_small.onnx", "PP-OCRv6_rec_small.onnx", "slanet-plus.onnx")
    private fun ownedFile(parent: File, name: String): File? {
        val file = File(parent, name)
        return file.takeIf { it.isFile && it.canonicalFile == File(parent.canonicalFile, name) }
    }
    fun clean(noBackupRoot: File, filesRoot: File): Long {
        var removed = 0L
        try {
            val expected = File(noBackupRoot.canonicalFile, "ocr-v09")
            val directory = File(noBackupRoot, "ocr-v09")
            if (directory.isDirectory && directory.canonicalFile == expected) {
                for (name in retiredModels) {
                    val file = ownedFile(directory, name) ?: continue
                    val bytes = file.length()
                    if (file.delete()) removed += bytes
                }
                if (directory.list()?.isEmpty() == true) directory.delete()
            }
            for (name in listOf("image-layouts-v1.json", "image-layouts-v1.json.tmp")) {
                val file = ownedFile(filesRoot, name) ?: continue
                val bytes = file.length()
                if (file.delete()) removed += bytes
            }
        } catch (_: Exception) { /* Unavailable files are retried next launch. */ }
        return removed
    }
}
