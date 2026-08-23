package com.example.starflow

import android.app.Application

class StarflowApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        NativeAppLogger.install(this)
    }
}
