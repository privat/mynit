# Basic HTML controller for turn-based duel games.
#
# The framework offers:
#
# * complete independence of the game logic
# * automatic pairing of players
# * multiple games hosting
# * two simple UI controls: checkboxes and buttons.
#   but you can easily define you own.
# * association of arbitrary objects to controls.
#   they are used when the control is activated.
# * automatic update of the opponent view.
# * some built-in stuff, like logging or alert messages.
#
# To use the framework:
#
# * subclass `PlayerView` and implements `on_render` and `on_action`.
# * subclass `GameCorn` and implements `new_player` to return your special class.
# * use your special GameCorn as an action in a nitcorn server.
#
# See `web_example.nit` for a simple example.
#
# Note that the whole thing is quite basic since each action causes a whole refresh
# on the client side for both players.
module web_ui

import nitcorn

# The state of the HTML display for a player.
#
# This class only contains information related to the displaying of the player.
#
# Game logic is connected through two main methods `on_render` to render the
# HTML body of the player content (with game information and controls),
# and `on_action` to answer the action of the player when a control is clicked.
#
# Both these two methods are linked since a control is mainly a special engineered HTML link.
# The view engine permits to associate arbitrary objects to links that will be retrieved
# when `on_action` is executed.
#
# To do that, two helper methods are provided: `add_entity` and `add_button`.
# An additional low-level `href_for` is also provided.
#
# You can pass high-level game objects, strings or whatever on these methods.
# The mapping is done internally without memory leaks.
class PlayerView
	# The opponent view, if any.
	#
	# Since we consider only duels, the point here is
	# to allow to force-refresh the opponent's window.
	#
	# opponents are automatically paired internally.
	var opponent: nullable PlayerView

	# Flag to indicate that the UI of the player is locked
	# Usually it means that the opponent is active.
	#
	# When true, all controls from `add_entry` and `add_button` are made inactive (non-clickable)
	#
	# MODIFY_IT: in `on_action` for both the player and opponent
	var is_passive = false is writable

	# List of recent messages (in HTML)
	#
	# Since there is no animation or whatever, use this to describe
	# what happens to the human player and to its human opponent.
	#
	# MODIFY_IT: in `on_action` for both the player and opponent
	var log = new Array[String]

	# An imperative message to be shown to the human.
	#
	# Use it mainly for error messages.
	#
	# MODIFY_IT: in `on_action` for the player
	var alert: nullable String = null is writable

	# Should the page be reloaded?
	#
	# Mainly it is because the opponent did something so we need to show it.
	#
	# MODIFY_IT: in `on_action` for the opponent
	var dirty = false is writable

	# List of selected entries, as selected with `add_entry`
	#
	# Entries can be whatever you want.
	#
	# If an entry is selected but not re-added with `add_entry` on `on_render`,
	# then the entry is automatically unselected (to avoid unaccessible elements in the list)
	#
	# MODIFY_IT: while you can modify it, it is automatically managed.
	#
	# See: `add_entry` and `href_for` (`remember` parameter)
	var entries = new Array[Object]

	# Used internally to mark entries that are selected and need to remain selected.
	# Such entries will be remembered, others will be forgotten.
	private var keep_entries = new Array[Object]

	# List of the received GET data.
	# For debugging only
	private var get: nullable Map[String, String] = null

	# List of linked entries.
	#
	# See `href_for` and `on_action`.
	private var list = new HashMap[String, Object]


	# Hook to handle the input of a player
	fun on_action(entry: Object) is abstract

	# Hook to handle the full HTML rendering of a player page
	fun do_render: String is abstract


	# Return selectable link (pseudo-checkbox) with a text associated to an entry.
	#
	# When clicked, the `on_action` with the corresponding `entry` will be called.
	# Moreover, the entity will be remembered and available in `player.entries`
	#
	# If no text is provided, the `entry.to_s` is used.
	#
	# NOTE: to use during the `on_render` phase only.
	fun add_entry(entry: Object, text: nullable String): String
	do
		if text == null then text = entry.to_s.html_escape
		if is_passive then
			return "<span>☐{text}</span><br>"
		end

		var href = href_for(entry, true)
		if entries.has(entry) then
			return """<a href="{{{href}}}">☑<b>{{{text}}}</b></a><br>"""
		else
			return """<a href="{{{href}}}">☐{{{text}}}</a><br>"""
		end
	end

	# Returns a button with a text associated to an entry.
	#
	# When clicked, the `on_action` with the corresponding `entry` will be called.
	#
	# Note that this is just a fancy link.
	# If the player is passive, a grayed disabled button is displayed instead.
	#
	# If no text is provided, the `entry.to_s` is used.
	#
	# NOTE: to use during the `on_render` phase only.
	fun add_button(entry: Object, text: nullable String): String
	do
		if text == null then text = entry.to_s.html_escape
		if is_passive then
			return """<span class="btn btn-default disabled">{{{text}}}</span> """
		end
		var href = href_for(entry)
		return """<a href="{{{href}}}" class="btn btn-default">{{{text}}}</a> """
	end

	# Low level object-passing through links.
	#
	# This returns a target HTML reference intended to use
	# in the `href` of a `<a>` tag for instance.
	#
	# When followed, the `on_action` with the corresponding `entry` will be called.
	#
	# This method is used by `add_entry` and `add_button` but can be used to provide
	# other kind of controls.
	#
	# If `remember` is true, the entity will be automatically selected/unselected
	# in the `player.entity` array when clicked.
	#
	# NOTE: to use during the `on_render` phase only.
	fun href_for(entry: Object, remember: nullable Bool): String
	do
		var id = list.length
		var name = "entry_{id}"
		list[name] = entry

		if remember == true then
			if entries.has(entry) then
				keep_entries.add entry
				return "do?entry={name}&s=f"
			else
				return "do?entry={name}&s=t"
			end
		end
		return "do?entry={name}"
	end
