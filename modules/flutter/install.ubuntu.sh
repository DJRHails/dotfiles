. "$DOTFILES/scripts/core/main.sh"

if ! platform::command_exists flutter; then
    platform::open "https://flutter.dev/docs/get-started/install/linux"
fi
if ! platform::command_exists studio; then
    platform::open "https://developer.android.com/studio"
fi
# tar -xf
# mv flutter /opt/flutter
# export PATH="$PATH:/opt/flutter/bin"
# flutter doctor
