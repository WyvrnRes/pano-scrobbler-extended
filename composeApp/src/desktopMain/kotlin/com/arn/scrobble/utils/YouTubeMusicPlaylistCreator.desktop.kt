package com.arn.scrobble.utils

import co.touchlab.kermit.Logger
import com.arn.scrobble.api.lastfm.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import pano_scrobbler.composeapp.generated.resources.Res
import java.io.File
import java.io.IOException
import java.net.URI
import java.util.concurrent.TimeUnit

internal object YouTubeMusicPlaylistCreator {
    private const val helperScriptResourcePath = "files/ytmusic_create_playlist.py"
    private const val helperScriptFileName = "ytmusic_create_playlist.py"
    private const val processTimeoutSeconds = 120L

    @Serializable
    private data class HelperTrack(
        val title: String,
        val artist: String,
        val album: String? = null,
    )

    @Serializable
    private data class HelperRequest(
        val authFilePath: String,
        val playlistName: String,
        val description: String,
        val tracks: List<HelperTrack>,
    )

    @Serializable
    private data class HelperResponse(
        val playlistId: String,
        val playlistUrl: String,
        val addedCount: Int,
        val totalRequestedCount: Int,
        val unmatchedTracks: List<String> = emptyList(),
    )

    suspend fun createPlaylist(
        playlistName: String,
        description: String,
        authFileUri: String,
        tracks: List<Track>,
    ): Result<YouTubeMusicPlaylistResult> = withContext(Dispatchers.IO) {
        runCatching {
            val authFilePath = resolveLocalPath(authFileUri)
            require(authFilePath.isNotBlank()) { "Select a YouTube Music auth JSON file first." }
            require(File(authFilePath).isFile) { "Auth JSON file was not found: $authFilePath" }

            val filteredTracks = tracks
                .mapNotNull { track ->
                    val title = track.name.trim()
                    val artist = track.artist.name.trim()
                    if (title.isBlank() || artist.isBlank()) {
                        null
                    } else {
                        HelperTrack(
                            title = title,
                            artist = artist,
                            album = track.album?.name?.trim()?.ifBlank { null },
                        )
                    }
                }
                .distinctBy { it.artist.lowercase() + "\u0000" + it.title.lowercase() }

            require(filteredTracks.isNotEmpty()) { "No recommended unheard tracks were available to add." }

            val helperScript = extractHelperScript()
            val responseJson = runHelper(
                helperScript = helperScript,
                payload = Stuff.myJson.encodeToString(
                    HelperRequest(
                        authFilePath = authFilePath,
                        playlistName = playlistName,
                        description = description,
                        tracks = filteredTracks,
                    )
                )
            )

            val response = Stuff.myJson.decodeFromString<HelperResponse>(responseJson)
            YouTubeMusicPlaylistResult(
                playlistId = response.playlistId,
                playlistUrl = response.playlistUrl,
                addedCount = response.addedCount,
                totalRequestedCount = response.totalRequestedCount,
                unmatchedTracks = response.unmatchedTracks,
            )
        }
    }

    private suspend fun extractHelperScript(): File {
        val scriptBytes = Res.readBytes(helperScriptResourcePath)
        val dir = File(PlatformStuff.cacheDir, "ytmusicapi").also { it.mkdirs() }
        val scriptFile = File(dir, helperScriptFileName)

        if (!scriptFile.exists() || !scriptFile.readBytes().contentEquals(scriptBytes)) {
            scriptFile.writeBytes(scriptBytes)
        }

        return scriptFile
    }

    private fun runHelper(helperScript: File, payload: String): String {
        var lastFailure: Throwable? = null

        for (candidate in pythonCandidates()) {
            try {
                Logger.i { "Running ytmusicapi helper with: ${candidate.joinToString(" ")}" }
                val process = ProcessBuilder(candidate + helperScript.absolutePath)
                    .redirectErrorStream(true)
                    .start()

                process.outputStream.bufferedWriter(Charsets.UTF_8).use {
                    it.write(payload)
                }

                val output = process.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                if (!process.waitFor(processTimeoutSeconds, TimeUnit.SECONDS)) {
                    process.destroyForcibly()
                    throw IOException("Timed out while waiting for the ytmusicapi helper.")
                }

                if (process.exitValue() == 0) {
                    return output
                }

                throw IOException(
                    output.ifBlank {
                        "ytmusicapi helper failed with exit code ${process.exitValue()}."
                    }.trim()
                )
            } catch (t: Throwable) {
                lastFailure = t
            }
        }

        throw IOException(
            lastFailure?.message
                ?: "Could not start Python. Install Python and the ytmusicapi dependency first.",
            lastFailure,
        )
    }

    private fun pythonCandidates(): List<List<String>> {
        return when (DesktopStuff.os) {
            DesktopStuff.Os.Windows -> listOf(
                listOf("py", "-3", "-u"),
                listOf("python", "-u"),
                listOf("python3", "-u"),
            )

            DesktopStuff.Os.Macos,
            DesktopStuff.Os.Linux,
                -> listOf(
                listOf("python3", "-u"),
                listOf("python", "-u"),
            )
        }
    }

    private fun resolveLocalPath(fileUriOrPath: String): String {
        return runCatching {
            if (fileUriOrPath.startsWith("file:")) {
                File(URI(fileUriOrPath)).absolutePath
            } else {
                File(fileUriOrPath).absolutePath
            }
        }.getOrElse {
            fileUriOrPath
        }
    }
}


