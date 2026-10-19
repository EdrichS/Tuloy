# Tuloy from Terminal. Needs Xcode (or its command line tools), nothing else.
#
#   make test      run the tests
#   make app       build build/Tuloy.app
#   make run       build it and start it
#   make demo      build it and start it with made-up data (no pings, none of your settings)
#   make install   build it, copy it to /Applications and start it (needed for launch at login)
#   make icon      redraw the app icon (scripts/make-icon.swift) into Support/AppIcon.icns

.PHONY: test app run demo install icon clean

test:
	swift test

app:
	./scripts/make-app.sh

run: app
	open build/Tuloy.app

demo: app
	open -n build/Tuloy.app --args --demo

# Also how you update: it quits the copy that's running, swaps it, and starts the new one.
install: app
	-@osascript -e 'tell application id "com.edrichsilva.tuloy" to quit' 2>/dev/null; sleep 1
	rm -rf /Applications/Tuloy.app
	cp -R build/Tuloy.app /Applications/Tuloy.app
	open /Applications/Tuloy.app
	@echo "Installed and started. Look for Tuloy in your menu bar."

icon:
	swift scripts/make-icon.swift Support/AppIcon.icns

clean:
	rm -rf .build build
