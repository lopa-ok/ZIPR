extends Node

var bg_music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var max_sfx_channels: int = 16

var sfx_cache: Dictionary = {}

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    
    bg_music_player = AudioStreamPlayer.new()
    bg_music_player.bus = "Music"
    add_child(bg_music_player)
    
    for i in range(max_sfx_channels):
        var p = AudioStreamPlayer.new()
        p.bus = "SFX"
        add_child(p)
        sfx_players.append(p)
    
    print("[SoundManager] Initialized with ", max_sfx_channels, " sfx channels.")

func play_music(stream_path: String, volume_db: float = 0.0, fade_time: float = 0.5) -> void:
    if stream_path == "" and bg_music_player.playing:
        _fade_out_music(fade_time)
        return

    var stream = load(stream_path)
    if not stream:
        print("[SoundManager] Failed to load music: ", stream_path)
        return
        
    if bg_music_player.stream == stream and bg_music_player.playing:
        return 
        
    if bg_music_player.playing:
        bg_music_player.stop()
        
    bg_music_player.stream = stream
    bg_music_player.volume_db = volume_db
    bg_music_player.play()

func stop_music(fade_time: float = 1.0) -> void:
    _fade_out_music(fade_time)

func play_sfx(stream_path: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
    var stream = _get_sfx_stream(stream_path)
    if not stream:
        return
        
    var player = _get_available_sfx_player()
    if player:
        player.stream = stream
        player.volume_db = volume_db
        player.pitch_scale = pitch_scale
        player.play()

func play_sfx_random_pitch(stream_path: String, volume_db: float = 0.0, min_pitch: float = 0.9, max_pitch: float = 1.1) -> void:
    play_sfx(stream_path, volume_db, randf_range(min_pitch, max_pitch))

func _get_sfx_stream(path: String) -> AudioStream:
    if sfx_cache.has(path):
        return sfx_cache[path]
    
    var stream = load(path)
    if stream:
        sfx_cache[path] = stream
    else:
        print("[SoundManager] Failed to load SFX: ", path)
    return stream

func _get_available_sfx_player() -> AudioStreamPlayer:
    for p in sfx_players:
        if not p.playing:
            return p
    return null

func _fade_out_music(duration: float) -> void:
    if duration <= 0.0:
        bg_music_player.stop()
        return
        
    var tween = create_tween()
    tween.tween_property(bg_music_player, "volume_db", -80.0, duration)
    tween.tween_callback(bg_music_player.stop)
    tween.tween_callback(func(): bg_music_player.volume_db = 0.0)
