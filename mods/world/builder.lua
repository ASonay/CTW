local conf_path = minetest.get_worldpath() .. "/world.conf"
if file_exists(conf_path) then
	world.load_locations(conf_path)
else
	minetest.log("error", "Map configuration for this world not found")
end

local mts_path = minetest.get_worldpath() .. "/world.mts"

minetest.register_on_shutdown(function()
	world.save_locations(conf_path)
end)

local teamnames = { "red", "blue", "green", "yellow" }
for _, tname in pairs(teamnames) do
	minetest.register_node(":palettes:palette_" .. tname, {
		description = tname .. " palette",
		drawtype = "nodebox",
		paramtype = "light",
		tiles = {
			"default_wood.png^[colorize:" .. tname .. ":0.1",
		},
		node_box = {
			type = "fixed",
			fixed = {
				{-0.5, -0.5, -0.5, 0.5, -0.375, 0.5},
			}
		},
		after_place_node = function(pos)
			minetest.get_meta(pos):set_string("infotext", minetest.pos_to_string(pos))
		end,
	})
end

minetest.register_node(":team_billboard:bb", {
	description = "Team Billboard",
	drawtype = "signlike",
	visual_scale = 2.0,
	tiles = { "wool_black.png" },
	inventory_image = "wool_black.png",
	paramtype = "light",
	paramtype2 = "wallmounted",
	sunlight_propagates = true,
	walkable = false,
	light_source = 1, -- reflecting a bit of light might be expected
	selection_box = { type = "wallmounted" },
	groups = {attached_node=1},
	legacy_wallmounted = true,
})

local function pos_to_string(pos)
	return ("%d,%d,%d"):format(pos.x, pos.y, pos.z)
end

local HELP = ([[
Click 'set' to set positions to the current position.
Click 'update' to create or update a location with the given location name.
Areas are defined using locations x_1 and x_, where x is the area name.
Click 'export' to create world.conf and world.mts at world/exports/.
]]):trim()


local function buildLocationList()
	local location_list = {}
	for key, value in pairs(world.get_all_locations()) do
		location_list[#location_list + 1] = { name = key, pos = value }
	end
	table.sort(location_list, function(a, b)
		return a.name < b.name
	end)
	return location_list
end

local function formatList(list)
	for i=1, #list do
		list[i] = minetest.formspec_escape(("%s = %s"):format(list[i].name,  pos_to_string(list[i].pos)))
	end
	return table.concat(list, ",")
end


sfinv.register_page("world:builder", {
	title = "World Meta",
	get = function(self, player, context)
		local area = world.get_area("world") or { from = vector.new(), to = vector.new() }
		context.location_name = context.location_name or "world_1"

		local location_list = buildLocationList()
		local location_selection = ""
		for i=1, #location_list do
			if location_list[i].name == context.location_name then
				location_selection = tostring(i)
				break
			end
		end

		local fs = {
			"real_coordinates[true]",
			"container[0.375,0.375]",
			"field[0,0.3;3.75,0.8;from;From;", pos_to_string(area.from), "]",
			"button[3.75,0.3;1,0.8;set_from;Set]",
			"field[5,0.3;3.75,0.8;to;To;", pos_to_string(area.to), "]",
			"button[8.75,0.3;1,0.8;set_to;Set]",
			"container_end[]",

			"container[0.375,2.225]",
			"box[-0.375,-0.375;10.375,6;#666666cc]",
			"vertlabel[-0.2,1.2;LOCATIONS]",
			"textlist[0,0;9.625,4;locations;", formatList(location_list), ";", location_selection, "]",
			"container[0,4.5]",
			"field[0,0;3.25,0.8;location_name;Name;", context.location_name, "]",
			"field[3.5,0;2.75,0.8;location_pos;Position;", pos_to_string(context.location_pos or vector.new()), "]",
			"button[6.25,0;1,0.8;location_set;Set]",
			"button[7.5,0;2,0.8;location_update;Update]",
			"container_end[]",
			"container_end[]",

			"container[0.375,8.225]",
			"textarea[0,0;9.625,2;;;", minetest.formspec_escape(HELP), "]",
			"container_end[]",

			"button[3.75,9.6;3,0.8;export;Export]",
		}

		return sfinv.make_formspec(player, context,
				table.concat(fs, ""), false)
	end,

	on_player_receive_fields = function(self, player, context, fields)
		if fields.from then
			local pos = minetest.string_to_pos(fields.from)
			world.set_location("world_1", pos)
		end

		if fields.to then
			local pos = minetest.string_to_pos(fields.to)
			world.set_location("world_2", pos)
		end

		if fields.set_from then
			world.set_location("world_1", player:get_pos())
		elseif fields.set_to then
			world.set_location("world_2", player:get_pos())
		end

		context.location_name = fields.location_name or context.location_name

		if fields.location_pos then
			context.location_pos = minetest.string_to_pos(fields.location_pos)
		end

		if fields.locations then
			local evt = minetest.explode_textlist_event(fields.locations)
			if evt.type == "CHG" then
				local list = buildLocationList()
				if evt.index > 0 and evt.index <= #list then
					context.location_name = list[evt.index].name
					context.location_pos = list[evt.index].pos
				end
			end
		elseif fields.location_set then
			context.location_pos = player:get_pos()
		elseif fields.location_update then
			world.set_location(context.location_name, context.location_pos)
		elseif fields.export then
			local area = world.get_area("world")
			if area then
				if file_exists(mts_path) then
					os.remove(mts_path)
				end

				area.from, area.to = vector.sort(area.from, area.to)
				world.set_location("world_1", area.from)
				world.set_location("world_2", area.to)
				world.save_locations(conf_path)

				player:set_inventory_formspec("size[3,2]label[0.1,0.1;Exporting, please wait...]")
				local pname = player:get_player_name()

				world.emerge_with_callbacks(area.from, area.to, function()
					minetest.create_schematic(area.from, area.to, nil, mts_path, nil)
					local player = minetest.get_player_by_name(pname)
					if player then
						sfinv.set_player_inventory_formspec(player, context)
					end
					minetest.chat_send_all("Export done!")
				end)
				return
			end
		end

		sfinv.set_player_inventory_formspec(player, context)
		world.save_locations(conf_path)
	end,
})
