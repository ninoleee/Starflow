package com.example.starflow

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePlaybackErrorPolicyTest {
    @Test
    fun preparedAddressRefreshOnlyForExpectedHttpStatuses() {
        for (code in listOf(401, 403, 404, 410)) {
            assertTrue(NativePlaybackErrorPolicy.isPreparedAddressRefreshable(code))
        }
        for (code in listOf(400, 408, 429, 500, 503)) {
            assertFalse(NativePlaybackErrorPolicy.isPreparedAddressRefreshable(code))
        }
        assertFalse(NativePlaybackErrorPolicy.isPreparedAddressRefreshable(null))
    }
}
