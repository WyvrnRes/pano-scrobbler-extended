#!/usr/bin/env python3
import json
import sys
from typing import Any, Dict, List, Optional, Set


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


try:
    from ytmusicapi import YTMusic
except Exception as exc:  # pragma: no cover - import guard
    fail(f"Failed to import ytmusicapi: {exc}. Install it with `pip install ytmusicapi`.")


def first_video_id(results: List[Dict[str, Any]]) -> Optional[str]:
    for result in results:
        video_id = result.get("videoId")
        if video_id:
            return video_id
    return None


def resolve_video_id(client: YTMusic, track: Dict[str, Any]) -> Optional[str]:
    queries = []
    artist = (track.get("artist") or "").strip()
    title = (track.get("title") or "").strip()
    album = (track.get("album") or "").strip()

    base_query = " ".join(part for part in (artist, title) if part)
    if album:
        queries.append(f"{base_query} {album}".strip())
    if base_query:
        queries.append(base_query)
    queries.append(title)

    seen_queries: Set[str] = set()
    for query in queries:
        if not query or query in seen_queries:
            continue
        seen_queries.add(query)

        for filter_name in ("songs", "videos", None):
            results = client.search(query, filter=filter_name, limit=5)
            video_id = first_video_id(results)
            if video_id:
                return video_id

    return None


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception as exc:
        fail(f"Invalid JSON input: {exc}")

    auth_file_path = payload.get("authFilePath")
    playlist_name = payload.get("playlistName")
    description = payload.get("description") or ""
    tracks = payload.get("tracks") or []

    if not auth_file_path:
        fail("authFilePath is required")
    if not playlist_name:
        fail("playlistName is required")
    if not tracks:
        fail("tracks is required")

    client = YTMusic(auth_file_path)

    video_ids: List[str] = []
    unmatched_tracks: List[str] = []

    for track in tracks:
        video_id = resolve_video_id(client, track)
        if video_id is None:
            unmatched_tracks.append(
                " - ".join(part for part in (track.get("artist"), track.get("title")) if part)
            )
            continue
        video_ids.append(video_id)

    if not video_ids:
        fail("No matching YouTube Music tracks were found for the recommended unheard songs.")

    playlist_id = client.create_playlist(
        title=playlist_name,
        description=description,
    )
    client.add_playlist_items(playlist_id, video_ids)

    response = {
        "playlistId": playlist_id,
        "playlistUrl": f"https://music.youtube.com/playlist?list={playlist_id}",
        "addedCount": len(video_ids),
        "totalRequestedCount": len(tracks),
        "unmatchedTracks": unmatched_tracks,
    }
    json.dump(response, sys.stdout)


if __name__ == "__main__":
    main()


