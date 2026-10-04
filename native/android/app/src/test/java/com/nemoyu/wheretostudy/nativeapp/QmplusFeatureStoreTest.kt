package com.nemoyu.wheretostudy.nativeapp

import java.io.IOException
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class QmplusFeatureStoreTest {
    @Test fun freshStoreInstancesFenceOldOwnersAndPublicationAcrossOffThenOn() = fixture { directory ->
        var bytes: ByteArray? = null
        val first = QmplusFeatureStore(directory, { bytes?.copyOf() }, { bytes = it.copyOf() })
        val second = QmplusFeatureStore(directory, { bytes?.copyOf() }, { bytes = it.copyOf() })
        assertFalse(first.status().enabled)
        val old = first.setEnabled(true)
        assertTrue(second.isCurrent(old))
        var publications = 0
        first.whileCurrent(old) { publications++ }
        val off = second.setEnabled(false)
        assertFalse(off.enabled)
        assertFalse(first.isCurrent(old))
        assertThrows(IllegalStateException::class.java) { first.whileCurrent(old) { publications++ } }
        val newOwner = second.setEnabled(true)
        assertTrue(newOwner.revision > old.revision)
        assertFalse(first.isCurrent(old))
        assertTrue(first.isCurrent(newOwner))
        assertThrows(IllegalStateException::class.java) { first.whileCurrent(old) { publications++ } }
        assertEquals(1, publications)
    }

    @Test fun unreadableMalformedOrUnverifiedWritesNeverGrantFeatureAuthority() = fixture { directory ->
        val missing = QmplusFeatureStore(directory, { null }, { })
        assertFalse(missing.status().enabled)
        assertThrows(IllegalStateException::class.java) { missing.setEnabled(true) }
        val malformed = QmplusFeatureStore(directory, { byteArrayOf(0, 0, 0, 0) }, { })
        assertFalse(malformed.isCurrent(QmplusFeatureRecord(1, true)))
        val unavailable = QmplusFeatureStore(directory, { throw IOException("synthetic read failure") }, { })
        assertFalse(unavailable.isCurrent(QmplusFeatureRecord(1, true)))
        val failingWrite = QmplusFeatureStore(directory, { null }, { throw IOException("synthetic write failure") })
        assertThrows(IOException::class.java) { failingWrite.setEnabled(true) }
        assertFalse(failingWrite.status().enabled)
    }

    @Test fun repeatedEnabledSettingPreservesTheCurrentBindingButEveryRealToggleRetiresIt() = fixture { directory ->
        var bytes: ByteArray? = null
        val store = QmplusFeatureStore(directory, { bytes?.copyOf() }, { bytes = it.copyOf() })
        val enabled = store.setEnabled(true)
        assertEquals(enabled, store.setEnabled(true))
        store.setEnabled(false)
        assertNotEquals(enabled, store.setEnabled(true))
    }

    @Test fun reenableAfterAFailedOffWriteMustRenewTheOldPersistedBinding() = fixture { directory ->
        var bytes: ByteArray? = null
        var failWrite = false
        val store = QmplusFeatureStore(directory, { bytes?.copyOf() }, {
            if (failWrite) throw IOException("synthetic off write failure")
            bytes = it.copyOf()
        })
        val old = store.setEnabled(true)
        failWrite = true
        assertThrows(IOException::class.java) { store.setEnabled(false) }
        // A failed write cannot pretend that the persistent mirror is already Off.
        assertEquals(old, store.status())
        failWrite = false
        val next = store.setEnabled(true, renewOwner = true)
        assertTrue(next.revision > old.revision)
        assertFalse(store.isCurrent(old))
        assertTrue(store.isCurrent(next))
    }

    @Test fun stopOnlyMessagesTargetTheOriginalConnectionWithoutClosingAReplacementOwner() {
        assertTrue(QmplusFeatureOwnerPolicy.acceptsStop("old", 1, "old", 1))
        assertFalse(QmplusFeatureOwnerPolicy.acceptsStop("new", 3, "old", 1))
        assertFalse(QmplusFeatureOwnerPolicy.acceptsStop("new", 1, "old", 1))
        assertFalse(QmplusFeatureOwnerPolicy.acceptsStop("new", 3, null, 1))
        assertTrue(QmplusFeatureOwnerPolicy.acceptsStop("old", 1, null, 1))
    }

    @Test fun migrationHonorsEstablishedMirrorBothWaysBeforeLegacyEvidenceAndExplicitPublicOffAlwaysWins() {
        assertTrue(QmplusFeatureMigrationPolicy.resolve(QmplusFeatureRecord(1, true), false, false) { it })
        assertFalse(QmplusFeatureMigrationPolicy.resolve(QmplusFeatureRecord(2, false), true, true) { it })
        assertTrue(QmplusFeatureMigrationPolicy.resolve(QmplusFeatureRecord(), true, false) { it })
        assertTrue(QmplusFeatureMigrationPolicy.resolve(QmplusFeatureRecord(), false, true) { it })
        assertFalse(QmplusFeatureMigrationPolicy.resolve(QmplusFeatureRecord(), false, false) { it })
        assertFalse(QmplusFeatureMigrationPolicy.resolve(QmplusFeatureRecord(1, true), true, true) { false })
    }

    @Test fun corruptMirrorCannotReachPreferenceMigrationOrBeOverwrittenAsEnabled() = fixture { directory ->
        var writes = 0
        var preferenceCalls = 0
        val store = QmplusFeatureStore(directory, { byteArrayOf(0, 0, 0, 0) }, { writes++ })
        assertThrows(IllegalArgumentException::class.java) {
            val mirror = store.status()
            val enabled = QmplusFeatureMigrationPolicy.resolve(mirror, true, true) { preferenceCalls++; it }
            store.setEnabled(enabled)
        }
        assertEquals(0, preferenceCalls)
        assertEquals(0, writes)
    }

    private fun fixture(work: (java.io.File) -> Unit) {
        val directory = Files.createTempDirectory("wts-qm-feature-test-").toFile()
        try { work(directory) } finally { directory.deleteRecursively() }
    }
}
