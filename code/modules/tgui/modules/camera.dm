/datum/tgui_module/camera
	name = "Security Cameras"

	var/access_based = FALSE
	var/list/network = list()

	var/obj/machinery/camera/active_camera
	var/list/concurrent_users = list()

	// Stuff needed to render the map
	var/map_name
	var/const/default_map_size = 15
	var/obj/screen/map_view/cam_screen
	/// All the plane masters that need to be applied.
	var/list/cam_plane_masters
	var/obj/screen/background/cam_background
	var/obj/screen/background/cam_foreground
	var/obj/screen/skybox/local_skybox
	// Needed for moving camera support
	var/camera_diff_x = -1
	var/camera_diff_y = -1
	var/camera_diff_z = -1

/datum/tgui_module/camera/New(host, list/network_computer)
	. = ..()
	if(!LAZYLEN(network_computer))
		access_based = TRUE
	else
		network = network_computer
	map_name = "camera_console_[REF(src)]_map"
	// Initialize map objects
	cam_screen = new
	cam_screen.name = "screen"
	cam_screen.assigned_map = map_name
	cam_screen.del_on_map_removal = FALSE
	cam_screen.screen_loc = "[map_name]:1,1"
	cam_plane_masters = list()
	
	for(var/plane in subtypesof(/obj/screen/plane_master))
		var/obj/screen/instance = new plane()
		instance.assigned_map = map_name
		instance.del_on_map_removal = FALSE
		instance.screen_loc = "[map_name]:CENTER"
		cam_plane_masters += instance

	local_skybox = new()
	local_skybox.assigned_map = map_name
	local_skybox.del_on_map_removal = FALSE
	local_skybox.screen_loc = "[map_name]:CENTER,CENTER"
	cam_plane_masters += local_skybox

	cam_background = new
	cam_background.assigned_map = map_name
	cam_background.del_on_map_removal = FALSE

	var/mutable_appearance/scanlines = mutable_appearance('icons/effects/static.dmi', "scanlines")
	scanlines.alpha = 50
	scanlines.layer = FULLSCREEN_LAYER

	var/mutable_appearance/noise = mutable_appearance('icons/effects/static.dmi', "1 light")
	noise.layer = FULLSCREEN_LAYER

	cam_foreground = new
	cam_foreground.assigned_map = map_name
	cam_foreground.del_on_map_removal = FALSE
	cam_foreground.plane = PLANE_FULLSCREEN
	cam_foreground.add_overlay(scanlines)
	cam_foreground.add_overlay(noise)

/datum/tgui_module/camera/Destroy()
	qdel(cam_screen)
	QDEL_LIST(cam_plane_masters)
	qdel(cam_background)
	qdel(cam_foreground)
	return ..()

/datum/tgui_module/camera/tgui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/tgui_state/state = GLOB.tgui_default_state)
	// Update UI
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	// Show static if can't use the camera
	if(!active_camera?.can_use())
		show_camera_static()
	if(!ui)
		var/user_ref = REF(user)
		var/is_living = isliving(user)
		// Ghosts shouldn't count towards concurrent users, which produces
		// an audible terminal_on click.
		if(is_living)
			concurrent_users += user_ref
		// Turn on the console
		if(length(concurrent_users) == 1 && is_living)
			playsound(tgui_host(), 'sound/machines/terminal_on.ogg', 25, FALSE)
		// Register map objects
		user.client.register_map_obj(cam_screen)
		for(var/plane in cam_plane_masters)
			user.client.register_map_obj(plane)
		user.client.register_map_obj(cam_background)
		user.client.register_map_obj(cam_foreground)
		// Open UI
		ui = new(user, src, ui_key, "CameraConsole", name, 870, 708, master_ui, state)
		ui.open()

/datum/tgui_module/camera/tgui_data()
	var/list/data = list()
	data["activeCamera"] = null
	if(active_camera)
		differential_check()
		data["activeCamera"] = list(
			name = active_camera.c_tag,
			status = active_camera.status,
		)
	return data

/datum/tgui_module/camera/tgui_static_data(mob/user)
	var/list/data = list()
	data["mapRef"] = map_name
	var/list/cameras = get_available_cameras(user)
	data["cameras"] = list()
	for(var/i in cameras)
		var/obj/machinery/camera/C = cameras[i]
		data["cameras"] += list(list(
			name = C.c_tag,
		))
	return data

