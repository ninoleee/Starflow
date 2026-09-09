package com.example.starflow

import androidx.media3.datasource.HttpDataSource

internal object NativePlaybackErrorPolicy {
    fun isPreparedAddressRefreshable(code: Int?): Boolean =
        PlaybackReliabilityPolicy.isAddressRefreshable(code)

    fun httpResponseCode(error: Throwable): Int? =
        generateSequence<Throwable>(error) { it.cause }
            .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
            .firstOrNull()
            ?.responseCode
}
