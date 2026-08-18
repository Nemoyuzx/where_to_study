package com.nemoyu.wheretostudy.nativeapp

import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HolidaySourceBoundaryTest {
    @Test
    fun emptyNameAndInvalidDateAreRejectedBeforeUnknownTypeIsSkipped() {
        assertHolidayError("节假日服务返回的名称不能为空。") {
            parse(source("""[{"date":"2026-01-01","name":"  ","type":"future-type"}]"""))
        }
        assertHolidayError("节假日服务返回的日期格式不正确。") {
            parse(source("""[{"date":"invalid","name":"测试","type":"future-type"}]"""))
        }
    }

    @Test
    fun emptyAndAllUnknownTypeResponsesAreRejected() {
        assertHolidayError("节假日服务未返回可识别的法定节假日记录。") {
            parse(source("[]"))
        }
        assertHolidayError("节假日服务未返回可识别的法定节假日记录。") {
            parse(source("""[{"date":"2026-01-01","name":"测试","type":"future-type"}]"""))
        }
    }

    @Test
    fun unknownTypesAreIgnoredWhenRecognizedRecordsRemain() {
        val snapshot = parse(source("""[
            {"date":"2026-01-01","name":"测试","type":"future-type"},
            {"date":"2026-01-02","name":"元旦","type":"public_holiday"}
        ]"""))

        assertEquals(listOf(HolidayItem("2026-01-02", "元旦", "holiday")), snapshot.items)
    }

    @Test
    fun transportMetadataUsesLicensedHttpsSourceAndBuildVersion() {
        assertEquals(
            "https://unpkg.com/holiday-calendar@1.3.3/data/CN",
            HolidayMetadata.source,
        )
        assertEquals("WhereToStudyNative/0.1.5", HolidayUserAgent.value)
    }

    @Test
    fun mismatchedYearAndMalformedEnvelopeAreRejected() {
        assertHolidayError("节假日数据年份与请求不一致。") {
            parse("""{"year":2025,"region":"CN","dates":[]}""")
        }
        assertHolidayError("节假日服务返回的日期列表格式不正确。") {
            parse("""{"year":2026,"region":"CN","dates":{}}""")
        }
        assertHolidayError("节假日数据包含其他年份的日期。") {
            parse(source("""[{"date":"2025-12-31","name":"跨年","type":"public_holiday"}]"""))
        }
    }

    private fun parse(value: String): HolidaysSnapshot = HolidaySourceParser.parse(
        payload = JSONObject(value),
        year = 2026,
        source = HolidayMetadata.source,
        fetchedAt = "2026-01-05T08:00:00+08:00",
    )

    private fun source(dates: String): String =
        """{"year":2026,"region":"CN","dates":$dates}"""

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

    @Test
    fun rejectedRemotePayloadCannotReplaceValidCache() {
        val store = HolidayStore(directory)
        val cached = validSnapshot()
        store.save(cached)

        val failure = runCatching {
            HolidaySourceParser.parse(
                payload = JSONObject(
                    """{"year":2026,"region":"CN","dates":[{"date":"2026-01-01","name":"未知","type":"future-type"}]}""",
                ),
                year = 2026,
                source = HolidayMetadata.source,
                fetchedAt = "2026-08-09T08:00:00+08:00",
            ).also(store::save)
        }.exceptionOrNull()

        assertTrue(failure is HolidayClientException)
        assertEquals(cached, store.load(2026))
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

class HolidayOfflineFallbackTest {
    @Test
    fun fallback2026MatchesCacheContractAndRustDataset() {
        val snapshot = requireNotNull(
            HolidayOfflineFallback.snapshot(2026, "2026-08-09T08:00:00+08:00"),
        )

        assertEquals(2026, snapshot.year)
        assertEquals(HolidayMetadata.fallbackSource, snapshot.source)
        assertEquals(EXPECTED_2026_ITEMS, snapshot.items)
        assertEquals(snapshot, HolidaysJsonCodec.decode(HolidaysJsonCodec.encode(snapshot)))
    }

    @Test
    fun fallbackIsUnavailableOutside2026() {
        assertEquals(null, HolidayOfflineFallback.snapshot(2025))
        assertEquals(null, HolidayOfflineFallback.snapshot(2027))
    }

    private companion object {
        val EXPECTED_2026_ITEMS = """
            2026-01-01|元旦|holiday
            2026-01-02|元旦|holiday
            2026-01-03|元旦|holiday
            2026-01-04|元旦补班|workday
            2026-02-14|春节补班|workday
            2026-02-15|春节|holiday
            2026-02-16|春节|holiday
            2026-02-17|春节|holiday
            2026-02-18|春节|holiday
            2026-02-19|春节|holiday
            2026-02-20|春节|holiday
            2026-02-21|春节|holiday
            2026-02-22|春节|holiday
            2026-02-23|春节|holiday
            2026-02-28|春节补班|workday
            2026-04-04|清明节|holiday
            2026-04-05|清明节|holiday
            2026-04-06|清明节|holiday
            2026-05-01|劳动节|holiday
            2026-05-02|劳动节|holiday
            2026-05-03|劳动节|holiday
            2026-05-04|劳动节|holiday
            2026-05-05|劳动节|holiday
            2026-05-09|劳动节补班|workday
            2026-06-19|端午节|holiday
            2026-06-20|端午节|holiday
            2026-06-21|端午节|holiday
            2026-09-25|中秋节|holiday
            2026-09-26|中秋节|holiday
            2026-09-27|中秋节|holiday
            2026-09-20|国庆节补班|workday
            2026-10-01|国庆节|holiday
            2026-10-02|国庆节|holiday
            2026-10-03|国庆节|holiday
            2026-10-04|国庆节|holiday
            2026-10-05|国庆节|holiday
            2026-10-06|国庆节|holiday
            2026-10-07|国庆节|holiday
            2026-10-10|国庆节补班|workday
        """.trimIndent().lineSequence().map { line ->
            val (date, name, type) = line.split('|')
            HolidayItem(date, name, type)
        }.toList()
    }
}
