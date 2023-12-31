# 🎶 Tidal To Apple Music Migrate and Sync

[![GitHub Repo stars](https://img.shields.io/github/stars/youtous/tidal-to-apple-music-sync-migrate?label=✨%20youtous%2Ftidal-to-apple-music-sync-migrate&style=social)](https://github.com/youtous/tidal-to-apple-music-sync-migrate/)
[![Gitlab Repo](https://img.shields.io/badge/gitlab.com%2Fyoutous%2Fsmart--door--opener?label=✨%20youtous%2Ftidal-to-apple-music-sync-migrate&style=social&logo=gitlab)](https://gitlab.com/youtous/tidal-to-apple-music-sync-migrate/)
[![Licence](https://img.shields.io/github/license/youtous/tidal-to-apple-music-sync-migrate)](https://github.com/youtous/tidal-to-apple-music-sync-migrate/blob/main/LICENSE)


Easily migrate or sync your playlists and favorites from Tidal to Apple Music.

**Features :**
- Migrate all your favorites songs, playlists, artists and albums from Tidal to Apple Music
- Reset all your library artists, albums and favorites songs on Apple Music
- Fast! Using parallel requests, the migration takes few seconds on a large library (see `--parallel_requests`)

## Usage

Git clone this repository.

- **Using a container:** `docker run --rm -it -v ./:/workdir ruby sh -c 'cd /workdir && gem install bundler && bundle install && ruby migrate.rb --help'`
- **Using Ruby:** `gem install bundler && bundle install && ruby migrate.rb --help`

### How to get Tidal and Apple Music Tokens?

#### Apple Music

1. Open a new tab in browser
2. Open the developer tools (Ctrl-Shift-I) and select the “Network” tab
3. Go to [https://music.apple.com](https://music.apple.com) and ensure you are logged in
4. Find any authenticated POST request.
5. Copy out the value of the `authorization header` without " bearer" and `media-user-token` request headers

#### Tidal

1. Open a new tab in browser
2. Open the developer tools (Ctrl-Shift-I) and select the “Network” tab
3. Go to [https://listen.tidal.com](https://listen.tidal.com) and ensure you are logged in
4. Find any authenticated POST request.
5. Copy out the value of the `authorization header` without "bearer " request headers

## Help

This is an extract from the `--help` command:

```text
╰─λ ruby migrate.rb --help                                                                                                                0 < 13:21:23
Usage:
    migrate.rb [OPTIONS] [SUBCOMMAND] [ARG] ...

Parameters:
    [SUBCOMMAND]                                                         subcommand (default: "migrate")
    [ARG] ...                                                            subcommand arguments

Subcommands:
    migrate                                                              Copy playlists and favorites from Tidal to Apple Music
    reset_all_favorites_songs                                            Remove from library and rating all favorites songs on Apple Music
    reset_all_library_albums                                             Remove from library all albums on Apple Music
    reset_all_library_artists                                            Remove from library all artists on Apple Music
    reset_all_library_playlists                                          Remove from library all playlists on Apple Music

Options:
    --log_level LOG_LEVEL                                                log level (default: $LOG_LEVEL, or "INFO")
    --parallel_requests PARALLEL_REQUESTS                                How many requests to perfom in parallel? (default: $PARALLEL_REQUESTS, or 10)
    --apple_music_bearer_token APPLE_MUSIC_BEARER_TOKEN                  Apple Music Bearer Token (required)
    --apple_music_music_token APPLE_MUSIC_MUSIC_TOKEN                    Apple Music Music Token (required)
    --apple_music_api_url APPLE_MUSIC_API_URL                            Apple Music API Url (default: $APPLE_MUSIC_API_URL, or "https://amp-api.music.apple.com")
    --apple_music_search_country_code APPLE_MUSIC_SEARCH_COUNTRY_CODE    Apple Music Search country code (default: $APPLE_MUSIC_SEARCH_COUNTRY_CODE, or "FR")
    --tidal_bearer_token TIDAL_BEARER_TOKEN                              Tidal Bearer Token (required)
    --tidal_country_code TIDAL_COUNTRY_CODE                              Tidal Country Code (default: $TIDAL_COUNTRY_CODE, or "AR")
    --tidal_api_url TIDAL_API_URL                                        Tidal API Url (default: $TIDAL_API_URL, or "https://api.tidal.com")
    --tidal_api_listen_url TIDAL_API_LISTEN_URL                          Tidal API Url (default: $TIDAL_API_URL, or "https://listen.tidal.com")
    -h, --help                                                           print help

```

## License

MIT