# YouTube Music playlist feature setup

This desktop feature creates a YouTube Music playlist from unheard Last.fm recommendations.

## Requirements

- Python 3 installed and available as `python`, `python3`, or `py -3`
- `ytmusicapi` installed
- A `ytmusicapi` auth JSON file
- Your scrobbles indexed in Pano Scrobbler

## Install

```powershell
python -m pip install -r py-scripts/requirements.txt
```

If you use the Windows launcher:

```powershell
py -3 -m pip install -r py-scripts/requirements.txt
```

## Create the auth file

Follow the official `ytmusicapi` authentication instructions to generate a browser-auth JSON file.

Project used by this feature:
- https://github.com/sigma67/ytmusicapi

## Use in the app

1. Open a track's similar tracks screen.
2. In the YouTube Music playlist section, select your auth JSON file.
3. Click **Create YouTube Music**.
4. The app creates a playlist from recommended tracks that are not present in your indexed listening history.

