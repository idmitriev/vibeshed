#!/bin/bash
# Vibeshed — make-testable.command
# Double-click this file in Finder to run it.
# It will:
#   1. Register Vibeshed with macOS LaunchServices (fixes computer-use discovery)
#   2. Add ctrl+shift+space as an alternative picker trigger in your config

set -e

echo "=== Vibeshed testability setup ==="
echo ""

# 1. Register with LaunchServices
echo "1. Registering Vibeshed with LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f /Applications/Vibeshed.app
echo "   Done."

# 2. Add ctrl+shift+space keybinding to config
CONFIG="$HOME/.config/vibeshed/config.yaml"

if [ ! -f "$CONFIG" ]; then
  echo "   Config file not found at $CONFIG — skipping keybinding patch."
else
  echo "2. Patching config to add ctrl+shift+space picker trigger..."
  python3 - <<'PYEOF'
import sys, os

config_path = os.path.expanduser("~/.config/vibeshed/config.yaml")
with open(config_path, "r") as f:
    content = f.read()

target = '  - combo: "capslock+space"\n    action: "app/togglePicker"'
addition = '\n  - combo: "ctrl+shift+space"\n    action: "app/togglePicker"'

if '"ctrl+shift+space"' in content:
    print("   ctrl+shift+space already present — skipping.")
elif target in content:
    content = content.replace(target, target + addition, 1)
    with open(config_path, "w") as f:
        f.write(content)
    print("   Added ctrl+shift+space binding.")
else:
    print("   Could not find expected keybinding block — skipping patch.")
    print("   Add this manually under the keybindings: section:")
    print('     - combo: "ctrl+shift+space"')
    print('       action: "app/togglePicker"')
PYEOF
fi

echo ""
echo "=== All done! ==="
echo ""
echo "Next steps:"
echo "  • Restart (or quit+relaunch) Vibeshed so it picks up the new config"
echo "  • Go to System Settings > Privacy & Security > Full Disk Access"
echo "    and enable Vibeshed.app (needed for Safari bookmarks/history)"
echo "  • Go to System Settings > General > Login Items"
echo "    and add Vibeshed.app to start it at login"
echo ""
echo "Press any key to close..."
read -rn 1
