require 'clamp'
require 'logger'
require 'parallel'
require 'httparty'
require 'jwt'

Clamp do
  option '--log_level', 'LOG_LEVEL', 'log level', environment_variable: 'LOG_LEVEL', default: 'INFO'


  option '--parallel_requests', 'PARALLEL_REQUESTS', 'How many requests to perfom in parallel?',
         environment_variable: 'PARALLEL_REQUESTS', default: 10 do |val|
    val.to_i
  end

  option '--apple_music_bearer_token', 'APPLE_MUSIC_BEARER_TOKEN', 'Apple Music Bearer Token',
         environment_variable: 'APPLE_MUSIC_BEARER_TOKEN', required: true
  option '--apple_music_music_token', 'APPLE_MUSIC_MUSIC_TOKEN', 'Apple Music Music Token',
         environment_variable: 'APPLE_MUSIC_MUSIC_TOKEN', required: true
  option '--apple_music_api_url', 'APPLE_MUSIC_API_URL', 'Apple Music API Url',
         environment_variable: 'APPLE_MUSIC_API_URL', default: 'https://amp-api.music.apple.com'
  option '--apple_music_search_country_code', 'APPLE_MUSIC_SEARCH_COUNTRY_CODE', 'Apple Music Search country code',
         environment_variable: 'APPLE_MUSIC_SEARCH_COUNTRY_CODE', default: 'FR'

  option '--tidal_bearer_token', 'TIDAL_BEARER_TOKEN', 'Tidal Bearer Token',
         environment_variable: 'TIDAL_BEARER_TOKEN', required: true
  option '--tidal_country_code', 'TIDAL_COUNTRY_CODE', 'Tidal Country Code',
         environment_variable: 'TIDAL_COUNTRY_CODE', default: 'AR'
  option '--tidal_api_url', 'TIDAL_API_URL', 'Tidal API Url', environment_variable: 'TIDAL_API_URL', default: 'https://api.tidal.com'
  option '--tidal_api_listen_url', 'TIDAL_API_LISTEN_URL', 'Tidal API Url', environment_variable: 'TIDAL_API_URL',
         default: 'https://listen.tidal.com'


  self.default_subcommand = 'migrate'

  subcommand 'migrate', 'Copy playlists and favorites from Tidal to Apple Music' do
  option "--add_artists_to_favorites", :flag, "Add artists to favorites (migrate only)", default: false
  option "--remove_artists_from_favorites", :flag, "Remove artists to favorites (migrate only)", default: false
  option "--add_albums_to_favorites", :flag, "Add albums to favorites (migrate only)", default: false
  option "--remove_albums_from_favorites", :flag, "Remove albums from favorites (migrate only)", default: false

  option "--do_not_sync_albums", :flag, "Prevent synchronization of library albums (migrate only)", default: false
  option "--do_not_sync_artists", :flag, "Prevent synchronization of library artists (migrate only)", default: false
  option "--do_not_sync_playlists", :flag, "Prevent synchronization of library playlists (migrate only)", default: false
  option "--do_not_sync_favorites", :flag, "Prevent synchronization of library favorites songs (migrate only)", default: false

  def execute
    init

    not_found_items = []

    unless self.do_not_sync_albums?
      # Sync Albums
      tidal_favorite_albums = tidal_get_entity_v1("albums")
      if self.add_albums_to_favorites?
        # Sync Artists - add to favorites
        not_found_items += add_tidal_albums_to_apple_library(items: tidal_favorite_albums, like: true)
      elsif self.remove_albums_from_favorites?
        not_found_items += add_tidal_albums_to_apple_library(items: tidal_favorite_albums, like: false)
      else
        not_found_items += add_tidal_albums_to_apple_library(items: tidal_favorite_albums, like: nil)
      end
    end

    unless self.do_not_sync_artists?
      # Sync Artists
      tidal_favorite_artists = tidal_get_entity_v1("artists")
      if self.add_artists_to_favorites?
        # Sync Artists - add to favorites
        not_found_items += add_tidal_artists_to_apple_favorites(items: tidal_favorite_artists, like: true)
      elsif self.remove_artists_from_favorites?
        not_found_items += add_tidal_artists_to_apple_favorites(items: tidal_favorite_artists, like: false)
      end
    end

    apple_music_playlists = apple_music_get_library_entities('playlists')
    log.info("Found #{apple_music_playlists.length} playlists: #{apple_music_playlists}")
    hash_apple_music_playlists = {}
    apple_music_playlists.each { |playlist|  hash_apple_music_playlists[playlist["attributes"]["name"]] = playlist }

    unless self.do_not_sync_playlists?
      # Sync playlists with tracks
      tidal_playlists = tidal_get_my_collection_playlists_v2
      log.info("Found #{tidal_playlists.length} playlists: #{tidal_playlists}")

      tidal_playlists.each do |playlist|
        # create missing playlists
        unless hash_apple_music_playlists.has_key? playlist["name"]
          playlist_created = apple_music_post_library_entity("playlists", {name: playlist["name"]})
          hash_apple_music_playlists[playlist["name"]] = playlist_created["data"][0]
        end

        apple_playlist = hash_apple_music_playlists[playlist["name"]]

        # for this playlist, get the titles
        playlist_items = tidal_get_entity_items_v1(playlist["data"]["uuid"], "playlists")
        log.info("Found #{playlist_items.length} songs in #{playlist["name"]}: #{playlist_items}")


        not_found_items += add_tidal_items_to_apple_playlist(playlist_items, apple_playlist)
      end
    end

    unless self.do_not_sync_favorites?
      # for the favorites, create a special playlist and also like the tracks
      favorites_playlist_name = "Favorites"
      unless hash_apple_music_playlists.has_key? favorites_playlist_name
        playlist_created = apple_music_post_library_entity("playlists", {name: favorites_playlist_name})
        hash_apple_music_playlists[favorites_playlist_name] = playlist_created["data"][0]
      end

      tidal_favorite_tracks = tidal_get_entity_v1("tracks")
      log.info("Found #{tidal_favorite_tracks.length} tracks: #{tidal_favorite_tracks}")
      not_found_items += add_tidal_items_to_apple_playlist(tidal_favorite_tracks, hash_apple_music_playlists[favorites_playlist_name], true, true)

      # Videos are treated as songs
      tidal_favorite_videos = tidal_get_entity_v1("videos")
      log.info("Found #{tidal_favorite_videos.length} videos: #{tidal_favorite_videos}")
      not_found_items += add_tidal_items_to_apple_playlist(tidal_favorite_videos, hash_apple_music_playlists[favorites_playlist_name], true, true, item_type: "videos")
    end

    unless not_found_items.empty?
      log.warn("The following items cannot be found on Apple Music, please proceed manually: #{not_found_items}")
    end
  end
