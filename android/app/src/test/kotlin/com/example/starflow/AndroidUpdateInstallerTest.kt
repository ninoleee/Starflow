package com.example.starflow

import android.app.Activity
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.content.pm.SigningInfo
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import org.mockito.ArgumentCaptor
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class AndroidUpdateInstallerTest {
    private fun installCall() = MethodCall("installApk", mapOf(
        "path" to "/private/updates/update.apk", "sha256" to "a".repeat(64),
        "versionCode" to 2L, "certificateSha256" to "b".repeat(64),
    ))

    @Test fun api23UsesLegacySignaturesAndVersionCode() {
        val signature = mock(Signature::class.java)
        `when`(signature.toByteArray()).thenReturn(byteArrayOf(1, 2, 3))
        val info = mock(PackageInfo::class.java)
        info.packageName = "com.example.starflow"
        @Suppress("DEPRECATION")
        info.versionCode = 123
        @Suppress("DEPRECATION")
        info.signatures = arrayOf(signature)
        val identity = AndroidUpdateInstaller.identity(info, 23)
        assertEquals(123L, identity.versionCode)
        assertEquals(setOf(AndroidUpdatePolicy.sha256(byteArrayOf(1, 2, 3))), identity.certificateDigests)
        @Suppress("DEPRECATION")
        assertEquals(PackageManager.GET_SIGNATURES, AndroidUpdateInstaller.signatureFlags(23))
    }

    @Test fun api28UsesCurrentSignersAndLongVersionNotSigningHistory() {
        val signature = mock(Signature::class.java)
        `when`(signature.toByteArray()).thenReturn(byteArrayOf(4, 5, 6))
        val signing = mock(SigningInfo::class.java)
        `when`(signing.apkContentsSigners).thenReturn(arrayOf(signature))
        val info = mock(PackageInfo::class.java)
        info.packageName = "com.example.starflow"
        info.signingInfo = signing
        `when`(info.longVersionCode).thenReturn(Int.MAX_VALUE.toLong() + 1L)
        val identity = AndroidUpdateInstaller.identity(info, 28)
        assertEquals(Int.MAX_VALUE.toLong() + 1L, identity.versionCode)
        assertEquals(setOf(AndroidUpdatePolicy.sha256(byteArrayOf(4, 5, 6))), identity.certificateDigests)
        verify(signing, never()).signingCertificateHistory
        assertEquals(PackageManager.GET_SIGNING_CERTIFICATES, AndroidUpdateInstaller.signatureFlags(28))
    }

    @Test fun api28DoesNotFallBackToLegacySignaturesWhenSigningInfoIsMissing() {
        val info = mock(PackageInfo::class.java)
        @Suppress("DEPRECATION")
        info.signatures = arrayOf(mock(Signature::class.java))
        assertTrue(AndroidUpdateInstaller.identity(info, 28).certificateDigests.isEmpty())
    }

    @Test fun api23PermissionQueryIsGracefulAndSettingsNeverLaunchInstallation() {
        val activity = mock(Activity::class.java)
        val executor = mock(ExecutorService::class.java)
        val bridge = AndroidUpdateInstaller(activity, executor, 23, { it() })
        val permission = mock(MethodChannel.Result::class.java)
        val settings = mock(MethodChannel.Result::class.java)
        bridge.onMethodCall(MethodCall("canInstallUpdates", null), permission)
        bridge.onMethodCall(MethodCall("openInstallPermissionSettings", null), settings)
        verify(permission).success(true)
        verify(settings).success(false)
        verifyNoInteractions(activity, executor)
        bridge.close()
    }

    @Test fun api26PermissionDenialDoesNotQueueVerificationOrOpenSettings() {
        val activity = mock(Activity::class.java)
        val manager = mock(PackageManager::class.java)
        val executor = mock(ExecutorService::class.java)
        `when`(activity.packageManager).thenReturn(manager)
        `when`(manager.canRequestPackageInstalls()).thenReturn(false)
        val bridge = AndroidUpdateInstaller(activity, executor, 26, { it() })
        val result = mock(MethodChannel.Result::class.java)
        bridge.onMethodCall(MethodCall("installApk", mapOf(
            "path" to "/private/updates/update.apk", "sha256" to "a".repeat(64),
            "versionCode" to 2L, "certificateSha256" to "b".repeat(64),
        )), result)
        verify(result).error("installPermissionRequired", "Update installation permission is required.", null)
        verifyNoInteractions(executor)
        verify(activity, never()).startActivity(any())
        bridge.close()
    }

    @Test fun closedBridgeReturnsOnlySanitizedError() {
        val activity = mock(Activity::class.java)
        val executor = mock(ExecutorService::class.java)
        val bridge = AndroidUpdateInstaller(activity, executor, 23, { it() })
        bridge.close()
        val result = mock(MethodChannel.Result::class.java)
        bridge.onMethodCall(MethodCall("installApk", "/sensitive/path"), result)
        verify(result).error("update_closed", "Update installer is no longer available.", null)
        verify(executor).shutdownNow()
        verifyNoInteractions(activity)
    }

    @Test fun backgroundInstallRequestDoesNotQueueWork() {
        val activity = mock(Activity::class.java)
        val executor = mock(ExecutorService::class.java)
        val bridge = AndroidUpdateInstaller(activity, executor, 23, { it() })
        val result = mock(MethodChannel.Result::class.java)
        bridge.onMethodCall(installCall(), result)
        verify(result).error("not_foreground", "Return to the app before installing an update.", null)
        verifyNoInteractions(executor)
        verify(activity, never()).startActivity(any())
        bridge.close()
    }

    @Test fun lostForegroundAtLaunchDeletesSnapshotAndNeverOpensInstaller() {
        val activity = mock(Activity::class.java)
        val executor = mock(ExecutorService::class.java)
        val bridge = AndroidUpdateInstaller(activity, executor, 23, { it() })
        val snapshot = File.createTempFile("starflow-update-test-", ".apk")
        try {
            val result = mock(MethodChannel.Result::class.java)
            bridge.launchInstaller(snapshot, result)
            verify(result).error("not_foreground", "Return to the app before installing an update.", null)
            verify(activity, never()).startActivity(any())
            assertFalse(snapshot.exists())
        } finally {
            snapshot.delete()
            bridge.close()
        }
    }

    @Test fun revokedPermissionAtLaunchDeletesSnapshotAndDoesNotOpenSettings() {
        val activity = mock(Activity::class.java)
        val manager = mock(PackageManager::class.java)
        `when`(activity.packageManager).thenReturn(manager)
        val bridge = AndroidUpdateInstaller(activity, mock(ExecutorService::class.java), 26, { it() })
        val snapshot = File.createTempFile("starflow-update-test-", ".apk")
        try {
            val result = mock(MethodChannel.Result::class.java)
            bridge.launchInstaller(snapshot, result)
            verify(result).error("installPermissionRequired", "Update installation permission is required.", null)
            verify(activity, never()).startActivity(any())
            assertFalse(snapshot.exists())
        } finally {
            snapshot.delete()
            bridge.close()
        }
    }

    @Test fun verificationIsQueuedRejectsConcurrentCallAndCloseCompletesOnce() {
        val activity = mock(Activity::class.java)
        `when`(activity.hasWindowFocus()).thenReturn(true)
        val executor = mock(ExecutorService::class.java)
        val bridge = AndroidUpdateInstaller(activity, executor, 23, { it() })
        val first = mock(MethodChannel.Result::class.java)
        bridge.onMethodCall(installCall(), first)
        val queued = ArgumentCaptor.forClass(Runnable::class.java)
        verify(executor).execute(queued.capture())
        verifyNoInteractions(first)
        val second = mock(MethodChannel.Result::class.java)
        bridge.onMethodCall(installCall(), second)
        verify(second).error("update_busy", "An update verification is already in progress.", null)
        bridge.close()
        queued.value.run()
        verify(first, times(1)).error("update_closed", "Update installer is no longer available.", null)
        verifyNoMoreInteractions(first)
        verify(activity, never()).startActivity(any())
    }
}
