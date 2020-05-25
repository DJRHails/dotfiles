#!/bin/bash
# Source: https://askubuntu.com/questions/1234742/automatic-light-dark-mode
echo export DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS > sunrise.sh
echo export DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS > sunset.sh
echo "gsettings set org.gnome.desktop.interface gtk-theme Yaru-light" >> sunrise.sh
echo "gsettings set org.gnome.desktop.interface gtk-theme Yaru-dark" >> sunset.sh
chmod 755 sunrise.sh
chmod 755 sunset.sh

currenttime=$(date +%H:%M)
if [[ "$currenttime" > "21:00" ]] || [[ "$currenttime" < "06:00" ]]; then
  ./sunset.sh
else
  ./sunrise.sh
fi
