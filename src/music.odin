package ld

import "core:log"
import "core:mem"
import "core:strings"
import "core:time"
import "lib:ve"
import ma "vendor:miniaudio"

// Core

Sound :: struct {
	source: ^ma.sound,
}

@(private)
ctx: struct {
	e: ma.engine,
}

init_music :: proc() {
	result := ma.engine_init(nil, &ctx.e)
	if result != .SUCCESS {
		log.panic("Miniaudio initialization failed. Result:", result)
	}
}

destroy_music :: proc() {
	ma.engine_uninit(&ctx.e)
}

sound_play :: proc(path: string, loc := #caller_location) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	result := ma.engine_play_sound(&ctx.e, cpath, nil)
	if result != .SUCCESS {
		log.panic("Miniaudio soudn loading failed. Result:", result, location = loc)
	}
}

load_sound :: proc(path: string, loc := #caller_location) -> Sound {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)

	sound := new(ma.sound)
	result := ma.sound_init_from_file(&ctx.e, cpath, {}, nil, nil, sound)
	if result != .SUCCESS {
		log.panic("Miniaudio soudn loading failed. Result:", result, location = loc)
	}

	return Sound{source = sound}
}

destroy_sound :: proc(s: ^Sound) {
	ma.sound_uninit(s.source)
	free(s.source)
}

sound_clone :: proc(s: Sound) -> Sound {
	clone: ^ma.sound = new(ma.sound)
	ma.sound_init_copy(&ctx.e, s.source, {}, nil, clone)
	return Sound{source = clone}
}

sound_is_initialized :: proc(s: Sound) -> bool {
	return s.source != nil
}

sound_is_playing :: proc(s: Sound) -> bool {
	return cast(bool)ma.sound_is_playing(s.source)
}

sound_set_looping :: proc(s: ^Sound, is_looping: bool) {
	ma.sound_set_looping(s.source, cast(b32)is_looping)
}

sound_is_looping :: proc(s: ^Sound) -> bool {
	return cast(bool)ma.sound_is_looping(s.source)
}

sound_set_volume :: proc(s: ^Sound, volume: f32) {
	ma.sound_set_volume(s.source, volume)
}

sound_get_volume :: proc(s: Sound) -> f32 {
	return ma.sound_get_volume(s.source)
}

sound_start :: proc(s: ^Sound) {
	ma.sound_start(s.source)
}

sound_rewind :: proc(s: ^Sound) {
	ma.sound_seek_to_pcm_frame(s.source, 0)
}

sound_restart :: proc(s: ^Sound) {
	sound_rewind(s)
	sound_start(s)
}

sound_stop :: proc(s: ^Sound) {
	ma.sound_stop(s.source)
}

// Helpers

Background_Music :: struct {
	current_sound: Sound,
}

@(private = "file")
bg: Background_Music

load_bg_music :: proc(path: string) -> Sound {
	s := load_sound(path)
	ma.sound_set_fade_start_in_milliseconds(
		s.source,
		0.01,
		0.5,
		cast(u64)time.duration_microseconds(time.Second * 2),
		0,
	)
	return s
}

bg_start :: proc(sound: Sound) {
	if sound_is_initialized(bg.current_sound) {
		sound_stop(&bg.current_sound)
	}

	bg.current_sound = sound
	sound_start(&bg.current_sound)
}

Multiple_Sound :: struct {
	sounds: []Sound,
}

load_multiple_sound :: proc(path: string, max: int = 5) -> Multiple_Sound {
	sounds := make([]Sound, max)
	sounds[0] = load_sound(path)

	for i in 1 ..< max {
		sounds[i] = sound_clone(sounds[0])
	}

	return Multiple_Sound{sounds = sounds}
}

destroy_multiple_sound :: proc(ms: ^Multiple_Sound) {
	for &s in ms.sounds {
		destroy_sound(&s)
	}
}

multiple_sound_play :: proc(ms: ^Multiple_Sound) {
	for &s in ms.sounds {
		if sound_is_playing(s) do continue
		sound_start(&s)
		return
	}
}
