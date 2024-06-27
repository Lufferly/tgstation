/datum/traitor_objective_category/release_gas
	name = "Release Gas"
	objectives = list(
		/datum/traitor_objective/release_gas = 1
	)
	weight = OBJECTIVE_WEIGHT_UNLIKELY

/datum/traitor_objective/release_gas
	name = "Plant a gas releasing device and defend it until it finishes its operation" //Change this
	description = "Call in the device at %AREA1% or %AREA2% and activate it. It will begin to release dangerous gas in cycles, ensure it can finish all of its cycles."

	progression_minimum = 30 MINUTES
	progression_reward = list(10 MINUTES, 20 MINUTES)
	telecrystal_reward = list(2, 4)
	telecrystal_penalty = 2

	/// The areas that the gas leaker device can be called into
	var/list/area/chosen_areas = list()
	/// If we have already sent down the gas leaker device
	var/device_sent = FALSE
	/// If the gas leaker device has completed its operation
	var/device_completed = FALSE
	/// If the gas leaker device has been destroyed
	var/device_destroyed = FALSE

/datum/traitor_objective/release_gas/can_generate_objective(datum/mind/generating_for, list/possible_duplicates)
	if (length(possible_duplicates) > 0)
		return FALSE
	if (SStraitor.get_taken_count(/datum/traitor_objective/release_gas > 1))
		return FALSE
	return TRUE

/datum/traitor_objective/release_gas/generate_objective(datum/mind/generating_for, list/possible_duplicates)
	// Areas that are allowed to be one of the objective locations
	var/list/allowed_areas = typecacheof(list(
		/area/station/command/bridge,
		/area/station/engineering,
		/area/station/medical,
		/area/station/science,
		/area/station/security,
		/area/station/service,
	))
	// Add some specfic areas, but not their subtypes
	allowed_areas += list(
		/area/station/cargo/lobby,
		/area/station/cargo/storage,
		/area/station/commons/dorms,
		/area/station/commons/toilet,
	)
	// Areas that are not allowed to be one of the objective locations
	var/list/blocked_areas = typecacheof(list(
		/area/station/engineering/atmos, //The idea is that atmos engineers need to at least walk out their front door
		/area/station/engineering/supermatter,
		/area/station/medical/abandoned,
		/area/station/science/ordnance/bomb,
		/area/station/science/ordnance/burnchamber, //boring
		/area/station/science/ordnance/freezerchamber,
		/area/station/security/prison,
		/area/station/service/abandoned_gambling_den,
		/area/station/service/kitchen/abandoned,
		/area/station/service/library/abandoned,
	))

	// Choose the two areas the device can be brought into
	var/list/possible_areas = GLOB.the_station_areas.Copy()
	for (var/area/possible_area as anything in possible_areas)
		if(!is_type_in_typecache(possible_area, allowed_areas) || initial(possible_area.outdoors) || is_type_in_typecache(possible_area, blocked_areas))
			possible_areas -= possible_area
	for (var/i in 1 to 2)
		chosen_areas += pick_n_take(possible_areas)

	replace_in_name("%AREA1%", initial(chosen_areas[1].name))
	replace_in_name("%AREA2%", initial(chosen_areas[2].name))
	return TRUE

/datum/traitor_objective/release_gas/generate_ui_buttons(mob/user)
	var/list/buttons = list()
	if (!device_sent)
		buttons += add_ui_button("", "Pressing this will call down the gas releasing device if you are in one of the designated areas", "bomb", "gas_device")
	return buttons

/datum/traitor_objective/release_gas/ui_perform_action(mob/user, action)
	. = ..()
	switch(action)
		if ("gas_device")
			if (device_sent)
				return
			// Check that the player is in one of the chosen areas
			var/area/user_area = get_area(user)
			var/user_in_correct_area = FALSE
			for (var/area/chosen_area as anything in chosen_areas)
				if (user_area.type == chosen_area)
					user_in_correct_area = TRUE
			if (user_in_correct_area == FALSE)
				to_chat(user, span_warning("You must be in one of the designated areas to call the gas releasing device, current area:[user_area.name]"))
				return

			device_sent = TRUE
			var/obj/machinery/gas_leaker/gas_leaker = new /obj/machinery/gas_leaker(get_turf(user))
			AddComponent(/datum/component/traitor_objective_register, \
				gas_leaker, \
				succeed_signals = list(COMSIG_GAS_LEAKER_FINISHED))
			AddComponent(/datum/component/traitor_objective_register, \
				gas_leaker, \
				fail_signals = list(COMSIG_QDELETING, COMSIG_MACHINERY_BROKEN), \
				penalty = telecrystal_penalty)

/obj/machinery/gas_leaker
	name = "gas_leaker"
	icon = 'icons/obj/pipes_n_cables/atmos.dmi'
	icon_state = "siphon"
	density = TRUE
	max_integrity = 350
	integrity_failure = 0.1
	use_power = NO_POWER_USE
	armor_type = /datum/armor/gas_leaker

	/// If we have started our operation of opening and closing
	var/started_operation = FALSE
	/// If we are currently open and releasing gas
	var/releasing_gas = FALSE
	/// How many times we will release gas
	var/max_cycles = 5
	/// What cycle of releasing gas we are on
	var/current_cycle = 1
	/// How long between each cycle of releasing gas
	var/cycle_time = 15 SECONDS
	/// How many moles of gas we release on each cycle, not including the final cycle
	var/moles_per_cycle = 200
	/// How many moles of gas we release on the final cycle
	var/moles_final_cycle = 2000

/datum/armor/gas_leaker
	fire = 100 //Dont like the idea of its own fire breaking it

/obj/machinery/gas_leaker/update_icon_state()
	. = ..()
	if (started_operation == TRUE)
		icon_state = "siphon_1"
	else
		icon_state = "siphon"

/obj/machinery/gas_leaker/interact()
	if (started_operation == FALSE)
		started_operation = TRUE
		start_operation()
		update_icon_state()
	. = ..()

/// Start the process of opening and closing
/obj/machinery/gas_leaker/proc/start_operation()
	addtimer(CALLBACK(src, PROC_REF(do_cycle)), cycle_time)

/// Open and release some gas, then close. Set up the next cycle if we havent finished all our cycles
/obj/machinery/gas_leaker/proc/do_cycle()
	balloon_alert_to_viewers("Releasing Gas...")
	if (current_cycle == max_cycles) //If we are on the final cycle, release extra gas
		atmos_spawn_air("[GAS_PLASMA]=[moles_final_cycle]")
	else
		atmos_spawn_air("[GAS_PLASMA]=[moles_per_cycle]") //change this

	// Set up the next cycle, if we havent already done all of our cycles
	current_cycle += 1
	if (current_cycle > max_cycles)
		balloon_alert_to_viewers("Finished!")
		SEND_SIGNAL(src, COMSIG_GAS_LEAKER_FINISHED)
		return
	addtimer(CALLBACK(src, PROC_REF(do_cycle)), cycle_time)
