package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.*
import org.junit.Test

class QmplusCredentialLimitsTest {
    @Test fun savedLoginInputHasBoundedFieldsAndNoImplicitAcademicPassword() {
        assertFalse(QmplusCredentialLimits.valid("", "synthetic".toCharArray()))
        assertFalse(QmplusCredentialLimits.valid("synthetic@example.invalid", charArrayOf()))
        assertFalse(QmplusCredentialLimits.valid("x".repeat(321), "synthetic".toCharArray()))
        assertFalse(QmplusCredentialLimits.valid("synthetic@example.invalid", CharArray(2049) { 'x' }))
        assertTrue(QmplusCredentialLimits.valid("synthetic@example.invalid", CharArray(2048) { 'x' }))
        assertFalse(QmplusCredentialLimits.valid("synthetic\u0000", "synthetic".toCharArray()))
        assertTrue(QmplusCredentialLimits.valid("  synthetic@example.invalid  ", "設定 raw secret".toCharArray()))
    }
}