end

redef class Session
	# To simplify, a nitcorn session is associated with a player
	var player: PlayerView is noautoinit
end

# The main game controller
#
# Handles HTTP game requests and generates HTML.
# However, the main job is delegated to `PlayerView`.
#
# Implements `new_player` to return a specific PlayerView object.
abstract class GameCorn
	super Action

	# Hook to handle the creation of a new player.
	#
	# If the player waits for an opponent, null is given.
	# If a waiting player exists, then the two will be paired.
	fun new_player(opponent: nullable PlayerView): PlayerView is abstract

	# A player without an opponent yet
	#
	# This is used internally to know which player, if any, does need an opponent.
	var free_player: nullable PlayerView

	# Creates (and setup) a new player.
	#
	# CALLS `new_player`
	fun setup_player: PlayerView
	do
		var free = free_player
		if free == null then
			free = new_player(null)
			print "new free player {free}"
			free_player = free
			free.is_passive = true
			return free
		else
			var res = new_player(free)
			print "new player {res} <-> {free}"
			free.opponent = res
			free.dirty = true
			free_player = null
			return res
		end
	end

	# Set to true to display additional debug information
	var debug = false is writable

	redef fun answer(request, url) do
		# Get the post things
		var get = request.get_args

		# Get the session, if any.
		var session = request.session

		# Prepare the response
		var rsp = new HttpResponse(200)
		rsp.header["Content-Type"] = "text/html; charset=\"UTF-8\""
		rsp.session = session
		var body = rsp.body

		# Special dirty/force-reload case
		if get.has_key("ping") then
			if session == null then return rsp
			var player = session.player
			
			if player.dirty then
				rsp.body = "true"
				player.dirty = false
			else
				rsp.body = "false"
			end
			return rsp
		end

		# New session implies new player
		if session == null then
			session = new Session
			session.player = setup_player
			rsp.session = session
		end

		# Ok, let's play!
		var player = session.player

		# Did the player do something?
		if not get.is_empty then
			player.get = get

			var action = get.get_or_null("entry")
			var sel = get.get_or_null("s")
			if action != null then
				var entry = player.list.get_or_null(action)
				if entry != null then
					if player.entries.has(entry) then
						player.entries.remove entry
					else if sel == "t" then
						player.entries.add entry
					end

					player.on_action(entry)
				end
			end

			# Post/Redirect/Get to prevent reload issues
			var response = new HttpResponse(303)
			response.header["Location"] = request.uri
			response.session = session
			return response
		end

		# Else, render the page
		body += """
<!DOCTYPE html>
<html>
<head>
	<link rel="stylesheet" href="http://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.min.css">
	<script src="https://ajax.googleapis.com/ajax/libs/jquery/2.1.1/jquery.min.js"></script>
	<script src="http://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/js/bootstrap.min.js"></script>
</head>
<body>
<div class="container">
"""

		# Prepare the content to be rendered
		player.list.clear
		player.keep_entries.clear

		# Render the content
		body += player.do_render

		# Activate the new entries
		var tmp = player.entries
		player.entries = player.keep_entries
		player.keep_entries = tmp

		if debug then
			body += "<p>URL: {request.url} vs {url}</p>"
			var pget = player.get
			if pget != null then body += "<p>GET: {pget.join(" * ", ": ")}</p>"
			body += "<p>LIST: {player.list.keys.join(", ")}</p>"
			body += "<p>SESS: {session.id_hash}</p>"
			body += "<p>PLAYER: {player.to_s.html_escape}</p>"
			body += "<p>OPPONENT: {(player.opponent or else "-").to_s.html_escape}</p>"
		end


		body += """
</div>

<script>

function try_refresh() {

$.get( "ajax/test.html", {ping: true}, function( data ) {
  if (data == "true") {
    location.reload(true);
  } else if (data == "false" ) {
    window.setTimeout(try_refresh, 100);
  } else {
    window.alert("Probleme de connexion avec le serveur :/");
  }
});


}
"""

var alert = player.alert
if alert != null then
	body += "window.alert(\"{alert}\");"
	player.alert = null
end

body += """

window.setTimeout(try_refresh, 100);
</script>

		
</body></html>"""

		rsp.body = body
		return rsp
	end
end
