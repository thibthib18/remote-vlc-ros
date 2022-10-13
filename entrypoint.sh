#!/bin/bash -e

trap "echo TRAPed signal" HUP INT QUIT KILL TERM

# Make user directory owned by the user in case it is not
sudo chown user:user /home/user
# Change operating system password to environment variable
echo "user:$PASSWD" | sudo chpasswd
# Remove directories to make sure the desktop environment starts
sudo rm -rf /tmp/.X* ~/.cache ~/.config/xfce4
# Change time zone from environment variable
sudo ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" | sudo tee /etc/timezone > /dev/null
# Add game directories and VirtualGL directories to path
export PATH="${PATH}:/usr/local/games:/usr/games:/opt/VirtualGL/bin"
# Add LibreOffice to library path
export LD_LIBRARY_PATH="/usr/lib/libreoffice/program:${LD_LIBRARY_PATH}"

# Start DBus without systemd
sudo /etc/init.d/dbus start
# Configure environment for selkies-gstreamer utilities
source /opt/gstreamer/gst-env

# Default display is :0 across the container
export DISPLAY=":0"
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

# Use VirtualGL to run the Xfce4 desktop environment with OpenGL if the GPU is available, otherwise use OpenGL with llvmpipe
if [ -n "$(nvidia-smi --query-gpu=uuid --format=csv | sed -n 2p)" ]; then
  export VGL_DISPLAY="${VGL_DISPLAY:-egl}"
  export VGL_REFRESHRATE="$REFRESH"
  vglrun +wm xfce4-session &
else
  xfce4-session &
fi

# Add custom processes here, or within `supervisord.conf` to perform service management similar to systemd

# Fix selkies-gstreamer keyboard mapping, remove if selkies-gstreamer issue #6 is fixed and in release
if [ "${NOVNC_ENABLE,,}" != "true" ]; then
  sudo xmodmap -e "keycode 94 shift = less less"
fi

echo "Session Running. Press [Return] to exit."
read
