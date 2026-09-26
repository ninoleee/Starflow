package com.example.starflow

import java.io.File
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.RandomAccessFile
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AndroidUpdatePolicyTest {
    @get:Rule val temporary = TemporaryFolder()
    private val hash = "a".repeat(64)
    private val certificate = "b".repeat(64)
    private val request = AndroidUpdateRequest("/unused.apk", hash, 101L, certificate)
    private val installed = AndroidUpdateIdentity("com.example.starflow", 100L, setOf(certificate))
    private val archive = installed.copy(versionCode = 101L)

    private fun args(): Map<String, Any> = mapOf(
        "path" to "/private/updates/release.apk", "sha256" to hash,
        "versionCode" to 101L, "certificateSha256" to certificate,
    )

    private fun rejects(error: AndroidUpdateError, action: () -> Unit) {
        try {
            action()
            fail("Expected ${error.code}")
        } catch (failure: AndroidUpdateException) {
            assertEquals(error, failure.reason)
            assertEquals(error.safeMessage, failure.message)
        }
    }

    @Test fun parsesCodecIntegersAndNormalizesHex() {
        assertEquals(101L, AndroidUpdatePolicy.parse(args()).versionCode)
        assertEquals(101L, AndroidUpdatePolicy.parse(args() + ("versionCode" to 101)).versionCode)
        assertEquals(hash, AndroidUpdatePolicy.parse(args() + ("sha256" to hash.uppercase())).sha256)
        assertEquals(certificate, AndroidUpdatePolicy.parse(
            args() + ("certificateSha256" to certificate.uppercase()),
        ).certificateSha256)
    }

    @Test fun rejectsMalformedArgumentsWithoutCoercion() {
        listOf(null, "path", emptyMap<String, Any>()).forEach { value ->
            rejects(AndroidUpdateError.INVALID_ARGUMENTS) { AndroidUpdatePolicy.parse(value) }
        }
        listOf<Any>(101.0, "101", 0, -1L).forEach { value ->
            rejects(AndroidUpdateError.INVALID_ARGUMENTS) {
                AndroidUpdatePolicy.parse(args() + ("versionCode" to value))
            }
        }
        listOf("", "g".repeat(64), "a".repeat(63), "$hash ", "aa:bb").forEach { value ->
            for (field in listOf("sha256", "certificateSha256")) {
                rejects(AndroidUpdateError.INVALID_ARGUMENTS) {
                    AndroidUpdatePolicy.parse(args() + (field to value))
                }
            }
        }
        listOf("", " ", "/private/\u0000.apk").forEach { value ->
            rejects(AndroidUpdateError.INVALID_ARGUMENTS) {
                AndroidUpdatePolicy.parse(args() + ("path" to value))
            }
        }
    }

    @Test fun acceptsSupportAndTemporaryUpdatesDirectories() {
        val files = temporary.newFolder("files")
        val cache = temporary.newFolder("cache")
        for (base in listOf(files, cache)) {
            val file = File(base, "updates/nested/release.apk")
            file.parentFile.mkdirs()
            file.writeText("apk")
            assertEquals(file.canonicalFile, AndroidUpdatePolicy.sourceFile(file.path, files, cache))
        }
    }

    @Test fun rejectsExternalTraversalSiblingPrefixAndRelativePaths() {
        val files = temporary.newFolder("files")
        val cache = temporary.newFolder("cache")
        File(files, "updates").mkdir()
        val outside = File(files, "secret.apk").apply { writeText("secret") }
        val sibling = File(files, "updates-other/release.apk").apply {
            parentFile.mkdirs()
            writeText("apk")
        }
        for (path in listOf(outside.path, sibling.path, File(files, "updates/../secret.apk").path,
            "updates/release.apk", "content://provider/release.apk", "/sdcard/Download/release.apk")) {
            rejects(AndroidUpdateError.INVALID_PATH) { AndroidUpdatePolicy.sourceFile(path, files, cache) }
        }
    }

    @Test fun rejectsSymlinkEscapeAndRedirectedRoot() {
        val files = temporary.newFolder("files")
        val cache = temporary.newFolder("cache")
        val root = File(files, "updates").apply { mkdir() }
        val outside = temporary.newFile("outside.apk").apply { writeText("apk") }
        val link = File(root, "release.apk")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        rejects(AndroidUpdateError.INVALID_PATH) { AndroidUpdatePolicy.sourceFile(link.path, files, cache) }
        link.delete()
        root.delete()
        Files.createSymbolicLink(root.toPath(), temporary.root.toPath())
        rejects(AndroidUpdateError.INVALID_PATH) {
            AndroidUpdatePolicy.sourceFile(File(root, outside.name).path, files, cache)
        }
    }

    @Test fun rejectsMissingEmptyFilesAndDirectories() {
        val files = temporary.newFolder("files")
        val cache = temporary.newFolder("cache")
        val root = File(files, "updates").apply { mkdir() }
        val empty = File(root, "empty.apk").apply { createNewFile() }
        val directory = File(root, "folder.apk").apply { mkdir() }
        for (file in listOf(empty, directory, File(root, "missing.apk"))) {
            rejects(AndroidUpdateError.FILE_UNAVAILABLE) {
                AndroidUpdatePolicy.sourceFile(file.path, files, cache)
            }
        }
    }

    @Test fun checksKnownSha256AndRejectsMismatch() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            AndroidUpdatePolicy.sha256("abc".toByteArray()))
        AndroidUpdatePolicy.verifyHash(hash, hash)
        rejects(AndroidUpdateError.HASH_MISMATCH) { AndroidUpdatePolicy.verifyHash(hash, certificate) }
    }

    @Test fun boundedCopyRejectsEmptyAndBytesBeyondLimitWhileReading() {
        assertEquals(536870912L, AndroidUpdatePolicy.MAX_APK_BYTES)
        rejects(AndroidUpdateError.FILE_UNAVAILABLE) {
            AndroidUpdatePolicy.copyAndHash(ByteArrayInputStream(byteArrayOf()), ByteArrayOutputStream())
        }
        val bytes = ByteArray(130000) { 7 }
        val output = ByteArrayOutputStream()
        rejects(AndroidUpdateError.FILE_TOO_LARGE) {
            AndroidUpdatePolicy.copyAndHash(ByteArrayInputStream(bytes), output, 100000L)
        }
        assertTrue(output.size() <= 100000)
        val exact = ByteArrayOutputStream()
        assertEquals(AndroidUpdatePolicy.sha256(bytes), AndroidUpdatePolicy.copyAndHash(
            ByteArrayInputStream(bytes), exact, bytes.size.toLong(),
        ))
        assertArrayEquals(bytes, exact.toByteArray())
    }

    @Test fun rejectsOversizedSourceBeforeCopying() {
        val files = temporary.newFolder("files")
        val cache = temporary.newFolder("cache")
        val file = File(files, "updates/large.apk")
        file.parentFile.mkdirs()
        RandomAccessFile(file, "rw").use { it.setLength(AndroidUpdatePolicy.MAX_APK_BYTES + 1) }
        rejects(AndroidUpdateError.FILE_TOO_LARGE) {
            AndroidUpdatePolicy.sourceFile(file.path, files, cache)
        }
    }

    @Test fun cancellationStopsCopyBeforeWriting() {
        val output = ByteArrayOutputStream()
        rejects(AndroidUpdateError.CLOSED) {
            AndroidUpdatePolicy.copyAndHash(ByteArrayInputStream(byteArrayOf(1)), output) {
                AndroidUpdatePolicy.fail(AndroidUpdateError.CLOSED)
            }
        }
        assertEquals(0, output.size())
    }

    @Test fun cleanupDeletesOnlyOldSnapshotsAndProtectsLastExternalReader() {
        val directory = temporary.newFolder("verified").canonicalFile
        val now = System.currentTimeMillis()
        val staleTime = now - AndroidUpdatePolicy.SNAPSHOT_RETENTION_MS - 10000
        val stale = File(directory, "install-stale.apk").apply { writeText("apk"); setLastModified(staleTime) }
        val protected = File(directory, "install-protected.apk").apply { writeText("apk"); setLastModified(staleTime) }
        val recent = File(directory, "install-recent.apk").apply { writeText("apk") }
        val unrelated = File(directory, "other.apk").apply { writeText("apk"); setLastModified(staleTime) }
        AndroidUpdatePolicy.prepareSnapshotDirectory(directory, now, protected.path)
        assertFalse(stale.exists())
        assertTrue(protected.exists())
        assertTrue(recent.exists())
        assertTrue(unrelated.exists())
    }

    @Test fun snapshotQuotaRejectsRepeatedInstallsWithoutDeletingRecentFiles() {
        val directory = temporary.newFolder("verified").canonicalFile
        repeat(AndroidUpdatePolicy.MAX_SNAPSHOTS) { index ->
            File(directory, "install-$index.apk").writeText("apk")
        }
        rejects(AndroidUpdateError.STORAGE_FULL) {
            AndroidUpdatePolicy.prepareSnapshotDirectory(directory, System.currentTimeMillis(), null)
        }
        assertEquals(AndroidUpdatePolicy.MAX_SNAPSHOTS, directory.listFiles()!!.size)
    }

    @Test fun cleanupDoesNotFollowSymlinksOrRecurse() {
        val directory = temporary.newFolder("verified").canonicalFile
        val outside = temporary.newFile("outside.apk").apply { writeText("apk") }
        val link = File(directory, "install-link.apk")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        val nested = File(directory, "install-folder.apk").apply { mkdir() }
        AndroidUpdatePolicy.prepareSnapshotDirectory(directory, System.currentTimeMillis(), null)
        assertTrue(link.exists())
        assertTrue(outside.exists())
        assertTrue(nested.isDirectory)
    }

    @Test fun acceptsOnlyNewerMatchingIdentity() {
        AndroidUpdatePolicy.verifyIdentity(installed, archive, request)
        val large = Int.MAX_VALUE.toLong() + 1L
        AndroidUpdatePolicy.verifyIdentity(installed, archive.copy(versionCode = large), request.copy(versionCode = large))
    }

    @Test fun rejectsWrongPackageAndWrongInstalledIdentity() {
        rejects(AndroidUpdateError.PACKAGE_MISMATCH) {
            AndroidUpdatePolicy.verifyIdentity(installed, archive.copy(packageName = "other.app"), request)
        }
        rejects(AndroidUpdateError.PACKAGE_MISMATCH) {
            AndroidUpdatePolicy.verifyIdentity(installed.copy(packageName = "other.app"), archive, request)
        }
    }

    @Test fun rejectsUnexpectedEqualAndOlderVersionCodes() {
        rejects(AndroidUpdateError.VERSION_MISMATCH) {
            AndroidUpdatePolicy.verifyIdentity(installed, archive.copy(versionCode = 102L), request)
        }
        for (version in listOf(99L, 100L)) {
            rejects(AndroidUpdateError.NOT_NEWER) {
                AndroidUpdatePolicy.verifyIdentity(installed, archive.copy(versionCode = version), request.copy(versionCode = version))
            }
        }
    }

    @Test fun rejectsMissingMismatchedRotatedAndAdditionalSigners() {
        for (signers in listOf(emptySet(), setOf(hash), setOf(certificate, hash))) {
            rejects(AndroidUpdateError.SIGNATURE_MISMATCH) {
                AndroidUpdatePolicy.verifyIdentity(installed, archive.copy(certificateDigests = signers), request)
            }
            rejects(AndroidUpdateError.SIGNATURE_MISMATCH) {
                AndroidUpdatePolicy.verifyIdentity(installed.copy(certificateDigests = signers), archive, request)
            }
        }
        rejects(AndroidUpdateError.SIGNATURE_MISMATCH) {
            AndroidUpdatePolicy.verifyIdentity(installed, archive, request.copy(certificateSha256 = hash))
        }
    }
}
