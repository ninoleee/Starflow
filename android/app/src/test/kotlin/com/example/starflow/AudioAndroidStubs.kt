package com.example.starflow

import android.os.SystemClock
import android.text.TextUtils
import org.junit.rules.ExternalResource
import org.mockito.MockedStatic
import org.mockito.Mockito.*

internal class AudioAndroidStubs : ExternalResource() {
    private lateinit var text: MockedStatic<TextUtils>
    private lateinit var clock: MockedStatic<SystemClock>

    override fun before() {
        text = mockStatic(TextUtils::class.java)
        text.`when`<Boolean> { TextUtils.isEmpty(nullable(CharSequence::class.java)) }
            .thenAnswer { it.getArgument<CharSequence?>(0).isNullOrEmpty() }
        text.`when`<Boolean> { TextUtils.equals(nullable(CharSequence::class.java), nullable(CharSequence::class.java)) }
            .thenAnswer { it.getArgument<CharSequence?>(0)?.toString() == it.getArgument<CharSequence?>(1)?.toString() }
        clock = mockStatic(SystemClock::class.java)
    }

    override fun after() {
        clock.close()
        text.close()
    }
}
