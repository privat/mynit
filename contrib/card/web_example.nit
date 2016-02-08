# Simple sample code to show how to use `web_ui`
module web_example

# Because we need it
import web_ui

# Import you game logic
import domain

# The main view code is in a subclass of PlayerView
class MyPlayerView
	super PlayerView

	# Associate a player view and a game logic player (from domain)
	var player = new GameLogicPlayer

	# This one is run to render the player HTML
	redef fun do_render
	do
		# Use game logic information to show things and things to do for the current player.
		#
		# Just generate some nice (or not nice) HTML with the content of the player's screen.
		#
		# For controls, you can add:
		#
		# a checkbox with
		#
		#     body += add_entry(entry, text)
		#
		# a button with
		#
		#     body += add_button(entry, text)
		#
		# of a free-style link with
		#
		#     if is_passive then
		#         # opponent's turn
		#         body += "<span>text</span>"
		#     else
		#         # player's turn
		#         body += "<a href='{href_to(entry)}'>text</a>"
		#     end
		#
		# where `entry` is whatever you want associated to the control.
		# You can use some game logic objects or strings for instance.

		var body = ""
		if opponent == null then
			body += "<p>En attente d'un adversaire...</p>"
			return body
		end

		body += "<h2>Adversaire</h2>"
		body += "<p>Pioche: {nombre de carte pioche adverse}</p>"
		body += "<p>Main: {nombre de carte main adverse}</p>"
		body += "<p>Combatants:</p>"
		for e in combattants adverses do
			body += add_entry(e)
		end
		body += "<h2>Joueur</h2>"
		body += "<p>Combatants:</p>"
		for e in combattants do
			body += add_entry(e)
		end
		body += "<p>Main:</p>"
		for e in main do
			body += add_entry(e)
		end
		body += "<p>Pioche: {nombre de carte pioche}</p>"

		body += add_button("p", "Piocher")
		body += add_button("d", "Deployer")
		body += add_button("a", "Attaquer")
		body += add_button("e", "Enchanter")
		body += add_button("s", "Soigner")
		body += add_button("de", "Defausser")
		body += add_button("f", "Finir le tour")

		# Write the log
		body += "<ul>"
		for l in log do
			body += "<li>{l}</li>"
		end
		body += "</ul>"

		return body
	end

	redef fun on_action(entry)
	do
		# When a checkbox, a button or a user-link is clicked,
		# this method is called where `entry` is the object associated to the control.
		#
		# Checkboxes are also called, however checkboxes are automatically remembered
		# and will accessible in the array `entities` on a future on_action.
		#
		# The point of this method is to update the view and the game model.
		#
		# You can read:
		#
		# * `entry` that contain the object given to the control.
		# * `entries` that contains all the selected objects.
		# * `player` and other new attributes that is related to your game logic.
		#
		# You can mutate:
		#
		# * `alert = "text"` to prepare some error message
		# * `log.add "text"` to display some information for the player
		# * `opponent.log.add "text"` to display some information for the opponent
		# * `opponent.dirty = true` to force a refresh of the opponent screen
		# * `is_passive` to control turns
		# * `player` and other new attributes that is related to your game logic.

		# Draw cards
		if action == "p" then
			some code

			if cannot draw then
				alert = "Cannot draw"
				return
			end

			some more code

			log.add "Vous piochez {xxx} cartes"
			opponent.log.add "L'adversaire pioche {xxx} cartes"
			opponent.dirty = true
		end

		# End of turn
		if action == "f" then
			is_passive = true
			opponent.is_passive = false
			opponent.dirty = true
		end
	end

end


# To connect the player code to the server,
# we need a specific game corn that does the dirty job and associate players
class MyGameCorn
	super GameCorn

	# The only need is to explain how to make players
	redef fun new_player(opponent) do return new MyPlayerView(opponent)
end

# Then create a small standalone nitcorn server:

var iface = "localhost:8080"
var vh = new VirtualHost(iface)

var action = new MyGameCorn
vh.routes.add new Route(null, action)

var fac = new HttpFactory.and_libevent
fac.config.virtual_hosts.add vh

print "Launching server on http://{iface}/"
fac.run
