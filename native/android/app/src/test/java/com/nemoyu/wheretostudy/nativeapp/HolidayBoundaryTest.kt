package com.nemoyu.wheretostudy.nativeapp

import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import org.json.JSONArray
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HolidaySourceBoundaryTest {
    @Test
    fun emptyNameAndRangeAreRejectedBeforeUnknownTypeIsSkipped() {
        assertHolidayError("节假日服务返回的名称不能为空。") {
            parse("""[{"name":"  ","range":["2026-01-01"],"type":"future-type"}]""")
        }
        assertHolidayError("节假日服务返回的日期范围不能为空。") {
            parse("""[{"name":"测试","range":[],"type":"future-type"}]""")
        }
    }

    @Test
    fun validUnknownTypeIsIgnored() {
        val snapshot = parse(
            """[{"name":"测试","range":["2026-01-01"],"type":"future-type"}]""",
        )

        assertTrue(snapshot.items.isEmpty())
    }

    @Test
    fun transportMetadataUsesRawHttpsAndBuildVersion() {
        assertEquals(
            "https://raw.githubusercontent.com/bastengao/chinese-holidays-data/master/data",
            HolidayMetadata.source,
        )
        assertEquals("WhereToStudyNative/0.1.1", HolidayUserAgent.value)
    }

    private fun parse(value: String): HolidaysSnapshot = HolidaySourceParser.parse(
        payload = JSONArray(value),
        year = 2026,
        source = HolidayMetadata.source,
        fetchedAt = "2026-01-05T08:00:00+08:00",
    )

    private fun assertHolidayError(message: String, block: () -> Unit) {
        val error = runCatching(block).exceptionOrNull()
        assertTrue(error is HolidayClientException)
        assertEquals(message, error?.message)
    }
}

class HolidayStoreBoundaryTest {
    private val directory: File = Files.createTempDirectory("holiday-store-test").toFile()

    @After
    fun cleanUp() {
        directory.deleteRecursively()
    }

    @Test
    fun storeRoundTripsAValidSnapshot() {
        val store = HolidayStore(directory)
        val expected = validSnapshot()

        store.save(expected)

        assertEquals(expected, store.load(2026))
    }

    @Test
    fun clearRemovesCachedYearsAndIsIdempotent() {
        val store = HolidayStore(directory)
        store.save(validSnapshot())

        store.clear()
        store.clear()

        assertFalse(directory.exists())
        assertEquals(null, store.load(2026))
    }

    @Test
    fun loadRejectsOversizedAndInvalidUtf8Caches() {
        val store = HolidayStore(directory)
        directory.mkdirs()
        val file = File(directory, "holidays_2026.json")
        file.writeBytes(ByteArray(HolidayInputLimits.maxResponseBytes + 1))
        assertHolidayError("本地节假日缓存过大。") { store.load(2026) }

        file.writeBytes(byteArrayOf(0xC3.toByte(), 0x28))
        assertHolidayError("本地节假日缓存编码不正确。") { store.load(2026) }
    }

    @Test
    fun decodeRejectsInvalidSnapshotBoundaries() {
        val valid = validSnapshot()
        val invalidSnapshots = listOf(
            valid.copy(year = HolidayMetadata.minimumYear - 1),
            valid.copy(source = ""),
            valid.copy(source = "s".repeat(HolidayInputLimits.maxSourceLength + 1)),
            valid.copy(fetchedAt = "2026-01-05"),
            valid.copy(items = List(HolidayInputLimits.maxExpandedItems + 1) { valid.items[0] }),
            valid.copy(items = listOf(valid.items[0].copy(date = "2026-1-01"))),
            valid.copy(items = listOf(valid.items[0].copy(date = "2025-01-01"))),
            valid.copy(items = listOf(valid.items[0].copy(name = " "))),
            valid.copy(items = listOf(valid.items[0].copy(
                name = "节".repeat(HolidayInputLimits.maxNameLength + 1),
            ))),
            valid.copy(items = listOf(valid.items[0].copy(type = "workingday"))),
        )

        invalidSnapshots.forEach { snapshot ->
            assertTrue(runCatching { HolidaysJsonCodec.encode(snapshot) }.isFailure)
        }
    }

    @Test
    fun loadRejectsMismatchedYearAndUnexpectedFields() {
        val store = HolidayStore(directory)
        directory.mkdirs()
        val file = File(directory, "holidays_2026.json")
        val otherYear = validSnapshot().copy(
            year = 2025,
            items = listOf(validSnapshot().items[0].copy(date = "2025-01-01")),
        )
        file.writeText(HolidaysJsonCodec.encode(otherYear), StandardCharsets.UTF_8)
        assertHolidayError("本地节假日缓存年份与请求不一致。") { store.load(2026) }

        file.writeText(
            HolidaysJsonCodec.encode(validSnapshot()).replaceFirst("{", "{\"unexpected\":true,"),
            StandardCharsets.UTF_8,
        )
        assertHolidayError("本地节假日缓存字段不正确。") { store.load(2026) }
    }

    @Test
    fun saveValidatesBeforeWriting() {
        val store = HolidayStore(directory)

        assertHolidayError("本地节假日缓存的数据源不正确。") {
            store.save(validSnapshot().copy(source = ""))
        }

        assertFalse(File(directory, "holidays_2026.json").exists())
    }

    private fun validSnapshot(): HolidaysSnapshot = HolidaysSnapshot(
        year = 2026,
        source = HolidayMetadata.source,
        fetchedAt = "2026-01-05T08:00:00+08:00",
        items = listOf(HolidayItem("2026-01-01", "示例假期", "holiday")),
    )

    private fun assertHolidayError(message: String, block: () -> Unit) {
        val error = runCatching(block).exceptionOrNull()
        assertTrue(error is HolidayClientException)
        assertEquals(message, error?.message)
    }
}
