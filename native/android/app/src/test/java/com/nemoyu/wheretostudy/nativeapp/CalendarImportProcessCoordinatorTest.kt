package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CalendarImportProcessCoordinatorTest {
    @Test
    fun aRecreatedOwnerCanAttachToAnActiveImport() {
        val coordinator = CalendarImportProcessCoordinator<String>()
        var oldResult: String? = null
        var newResult: String? = null
        val registration = coordinator.start(1) { _, result -> oldResult = result.getOrNull() }!!

        coordinator.detach(1)
        val attachment = coordinator.attach(registration.token, 2) { _, result ->
            newResult = result.getOrNull()
        }
        assertTrue(attachment is CalendarImportAttachment.Active)

        coordinator.complete(registration.token, Result.success("finished")).forEach { observer ->
            observer(registration.token, Result.success("finished"))
        }

        assertNull(oldResult)
        assertEquals("finished", newResult)
        assertFalse(coordinator.isRunning())
    }

    @Test
    fun aCompletionDuringRecreationRemainsAvailableUntilTheNextImport() {
        val coordinator = CalendarImportProcessCoordinator<String>()
        val registration = coordinator.start(1) { _, _ -> }!!
        coordinator.detach(1)
        coordinator.complete(registration.token, Result.success("finished"))

        val attachment = coordinator.attach(registration.token, 2) { _, _ -> }
        assertEquals("finished", (attachment as CalendarImportAttachment.Completed).result.getOrNull())

        val next = coordinator.start(3) { _, _ -> }!!
        assertTrue(
            coordinator.attach(registration.token, 4) { _, _ -> } is CalendarImportAttachment.Missing,
        )
        assertTrue(next.token > registration.token)
    }
}
