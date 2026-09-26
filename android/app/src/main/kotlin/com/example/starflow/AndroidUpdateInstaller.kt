package com.example.starflow

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

internal class AndroidUpdateInstaller(
    private val activity: Activity,
    private val executor: ExecutorService = Executors.newSingleThreadExecutor(),
    private val sdkInt: Int = Build.VERSION.SDK_INT,
    private val postToMain: (() -> Unit) -> Unit = { activity.runOnUiThread(it) },
) : MethodChannel.MethodCallHandler {
    @Volatile private var closed = false
    private var pending: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.fail(AndroidUpdateError.CLOSED)
            return
        }
        try {
            when (call.method) {
                "deviceInfo" -> result.success(mapOf(
                    "sdkInt" to sdkInt,
                    "abis" to Build.SUPPORTED_ABIS.toList(),
                    "versionCode" to versionCode(installedPackage(), sdkInt),
                    "packageName" to activity.packageName,
                ))
                "canInstallUpdates" -> result.success(canInstallUpdates())
                "openInstallPermissionSettings" -> result.success(openPermissionSettings())
                "installApk" -> install(AndroidUpdatePolicy.parse(call.arguments), result)
                else -> result.notImplemented()
            }
        } catch (error: AndroidUpdateException) {
            result.fail(error.reason)
        } catch (_: Exception) {
            result.fail(AndroidUpdateError.FAILED)
        }
    }

    internal fun canInstallUpdates(): Boolean =
        sdkInt < Build.VERSION_CODES.O || activity.packageManager.canRequestPackageInstalls()

    private fun openPermissionSettings(): Boolean {
        if (sdkInt < Build.VERSION_CODES.O) return false
        return try {
            activity.startActivity(Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            ))
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun install(request: AndroidUpdateRequest, result: MethodChannel.Result) {
        if (pending != null) AndroidUpdatePolicy.fail(AndroidUpdateError.BUSY)
        if (!canInstallUpdates()) AndroidUpdatePolicy.fail(AndroidUpdateError.PERMISSION_REQUIRED)
        if (!activity.hasWindowFocus()) AndroidUpdatePolicy.fail(AndroidUpdateError.NOT_FOREGROUND)
        pending = result
        try {
            executor.execute {
                var snapshot: File? = null
                val error = try {
                    if (closed) AndroidUpdatePolicy.fail(AndroidUpdateError.CLOSED)
                    snapshot = verifiedSnapshot(request)
                    null
                } catch (failure: AndroidUpdateException) {
                    failure.reason
                } catch (_: IOException) {
                    AndroidUpdateError.FILE_UNAVAILABLE
                } catch (_: Exception) {
                    AndroidUpdateError.FAILED
                }
                val verified = snapshot
                postToMain {
                    if (closed || pending !== result) {
                        verified?.delete()
                    } else {
                        pending = null
                        if (error != null) {
                            result.fail(error)
                        } else {
                            launchInstaller(requireNotNull(verified), result)
                        }
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            pending = null
            result.fail(AndroidUpdateError.CLOSED)
        }
    }

    private fun verifiedSnapshot(request: AndroidUpdateRequest): File {
        val source = AndroidUpdatePolicy.sourceFile(request.path, activity.filesDir, activity.cacheDir)
        val root = AndroidUpdatePolicy.updateRoot(activity.filesDir)
        val directory = File(root, "verified")
        AndroidUpdatePolicy.prepareSnapshotDirectory(directory, System.currentTimeMillis(), protectedSnapshotPath)
        val snapshot = File.createTempFile("install-", ".apk", directory)
        try {
            // The installer reads this private snapshot, never the mutable download source.
            val actualHash = source.inputStream().use { input ->
                snapshot.outputStream().use { output ->
                    val hash = AndroidUpdatePolicy.copyAndHash(input, output) {
                        if (closed || Thread.currentThread().isInterrupted) {
                            AndroidUpdatePolicy.fail(AndroidUpdateError.CLOSED)
                        }
                    }
                    output.fd.sync()
                    hash
                }
            }
            AndroidUpdatePolicy.verifyHash(actualHash, request.sha256)
            if (!snapshot.setReadOnly()) AndroidUpdatePolicy.fail(AndroidUpdateError.FILE_UNAVAILABLE)
            val archive = activity.packageManager.getPackageArchiveInfo(snapshot.path, signatureFlags(sdkInt))
                ?: AndroidUpdatePolicy.fail(AndroidUpdateError.INVALID_APK)
            AndroidUpdatePolicy.verifyIdentity(
                identity(installedPackage(), sdkInt), identity(archive, sdkInt), request,
            )
            return snapshot
        } catch (error: Exception) {
            snapshot.delete()
            throw error
        }
    }

    internal fun launchInstaller(snapshot: File, result: MethodChannel.Result) {
        try {
            if (activity.isFinishing || activity.isDestroyed) {
                AndroidUpdatePolicy.fail(AndroidUpdateError.CLOSED)
            }
            if (!canInstallUpdates()) AndroidUpdatePolicy.fail(AndroidUpdateError.PERMISSION_REQUIRED)
            if (!activity.hasWindowFocus()) AndroidUpdatePolicy.fail(AndroidUpdateError.NOT_FOREGROUND)
            val uri = FileProvider.getUriForFile(
                activity, "${activity.packageName}.update-files", snapshot,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = ClipData.newRawUri("Update APK", uri)
            }
            activity.startActivity(intent)
            protectedSnapshotPath = snapshot.path
            // Retain the snapshot while the external, user-confirmed installer may be reading it.
            result.success(true)
        } catch (error: AndroidUpdateException) {
            snapshot.delete()
            result.fail(error.reason)
        } catch (_: ActivityNotFoundException) {
            snapshot.delete()
            result.fail(AndroidUpdateError.INSTALLER_UNAVAILABLE)
        } catch (_: SecurityException) {
            snapshot.delete()
            result.fail(AndroidUpdateError.INSTALLER_UNAVAILABLE)
        } catch (_: Exception) {
            snapshot.delete()
            result.fail(AndroidUpdateError.FAILED)
        }
    }

    @Suppress("DEPRECATION")
    private fun installedPackage(): PackageInfo =
        activity.packageManager.getPackageInfo(activity.packageName, signatureFlags(sdkInt))

    fun close() {
        closed = true
        pending?.fail(AndroidUpdateError.CLOSED)
        pending = null
        executor.shutdownNow()
    }

    private fun MethodChannel.Result.fail(error: AndroidUpdateError) {
        this.error(error.code, error.safeMessage, null)
    }

    companion object {
        @Volatile private var protectedSnapshotPath: String? = null

        @Suppress("DEPRECATION")
        internal fun signatureFlags(sdkInt: Int): Int =
            if (sdkInt >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES
            else PackageManager.GET_SIGNATURES

        @Suppress("DEPRECATION")
        internal fun versionCode(info: PackageInfo, sdkInt: Int): Long =
            if (sdkInt >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

        @Suppress("DEPRECATION")
        internal fun identity(info: PackageInfo, sdkInt: Int): AndroidUpdateIdentity {
            val signatures = if (sdkInt >= Build.VERSION_CODES.P) {
                info.signingInfo?.apkContentsSigners
            } else {
                info.signatures
            }
            return AndroidUpdateIdentity(
                info.packageName,
                versionCode(info, sdkInt),
                signatures?.map { AndroidUpdatePolicy.sha256(it.toByteArray()) }?.toSet() ?: emptySet(),
            )
        }
    }
}
