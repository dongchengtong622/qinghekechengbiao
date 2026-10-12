package com.qinghe.qinghe_timetable
import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class LegacyImportCleanupTest {
    @Test fun removesOnlyRetiredFilesAndPreservesExcelDatabaseAndAudio() {
        val root=Files.createTempDirectory("qinghe-retired-").toFile()
        try {
            val noBackup=File(root,"no_backup").apply{mkdir()};val files=File(root,"files").apply{mkdir()}
            val dir=File(noBackup,"ocr-v09").apply{mkdir()}
            for(name in listOf("PP-OCRv6_det_small.onnx","PP-OCRv6_rec_small.onnx","slanet-plus.onnx"))File(dir,name).writeBytes(byteArrayOf(1,2))
            File(dir,"unknown.txt").writeText("keep")
            File(files,"image-layouts-v1.json").writeText("[]")
            val db=File(files,"qinghe_timetable.sqlite").apply{writeText("course database")}
            val template=File(files,"excel-template.xlsx").apply{writeText("template")}
            val audio=File(files,"ringtones").apply{mkdir()};File(audio,"music").writeText("audio")
            assertEquals(8L,LegacyImportCleanup.clean(noBackup,files))
            assertEquals("course database",db.readText());assertEquals("template",template.readText());assertEquals("audio",File(audio,"music").readText())
            assertTrue(File(dir,"unknown.txt").isFile);assertFalse(File(files,"image-layouts-v1.json").exists())
            assertEquals(0L,LegacyImportCleanup.clean(noBackup,files))
        } finally { root.deleteRecursively() }
    }
    @Test fun neverTraversesNamedModelOrTemplateDirectories() {
        val root=Files.createTempDirectory("qinghe-dirs-").toFile()
        try {
            val noBackup=File(root,"no_backup").apply{mkdir()};val files=File(root,"files").apply{mkdir()}
            val dir=File(noBackup,"ocr-v09").apply{mkdir()}
            val named=File(dir,"PP-OCRv6_det_small.onnx").apply{mkdir()};val nested=File(named,"private").apply{writeText("keep")}
            val template=File(files,"image-layouts-v1.json").apply{mkdir()};val content=File(template,"private").apply{writeText("keep")}
            assertEquals(0L,LegacyImportCleanup.clean(noBackup,files));assertEquals("keep",nested.readText());assertEquals("keep",content.readText())
        } finally { root.deleteRecursively() }
    }
}
