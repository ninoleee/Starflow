package com.example.starflow

object NativePlaybackHlsFallbackPolicy {
    private const val PARSING_CONTAINER_UNSUPPORTED_ERROR_CODE = 3003

    fun shouldRetryAsHls(
        errorCode: Int,
        url: String,
        alreadyAttempted: Boolean,
    ): Boolean {
        return !alreadyAttempted &&
            errorCode == PARSING_CONTAINER_UNSUPPORTED_ERROR_CODE &&
            isSmartStrmUrl(url)
    }

    fun isSmartStrmUrl(url: String): Boolean {
        val normalized = url.trim().lowercase()
        return (normalized.startsWith("http://") || normalized.startsWith("https://")) &&
            normalized.contains("/smartstrm/")
    }
}
