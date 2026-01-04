package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"

savefile_save :: proc(save_data: Save_Data) -> (success: bool) {
	options := json.Marshal_Options {
		spec = .SJSON,
	}
	data, err := json.marshal(save_data, options, context.temp_allocator)

	if err == nil {
		path := fmt.tprintf("saves/%d.json", save_data.slot)
		success = os.write_entire_file(path, data)
	}

	return
}

savefile_load :: proc(path: string) -> (save_data: Save_Data, ok: bool) {
	data := os.read_entire_file(path) or_return

	if json.unmarshal(data, &save_data, .SJSON) == nil {
		ok = true
	}

	return
}

save_data_update :: proc(gs: ^Game_State) {
	gs.save_data.location = gs.level.name

	time_since_update := time.diff(gs.last_update_time, time.now())
	gs.save_data.seconds_played += time.duration_seconds(time_since_update)
	gs.last_update_time = time.now()

	if !slice.contains(gs.save_data.visited_level_ids[:], gs.level.id) {
		append(&gs.save_data.visited_level_ids, gs.level.id)
	}
}
