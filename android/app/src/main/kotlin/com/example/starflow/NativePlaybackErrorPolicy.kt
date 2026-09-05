package com.example.starflow

import androidx.media3.datasource.HttpDataSource

internal object NativePlaybackErrorPolicy {
    fun isPreparedAddressRefreshable(code: Int?): Boolean = code in listOf(401, 403, 404, 410)

    fun httpResponseCode(error: Throwable): Int? =
        generateSequence<Throwable>(error) { it.cause }
            .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
            .firstOrNull()
            ?.responseCode
}
