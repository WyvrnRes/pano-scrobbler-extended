package com.arn.scrobble.utils

/**
 * Result from creating a YouTube Music playlist through the desktop ytmusicapi bridge.
 */
data class YouTubeMusicPlaylistResult(
    val playlistId: String,
    val playlistUrl: String,
    val addedCount: Int,
    val totalRequestedCount: Int,
    val unmatchedTracks: List<String>,
)

