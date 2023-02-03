#!/bin/bash -e

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

trap "echo TRAPed signal" HUP INT QUIT KILL TERM

# Create and modify permissions of XDG_RUNTIME_DIR
sudo -u user mkdir -pm700 /tmp/runtime-user
sudo chown user:user /tmp/runtime-user
sudo -u user chmod 700 /tmp/runtime-user
# Make user directory owned by the user in case it is not
sudo chown user:user /home/user
# Change operating system password to environment variable
echo "user:$PASSWD" | sudo chpasswd
# Remove directories to make sure the desktop environment starts
sudo rm -rf /tmp/.X* ~/.cache
# Change time zone from environment variable
sudo ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" | sudo tee /etc/timezone > /dev/null
# Add game directories for Lutris and VirtualGL directories to path
export PATH="${PATH}:/opt/VirtualGL/bin"

# Start DBus without systemd
sudo /etc/init.d/dbus start
# Configure environment for selkies-gstreamer utilities
source /opt/gstreamer/gst-env

# Default display is :0 across the container
export DISPLAY=":35"
# Run Xvfb server with required extensions
Xvfb "${DISPLAY}" -ac -screen "0" "8192x4096x${CDEPTH}" -dpi "${DPI}" +extension "RANDR" +extension "GLX" +iglx +extension "MIT-SHM" +render -nolisten "tcp" -noreset -shmem &

# Wait for X11 to start
echo "Waiting for X socket"
until [ -S "/tmp/.X11-unix/X${DISPLAY/:/}" ]; do sleep 1; done
echo "X socket is ready"

# Resize the screen to the provided size
selkies-gstreamer-resize "${SIZEW}x${SIZEH}"

# Run the x11vnc + noVNC fallback web interface if enabled
if [ "${NOVNC_ENABLE,,}" = "true" ]; then
    if [ -n "$NOVNC_VIEWPASS" ]; then export NOVNC_VIEWONLY="-viewpasswd ${NOVNC_VIEWPASS}"; else unset NOVNC_VIEWONLY; fi
    x11vnc -display "${DISPLAY}" -passwd "${BASIC_AUTH_PASSWORD:-$PASSWD}" -shared -forever -repeat -xkb -snapfb -threads -xrandr "resize" -rfbport 5900 ${NOVNC_VIEWONLY} &
    /opt/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 8080 --heartbeat 10 &
fi


KDE_START="matchbox-window-manager -use_titlebar no -use_cursor yes"


# Use VirtualGL to run the KDE desktop environment with OpenGL if the GPU is available, otherwise use OpenGL with llvmpipe
if [ -n "$(nvidia-smi --query-gpu=uuid --format=csv | sed -n 2p)" ]; then
    export VGL_DISPLAY="${VGL_DISPLAY:-egl}"
    export VGL_REFRESHRATE="$REFRESH"
    vglrun +wm $KDE_START &
else
    $KDE_START &
fi


# Add custom processes right below this line, or within `supervisord.conf` to perform service management similar to systemd

# source /opt/ros/humble/setup.bash
# vglrun -d ${VGL_DISPLAY} /opt/ros/humble/lib/plotjuggler/plotjuggler
vglrun -d ${VGL_DISPLAY} /vlc/vlc

echo "Session Running. Press [Return] to exit."
read
