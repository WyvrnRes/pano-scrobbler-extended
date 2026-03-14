package com.arn.scrobble.info

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.paging.compose.collectAsLazyPagingItems
import com.arn.scrobble.api.UserCached
import com.arn.scrobble.api.lastfm.Artist
import com.arn.scrobble.api.lastfm.Track
import com.arn.scrobble.navigation.PanoRoute
import com.arn.scrobble.ui.EntriesGridOrList
import com.arn.scrobble.ui.FilePicker
import com.arn.scrobble.ui.FilePickerMode
import com.arn.scrobble.ui.FileType
import com.arn.scrobble.ui.PanoSnackbarVisuals
import com.arn.scrobble.utils.PlatformFile
import com.arn.scrobble.utils.PlatformStuff
import com.arn.scrobble.utils.Stuff
import com.arn.scrobble.utils.Stuff.collectAsStateWithInitialValue
import com.arn.scrobble.utils.redactedMessage
import kotlinx.coroutines.launch
import org.jetbrains.compose.resources.getString
import org.jetbrains.compose.resources.stringResource
import pano_scrobbler.composeapp.generated.resources.Res
import pano_scrobbler.composeapp.generated.resources.create
import pano_scrobbler.composeapp.generated.resources.edit
import pano_scrobbler.composeapp.generated.resources.not_found
import pano_scrobbler.composeapp.generated.resources.yt_music
import pano_scrobbler.composeapp.generated.resources.yt_music_auth_file
import pano_scrobbler.composeapp.generated.resources.yt_music_auth_file_missing
import pano_scrobbler.composeapp.generated.resources.yt_music_auth_file_pick
import pano_scrobbler.composeapp.generated.resources.yt_music_playlist_created
import pano_scrobbler.composeapp.generated.resources.yt_music_playlist_desc
import pano_scrobbler.composeapp.generated.resources.yt_music_playlist_unheard_recs


@Composable
fun SimilarTracksScreen(
    track: Track,
    user: UserCached,
    appId: String?,
    onNavigate: (PanoRoute.Modal) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: SimilarTracksVM = viewModel { SimilarTracksVM(track) },
) {
    val similarTracks = viewModel.similarTracks.collectAsLazyPagingItems()
    val playlistViewModel: SimilarTracksPlaylistVM = viewModel(key = "SimilarTracksPlaylistVM") {
        SimilarTracksPlaylistVM(track)
    }
    val isCreatingPlaylist by playlistViewModel.isCreatingPlaylist.collectAsStateWithLifecycle()
    val authFileUri by PlatformStuff.mainPrefs.data.collectAsStateWithInitialValue { it.ytMusicAuthFileUri }
    val authFileName = remember(authFileUri) {
        authFileUri?.let {
            runCatching { PlatformFile(it).name() }.getOrElse { _ -> it }
        }
    }
    val scope = rememberCoroutineScope()
    var filePickerShown by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        playlistViewModel.playlistCreationResult.collect { result ->
            result.onSuccess {
                Stuff.globalSnackbarFlow.emit(
                    PanoSnackbarVisuals(
                        getString(Res.string.yt_music_playlist_created, it.addedCount)
                    )
                )
                PlatformStuff.openInBrowser(it.playlistUrl)
            }.onFailure {
                Stuff.globalSnackbarFlow.emit(
                    PanoSnackbarVisuals(
                        message = it.redactedMessage,
                        isError = true,
                        longDuration = true,
                    )
                )
            }
        }
    }

    Column(modifier = modifier) {
        if (PlatformStuff.isDesktop) {
            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                Text(
                    text = stringResource(Res.string.yt_music_playlist_unheard_recs),
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    text = stringResource(Res.string.yt_music_playlist_desc),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    text = authFileName?.let {
                        stringResource(Res.string.yt_music_auth_file, it)
                    } ?: stringResource(Res.string.yt_music_auth_file_missing),
                    style = MaterialTheme.typography.bodySmall,
                )

                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    OutlinedButton(
                        onClick = { filePickerShown = true },
                    ) {
                        Text(
                            if (authFileUri.isNullOrBlank())
                                stringResource(Res.string.yt_music_auth_file_pick)
                            else
                                stringResource(Res.string.edit)
                        )
                    }

                    OutlinedButton(
                        enabled = !isCreatingPlaylist && !authFileUri.isNullOrBlank(),
                        onClick = {
                            playlistViewModel.createPlaylist(authFileUri)
                        },
                    ) {
                        Text(
                            if (isCreatingPlaylist)
                                stringResource(Res.string.create) + "…"
                            else
                                stringResource(Res.string.create) + " " + stringResource(Res.string.yt_music)
                        )
                    }

                }
            }
        }

        EntriesGridOrList(
            entries = similarTracks,
            fetchAlbumImageIfMissing = true,
            showArtists = true,
            emptyStringRes = Res.string.not_found,
            placeholderItem = remember {
                Track(
                    name = "Track",
                    artist = Artist(
                        name = "Artist",
                    ),
                    playcount = 10,
                    album = null,
                )
            },
            onItemClick = {
                onNavigate(
                    PanoRoute.Modal.MusicEntryInfo(
                        track = it as Track,
                        appId = appId,
                        user = user
                    )
                )
            },
            modifier = Modifier.fillMaxWidth()
        )
    }

    FilePicker(
        show = filePickerShown && PlatformStuff.isDesktop,
        mode = FilePickerMode.Open(),
        type = FileType.JSON,
        onDismiss = { filePickerShown = false },
    ) {
        scope.launch {
            PlatformStuff.mainPrefs.updateData { prefs ->
                prefs.copy(ytMusicAuthFileUri = it.uri)
            }
        }
    }

}