/datum/tgui_module/camera/tgui_act(action, params)
	if(..())
		return

	if(action == "switch_camera")
		var/c_tag = params["name"]
		var/list/cameras = get_available_cameras(usr)
		var/obj/machinery/camera/C = cameras[c_tag]
		active_camera = C
		playsound(tgui_host(), get_sfx("terminal_type"), 25, FALSE)

		reload_cameraview()

		return TRUE

/datum/tgui_module/camera/proc/differential_check()
	var/turf/T = get_turf(active_camera)
	if(T)
		var/new_x = T.x
		var/new_y = T.y
		var/new_z = T.z
		if((new_x != camera_diff_x) || (new_y != camera_diff_y) || (new_z != camera_diff_z))
			reload_cameraview()

/datum/tgui_module/camera/proc/reload_cameraview()
	// Show static if can't use the camera
	if(!active_camera?.can_use())
		show_camera_static()
		return TRUE

	var/turf/camTurf = get_turf(active_camera)

	camera_diff_x = camTurf.x
	camera_diff_y = camTurf.y
	camera_diff_z = camTurf.z

	var/list/visible_turfs = list()
	for(var/turf/T in (active_camera.isXRay() \
			? range(active_camera.view_range, camTurf) \
			: view(active_camera.view_range, camTurf)))
		visible_turfs += T

	var/list/bbox = get_bbox_of_atoms(visible_turfs)
	var/size_x = bbox[3] - bbox[1] + 1
	var/size_y = bbox[4] - bbox[2] + 1

	cam_screen.vis_contents = visible_turfs
	cam_background.icon_state = "clear"
	cam_background.fill_rect(1, 1, size_x, size_y)

	cam_foreground.fill_rect(1, 1, size_x, size_y)

	local_skybox.cut_overlays()
	local_skybox.add_overlay(SSskybox.get_skybox(get_z(camTurf)))
	local_skybox.scale_to_view(size_x)
	local_skybox.set_position("CENTER", "CENTER", (world.maxx>>1) - camTurf.x, (world.maxy>>1) - camTurf.y)

// Returns the list of cameras accessible from this computer
// This proc operates in two distinct ways depending on the context in which the module is created.
// It can either return a list of cameras sharing the same the internal `network` variable, or
// It can scan all station networks and determine what cameras to show based on the access of the user.
/datum/tgui_module/camera/proc/get_available_cameras(mob/user)
	var/list/all_networks = list()
	// Access Based
	if(access_based)
		for(var/network in using_map.station_networks)
			if(can_access_network(user, get_camera_access(network), 1))
				all_networks.Add(network)
		for(var/network in using_map.secondary_networks)
			if(can_access_network(user, get_camera_access(network), 0))
				all_networks.Add(network)
	// Network Based
	else
		all_networks = network.Copy()

	var/list/L = list()
	for(var/obj/machinery/camera/C in cameranet.cameras)
		L.Add(C)
	var/list/D = list()
	for(var/obj/machinery/camera/C in L)
		if(!C.network)
			stack_trace("Camera in a cameranet has no camera network")
			continue
		if(!(islist(C.network)))
			stack_trace("Camera in a cameranet has a non-list camera network")
			continue
		var/list/tempnetwork = C.network & all_networks
		if(tempnetwork.len)
			D["[C.c_tag]"] = C
	return D

/datum/tgui_module/camera/proc/can_access_network(mob/user, network_access, station_network = 0)
	// No access passed, or 0 which is considered no access requirement. Allow it.
	if(!network_access)
		return 1

	if(station_network)
		return check_access(user, network_access) || check_access(user, access_security) || check_access(user, access_heads)
	else
		return check_access(user, network_access)

/datum/tgui_module/camera/proc/show_camera_static()
	cam_screen.vis_contents.Cut()
	cam_background.icon_state = "scanline2"
	cam_background.fill_rect(1, 1, default_map_size, default_map_size)
	local_skybox.cut_overlays()

/datum/tgui_module/camera/tgui_close(mob/user)
	. = ..()
	var/user_ref = REF(user)
	var/is_living = isliving(user)
	// living creature or not, we remove you anyway.
	concurrent_users -= user_ref
	// Unregister map objects
	if(user.client)
		user.client.clear_map(map_name)
	// Turn off the console
	if(length(concurrent_users) == 0 && is_living)
		active_camera = null
		playsound(tgui_host(), 'sound/machines/terminal_off.ogg', 25, FALSE)