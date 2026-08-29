package com.alexmercerind.media_kit_libs_android_video;

import android.util.Log;
import androidx.annotation.NonNull;
import com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

public class MediaKitLibsAndroidVideoPlugin implements FlutterPlugin {
    static {
        try {
            System.loadLibrary("mpv");
        } catch (Throwable error) {
            error.printStackTrace();
        }
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        Log.i("media_kit", "package:media_kit_libs_android_video attached.");
        try {
            MediaKitAndroidHelper.setApplicationContextJava(
                binding.getApplicationContext()
            );
        } catch (Throwable error) {
            error.printStackTrace();
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        Log.i("media_kit", "package:media_kit_libs_android_video detached.");
    }
}
