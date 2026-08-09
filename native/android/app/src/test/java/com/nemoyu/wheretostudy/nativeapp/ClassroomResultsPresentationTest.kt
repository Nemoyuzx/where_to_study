package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ClassroomResultsPresentationTest {
    @Test
    fun keepsAllLargeResultsWithoutChangingTheirOrder() {
        val rooms = (1..100).map { index -> classroom(index) }

        val presentation = ClassroomResultsPresentation.from(rooms)

        assertEquals(rooms, presentation.rooms)
        assertEquals(null, presentation.message)
    }

    @Test
    fun keepsSmallResultsAndEmptyMessagesUnchanged() {
        val rooms = listOf(classroom(1), classroom(2))
        val populated = ClassroomResultsPresentation.from(rooms)
        val empty = ClassroomResultsPresentation.empty("未选择教学楼")

        assertEquals(rooms, populated.rooms)
        assertEquals("未选择教学楼", empty.message)
        assertTrue(empty.rooms.isEmpty())
    }

    private fun classroom(index: Int) = Classroom(
        id = index.toString(),
        name = "主楼-${index.toString().padStart(3, '0')}",
        building = "主楼",
        room = index.toString().padStart(3, '0'),
        size = 30,
        type = "普通教室",
        availableSlots = listOf(1, 2),
        source = "test",
    )
}
