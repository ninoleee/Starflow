package com.example.starflow

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.Locale

internal enum class AndroidUpdateError(val code: String, val safeMessage: String) {
    INVALID_ARGUMENTS("invalid_arguments", "Invalid update arguments."),
    INVALID_PATH("invalid_path", "Update file is outside the allowed directory."),
    FILE_UNAVAILABLE("file_unavailable", "Update file is unavailable."),
    HASH_MISMATCH("hash_mismatch", "Update checksum does not match."),
    INVALID_APK("invalid_apk", "Update package cannot be verified."),
    PACKAGE_MISMATCH("package_mismatch", "Update package identity does not match."),
    VERSION_MISMATCH("version_mismatch", "Update version does not match."),
    NOT_NEWER("not_newer", "Update version must be newer than the installed version."),
    SIGNATURE_MISMATCH("signature_mismatch", "Update signing identity does not match."),
    PERMISSION_REQUIRED("installPermissionRequired", "Update installation permission is required."),
    FILE_TOO_LARGE("file_too_large", "Update file exceeds the size limit."),
    STORAGE_FULL("update_storage_full", "Update snapshot storage is full."),
    NOT_FOREGROUND("not_foreground", "Return to the app before installing an update."),
    INSTALLER_UNAVAILABLE("installer_unavailable", "Package installer is unavailable."),
    BUSY("update_busy", "An update verification is already in progress."),
    CLOSED("update_closed", "Update installer is no longer available."),
    FAILED("update_failed", "Update operation could not be completed."),
}

internal class AndroidUpdateException(val reason: AndroidUpdateError) :
    Exception(reason.safeMessage)

internal data class AndroidUpdateRequest(
    val path: String,
    val sha256: String,
    val versionCode: Long,
    val certificateSha256: String,
)

internal data class AndroidUpdateIdentity(
    val packageName: String?,
    val versionCode: Long,
    val certificateDigests: Set<String>,
)

internal object AndroidUpdatePolicy {
    const val PACKAGE_NAME = "com.example.starflow"
    const val MAX_APK_BYTES = 512L * 1024 * 1024
    const val SNAPSHOT_RETENTION_MS = 24L * 60 * 60 * 1000
    const val MAX_SNAPSHOTS = 4
    private val digestPattern = Regex("[0-9a-fA-F]{64}")

    fun parse(arguments: Any?): AndroidUpdateRequest {
        val args = arguments as? Map<*, *> ?: fail(AndroidUpdateError.INVALID_ARGUMENTS)
        val path = args["path"] as? String ?: fail(AndroidUpdateError.INVALID_ARGUMENTS)
        val versionCode = when (val value = args["versionCode"]) {
            is Int -> value.toLong()
            is Long -> value
            else -> fail(AndroidUpdateError.INVALID_ARGUMENTS)
        }
        if (path.isBlank() || '\u0000' in path || versionCode <= 0) {
            fail(AndroidUpdateError.INVALID_ARGUMENTS)
        }
        return AndroidUpdateRequest(
            path, digest(args["sha256"]), versionCode, digest(args["certificateSha256"]),
        )
    }

    private fun digest(value: Any?): String {
        val text = value as? String ?: fail(AndroidUpdateError.INVALID_ARGUMENTS)
        if (!digestPattern.matches(text)) fail(AndroidUpdateError.INVALID_ARGUMENTS)
        return text.lowercase(Locale.ROOT)
    }

    fun updateRoot(base: File): File {
        val parent = base.canonicalFile
        val root = File(parent, "updates")
        // Do not allow a redirected updates directory to redefine the trust boundary.
        if (root.canonicalFile != root) fail(AndroidUpdateError.INVALID_PATH)
        return root
    }

    fun sourceFile(path: String, filesDir: File, cacheDir: File): File {
        val requested = File(path)
        if (!requested.isAbsolute) fail(AndroidUpdateError.INVALID_PATH)
        val file = requested.canonicalFile
        val roots = listOf(updateRoot(filesDir), updateRoot(cacheDir))
        if (roots.none { file.path.startsWith(it.path + File.separator) }) {
            fail(AndroidUpdateError.INVALID_PATH)
        }
        if (!file.isFile || !file.canRead() || file.length() == 0L) {
            fail(AndroidUpdateError.FILE_UNAVAILABLE)
        }
        if (file.length() > MAX_APK_BYTES) fail(AndroidUpdateError.FILE_TOO_LARGE)
        return file
    }

    fun copyAndHash(
        input: InputStream,
        output: OutputStream,
        maxBytes: Long = MAX_APK_BYTES,
        checkCancelled: () -> Unit = {},
    ): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            checkCancelled()
            val count = input.read(buffer)
            if (count == -1) break
            if (count == 0) continue
            if (count.toLong() > maxBytes - total) fail(AndroidUpdateError.FILE_TOO_LARGE)
            output.write(buffer, 0, count)
            digest.update(buffer, 0, count)
            total += count
        }
        if (total == 0L) fail(AndroidUpdateError.FILE_UNAVAILABLE)
        return hex(digest.digest())
    }

    fun prepareSnapshotDirectory(directory: File, nowMs: Long, protectedPath: String?) {
        if (directory.canonicalFile != directory) fail(AndroidUpdateError.INVALID_PATH)
        if (!directory.isDirectory && !directory.mkdirs()) fail(AndroidUpdateError.FILE_UNAVAILABLE)
        val files = directory.listFiles() ?: fail(AndroidUpdateError.FILE_UNAVAILABLE)
        var retained = 0
        for (file in files) {
            // Never follow links, recurse, or remove a recently handed-off installation snapshot.
            val stale = file.canonicalFile == file && file.isFile &&
                file.name.startsWith("install-") && file.name.endsWith(".apk") &&
                file.path != protectedPath && file.lastModified() > 0 &&
                file.lastModified() < nowMs - SNAPSHOT_RETENTION_MS
            if (!stale || !file.delete()) retained++
        }
        if (retained >= MAX_SNAPSHOTS) fail(AndroidUpdateError.STORAGE_FULL)
    }

    fun sha256(bytes: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(bytes))

    fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }

    fun verifyHash(actual: String, expected: String) {
        if (actual != expected) fail(AndroidUpdateError.HASH_MISMATCH)
    }

    fun verifyIdentity(
        installed: AndroidUpdateIdentity,
        archive: AndroidUpdateIdentity,
        request: AndroidUpdateRequest,
    ) {
        if (installed.packageName != PACKAGE_NAME || archive.packageName != PACKAGE_NAME) {
            fail(AndroidUpdateError.PACKAGE_MISMATCH)
        }
        if (archive.versionCode != request.versionCode) fail(AndroidUpdateError.VERSION_MISMATCH)
        if (archive.versionCode <= installed.versionCode) fail(AndroidUpdateError.NOT_NEWER)
        // A single expected certificate is the contract. Do not infer rotation or trust history.
        if (archive.certificateDigests != installed.certificateDigests ||
            archive.certificateDigests != setOf(request.certificateSha256)
        ) {
            fail(AndroidUpdateError.SIGNATURE_MISMATCH)
        }
    }

    fun fail(error: AndroidUpdateError): Nothing = throw AndroidUpdateException(error)
}