end

  subcommand 'reset_all_favorites_songs', 'Remove from library and rating all favorites songs on Apple Music' do
    def execute
      init

      all_existing_favorites_songs = apple_music_get_library_entities('songs')
      log.info("Found #{all_existing_favorites_songs.length} existing favorite songs to remove from library: #{all_existing_favorites_songs}")
      Parallel.each(all_existing_favorites_songs, in_threads: self.parallel_requests, progress: "Removing songs from library") do |i|
        apple_music_remove_entity_from_library(i["id"], "songs")
        log.info("Song #{i['id']} removed from library!")
        if i["attributes"] and i["attributes"]["playParams"] and i["attributes"]["playParams"]["catalogId"]
          apple_music_put_rating_entity(i["attributes"]["playParams"]["catalogId"], "songs", false)
          log.info("Song #{i['id']} removed from ratings!")
        end
      end
    end
  end

  subcommand 'reset_all_library_albums', 'Remove from library all albums on Apple Music' do
    def execute
      init

      all_existing_favorites_albums = apple_music_get_library_entities('albums')
      log.info("Found #{all_existing_favorites_albums.length} existing albums to remove from library: #{all_existing_favorites_albums}")
      Parallel.each(all_existing_favorites_albums, in_threads: self.parallel_requests, progress: "Removing albums from library") do |i|
        apple_music_remove_entity_from_library(i["id"], "albums")
        log.info("Album #{i['id']} removed from library!")
      end
    end
  end

  subcommand 'reset_all_library_artists', 'Remove from library all artists on Apple Music' do
    def execute
      init

      all_existing_favorites_artists = apple_music_get_library_entities('artists')
      log.info("Found #{all_existing_favorites_artists.length} existing artists to remove from library: #{all_existing_favorites_artists}")
      Parallel.each(all_existing_favorites_artists, in_threads: self.parallel_requests, progress: "Removing artists from library") do |i|
        apple_music_remove_entity_from_library(i["id"], "artists")
        log.info("Artist #{i['id']} removed from library!")
      end
    end
  end

  subcommand 'reset_all_library_playlists', 'Remove from library all playlists on Apple Music' do
    def execute
      init

      all_playlists = apple_music_get_library_entities('playlists')
      log.info("Found #{all_playlists.length} existing playlists to remove from library: #{all_playlists}")
      Parallel.each(all_playlists, in_threads: self.parallel_requests, progress: "Removing playlists from library") do |i|
        apple_music_remove_entity_from_library(i["id"], "all_playlists")
        log.info("Playlist #{i['id']} removed from library!")
      end
    end
  end

  def init
    @log = Logger.new($stdout, level: log_level)
    tidal_auth
    apple_music_auth
  end

  def add_tidal_artists_to_apple_favorites(items:, like: true)
    not_found_items = Queue.new
    log.info("Found #{items.length} artists: #{items}")
    Parallel.each(items, in_threads: self.parallel_requests, progress: "Adding artists to Apple Music") do |artist|
      searched_item = apple_music_search_catalog(term: "#{artist["item"]["name"]}", country_code: "FR", types: ["artists"])
      if searched_item["results"].empty? or searched_item["results"]["artists"].empty?
        log.warn("Tidal artist not found on Apple Music, review manually : #{artist}")
        not_found_items.push({item: artist})
      else
        apple_music_put_rating_entity(searched_item["results"]["artists"]["data"][0]["id"], "artists", like)
      end
    end
    return Array.new(not_found_items.size) { not_found_items.pop }
  end

  def add_tidal_albums_to_apple_library(items:, like: false)
    not_found_items = Queue.new
    log.info("Found #{items.length} albums: #{items}")
    Parallel.each(items,in_threads: self.parallel_requests, progress: "Adding albums to Apple Music") do |album|
      searched_item = apple_music_search_catalog(term: "#{album["item"]["title"]} #{album["item"]["artist"]["name"]}", country_code: "FR", types: ["albums"])
      if searched_item["results"].empty? or searched_item["results"]["albums"].empty?  or searched_item["results"]["albums"]["data"].empty?
        log.warn("Tidal album not found on Apple Music, review manually : #{album}")
        not_found_items.push({item: album})
      else
        album_id = searched_item["results"]["albums"]["data"][0]["id"]
        apple_music_add_entities_to_library(album_id, "albums")

        if like != nil
          apple_music_put_rating_entity(album_id, "albums", like)
        end
      end
    end
    return Array.new(not_found_items.size) { not_found_items.pop }
  end

  def add_tidal_items_to_apple_playlist(items, apple_playlist, rate_like=false, add_to_library=false, item_type: "songs")
    not_found_items = Queue.new
    # get all songs in the playlist
    apple_music_playlist_items = apple_music_get_playlist_tracks(apple_playlist["id"])
    hash_apple_music_playlist_songs = {}

    apple_music_playlist_items.each do |item|
      play_params = item["attributes"]["playParams"]
      if play_params
        hash_apple_music_playlist_songs[play_params["catalogId"]] = item
      end
    end

    log.info("All songs in playlist '#{apple_playlist["attributes"]["name"]}': #{hash_apple_music_playlist_songs}")

    Parallel.each(items,in_threads: self.parallel_requests, progress: "Adding items to Apple Music") do |item|

      term =  "#{item["item"]["title"]}"
      if item["item"]["album"] and item["item"]["album"]["title"]
        term += " #{item["item"]["album"]["title"]}"
      end
      log.info("Searching Tidal item on Apple Music : #{item} - #{term}")
      searched_item = apple_music_search_catalog(term: term, country_code: self.apple_music_search_country_code)

      # add the song
      if searched_item["results"].empty? or searched_item["results"]["songs"].empty?
        log.warn("Tidal item not found on Apple Music, review manually : #{item}")
        not_found_items.push({playlist: apple_playlist["attributes"]["name"], item: item})
      else

        song_id = searched_item["results"]["songs"]["data"][0]["id"]

        # only add missing songs
        unless hash_apple_music_playlist_songs.key? song_id
          result_add = apple_music_add_track_playlist(apple_playlist["id"], "songs", searched_item["results"]["songs"]["data"][0]["id"])
          log.info("Track added to '#{apple_playlist["attributes"]["name"]}' result : ''#{result_add}' #{searched_item}")
        end

        if rate_like
          log.info("Rating like ##{song_id}")
          apple_music_put_rating_entity(song_id, "songs")
        end

        if add_to_library
          log.info("Adding to library ##{song_id}")
          apple_music_add_entities_to_library(song_id, "songs")
        end

      end
    end
    return Array.new(not_found_items.size) { not_found_items.pop }
  end

  def tidal_get_entity_v1(entity = 'albums')
    offset = 0
    step = 100
    items = []
    loop do
      params = { limit: step, offset: offset, order: 'DATE', orderDirection: 'DESC',
                 countryCode: tidal_country_code }
      url = "#{self.tidal_api_url}/v1/users/#{self.tidal_user['uid']}/favorites/#{entity}"
      log.info("GET #{url} - #{params}")
      tidal_response = HTTParty
                         .get(url,
                              query: params,
                              headers: { 'Authorization' => "Bearer #{tidal_bearer_token}" })

      unless tidal_response.success?
        err = "An error occurred with the request: #{tidal_response.request.last_uri} (http_code=#{tidal_response.code}) #{tidal_response}"
        log.error(err)
        raise StandardError, err
      end

      break if tidal_response.parsed_response['items'].empty?

      offset += step
      items += tidal_response.parsed_response['items']
    end
    items
  end

  def tidal_get_entity_items_v1(id, entity = 'playlists')
    offset = 0
    step = 100
    items = []
    loop do
      params = { limit: step, offset: offset, order: 'DATE', orderDirection: 'DESC',
                 countryCode: tidal_country_code }
      url = "#{self.tidal_api_url}/v1/#{entity}/#{id}/items"
      log.info("GET #{url} - #{params}")
      tidal_response = HTTParty
                         .get(url,
                              query: params,
                              headers: { 'Authorization' => "Bearer #{tidal_bearer_token}" })

      unless tidal_response.success?
        err = "An error occurred with the request: #{tidal_response.request.last_uri} (http_code=#{tidal_response.code}) #{tidal_response}"
        log.error(err)
        raise StandardError, err
      end

      break if tidal_response.parsed_response['items'].empty?

      offset += step
      items += tidal_response.parsed_response['items']
    end
    items
  end

  def tidal_get_my_collection_playlists_v2
    cursor = nil
    step = 50
    items = []
    loop do
      params = { limit: step, cursor: cursor, order: 'DATE', orderDirection: 'DESC',
                 countryCode: tidal_country_code, includeOnly: "PLAYLIST" }
      url = "#{self.tidal_api_listen_url}/v2/my-collection/playlists/folders/flattened"
      log.info("GET #{url} - #{params}")
      tidal_response = HTTParty
                         .get(url,
                              query: params,
                              headers: { 'Authorization' => "Bearer #{tidal_bearer_token}" })

      unless tidal_response.success?
        err = "An error occurred with the request: #{tidal_response.request.last_uri} (http_code=#{tidal_response.code}) #{tidal_response}"
        log.error(err)
        raise StandardError, err
      end

      items += tidal_response.parsed_response['items']

      cursor = tidal_response.parsed_response['cursor']
      break if cursor.nil?
    end
    items
  end

  def tidal_auth
    @tidal_user = JWT.decode(self.tidal_bearer_token, nil, false)[0]
    log.info("Tidal User: #{self.tidal_user}")
  end

  def apple_music_add_entities_to_library(ids, entity = 'songs')
    url = "#{self.apple_music_api_url}/v1/me/library"
    if ids.kind_of? Array
      ids = ids.join(',')
    end

    query = {"ids[#{entity}]" => ids}
    log.info("POST #{url} - #{query}")
    apple_response = HTTParty
                       .post(url,
                             query: query,
                             headers: self.apple_music_headers)

    unless apple_response.success?
      err = "An error occurred with the request: #{apple_response.request.last_uri} (http_code=#{apple_response.code}) #{apple_response}"
      log.error(err)
      raise StandardError, err
    end

    return apple_response.parsed_response
  end

  def apple_music_remove_entity_from_library(id, entity = 'songs')
    url = "#{self.apple_music_api_url}/v1/me/library/#{entity}/#{id}"
    log.info("DELETE #{url}")
    apple_response = HTTParty
                       .delete(url,
                               headers: self.apple_music_headers)

    unless apple_response.success?
      err = "An error occurred with the request: #{apple_response.request.last_uri} (http_code=#{apple_response.code}) #{apple_response}"
      if apple_response.code == 500
        log.warn("Retrying in 1s: #{err}")
        sleep(1)
        return  apple_music_remove_entity_from_library(id, entity)
      end
      log.error(err)
      raise StandardError, err
    end

    return apple_response.parsed_response
  end

  def apple_music_put_rating_entity(id, entity = 'songs', like = true)
    url = "#{self.apple_music_api_url}/v1/me/ratings/#{entity}/#{id}"
    query = {}
    body = {type: "rating", attributes: {value: like ? 1 : -1}}
    if like
      log.info("PUT #{url} - #{query} - #{body}")
      apple_response = HTTParty
                         .put(url,
                              body: body.to_json,
                              query: query,
                              headers: self.apple_music_headers)
    else
      # remove the rating, instead of unlinking
      log.info("DELETE #{url} - #{query}")
      apple_response = HTTParty
                         .delete(url,
                                 headers:self.apple_music_headers)
    end


    unless apple_response.success?
      err = "An error occurred with the request: #{apple_response.request.last_uri} (http_code=#{apple_response.code}) #{apple_response}"
      log.error(err)
      raise StandardError, err
    end

    return apple_response.parsed_response
  end

  def apple_music_delete_library_entity(id, entity = 'songs')
    url = "#{self.apple_music_api_url}/v1/me/library/#{entity}/#{id}"
    log.info("DELETE #{url}")
    apple_response = HTTParty
                       .delete(url,
                               headers: self.apple_music_headers)

    unless apple_response.success?
      err = "An error occurred with the request: #{apple_response.request.last_uri} (http_code=#{apple_response.code}) #{apple_response}"
      log.error(err)
      raise StandardError, err
    end

    return apple_response.parsed_response
  end

  def apple_music_get_library_entity(id, entity = 'songs')
    url = "#{self.apple_music_api_url}/v1/me/library/#{entity}/#{id}"
    log.info("GET #{url}")
    apple_response = HTTParty
                       .get(url,
                            headers: self.apple_music_headers)

    unless apple_response.success?
      err = "An error occurred with the request: #{apple_response.request.last_uri} (http_code=#{apple_response.code}) #{apple_response}"
      log.error(err)
      raise StandardError, err
    end

    return apple_response.parsed_response
  end

  def apple_music_search_catalog(term:, country_code:, limit: 1, types: ['songs'])
    params = {limit: limit, term: term, types: types.join(', ') }
    url = "#{self.apple_music_api_url}/v1/catalog/#{country_code}/search"
    log.info("GET #{url} - #{params}")
    apple_response = HTTParty
                       .get(url,
                            query: params,
                            headers: self.apple_music_headers)

    unless apple_response.success?
      err = "An error occurred with the request: #{apple_response.request.last_uri} (http_code=#{apple_response.code}) #{apple_response}"
      if apple_response.code == 500
        log.warn("Retrying in 1s: #{err}")
        sleep(1)
        return  apple_music_search_catalog(term: term, country_code: country_code, limit: limit, types: types)
      end
      log.error(err)
      raise StandardError, err
    end

    return apple_response
  end

  def apple_music_get_playlist_tracks(id)
    offset = 0
    items = []
    step = 50

    loop do
      params = {offset: offset, limit: step}
      url = "#{self.apple_music_api_url}/v1/me/library/playlists/#{id}/tracks"
      log.info("GET #{url} - #{params}")
      apple_response = HTTParty
                         .get(url,
                              query: params,
                              headers: self.apple_music_headers)

      unless apple_response.success?
        if apple_response.code == 404
          return items
        end
        err = "An error occurred with the request: #{apple_response.request.last_uri} (http_code=#{apple_response.code}) #{apple_response}"
        log.error(err)
        raise StandardError, err
      end

      break if apple_response.parsed_response['data'].empty?

      items += apple_response.parsed_response['data']
      offset += step
    end
    items
  end

  def apple_music_get_library_entities(entity = 'songs')
    offset = 0
    step = 100
    items = []


    loop do
      params = {limit: step, offset: offset}
      url = "#{self.apple_music_api_url}/v1/me/library/#{entity}"
      log.info("GET #{url} - #{params}")
      apple_response = HTTParty
                         .get(url,
                              query: params,
                              headers: self.apple_music_headers)

      unless apple_response.success?
        err = "An error occurred with the request: #{apple_response.request.last_uri} (http_code=#{apple_response.code}) #{apple_response}"
        log.error(err)
        raise StandardError, err
      end

      break if apple_response.parsed_response['data'].empty?

      offset += step
      items += apple_response.parsed_response['data']
    end
    items
  end

  def apple_music_post_library_entity(entity = 'songs', attributes = {})
    params = {}
    url = "#{self.apple_music_api_url}/v1/me/library/#{entity}"
    log.info("POST #{url} - #{params} : #{attributes}")
    apple_response = HTTParty
                       .post(url,
                             query: params,
                             headers: self.apple_music_headers,
                             body: {attributes: attributes}.to_json
                       )

    unless apple_response.success?
      err = "An error occurred with the request: #{apple_response.request.last_uri} (http_code=#{apple_response.code}) #{apple_response}"
      log.error(err)
      raise StandardError, err
    end

    return  apple_response.parsed_response
  end

  def apple_music_add_track_playlist(playlist_id, item_type, item_id)
    params = {}
    url = "#{self.apple_music_api_url}/v1/me/library/playlists/#{playlist_id}/tracks"
    body = {data: [{id: item_id, type: item_type}]}
    log.info("POST #{url} - #{params} : #{body}")
    apple_response = HTTParty
                       .post(url,
                             query: params,
                             headers: self.apple_music_headers,
                             body: body.to_json
                       )

    unless apple_response.success?
      err = "An error occurred with the request: #{apple_response.request.last_uri} (http_code=#{apple_response.code}) #{apple_response}"
      if apple_response.code == 500
        log.warn("Retrying in 1s: #{err}")
        sleep(1)
        return apple_music_add_track_playlist(playlist_id, item_type, item_id)
      end
      log.error(err)
      raise StandardError, err
    end

    return  apple_response.parsed_response
  end

  attr_reader :apple_music_headers, :apple_music_user, :log, :tidal_user

  def apple_music_auth
    @apple_music_user = JWT.decode(apple_music_bearer_token, nil, false)[0]
    log.info("Apple Music User: #{self.apple_music_user}")

    @apple_music_headers = {
      "Authorization": "Bearer #{self.apple_music_bearer_token}",
      "Media-User-Token": self.apple_music_music_token.to_s,
      "User-Agent": 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:102.0) Gecko/20100101 Firefox/102.0',
      "Accept": '*/*', "Accept-Language": 'en-US,en;q=0.5', "Accept-Encoding": 'gzip, deflate',
      "Referer": 'https://music.apple.com/', "Origin": 'https://music.apple.com',
      "Sec-Fetch-Dest": 'empty', "Sec-Fetch-Mode": 'cors', "Sec-Fetch-Site": 'same-site', "Te": 'trailers'
    }
  end

end
