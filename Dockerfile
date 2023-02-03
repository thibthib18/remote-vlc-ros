# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Ubuntu release versions 22.04, 20.04, and 18.04 are supported
ARG UBUNTU_RELEASE=18.04
ARG CUDA_VERSION=11.7.1
FROM nvcr.io/nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_RELEASE}

LABEL maintainer "https://github.com/ehfd,https://github.com/danisla"

ARG UBUNTU_RELEASE
ARG CUDA_VERSION
# Make all NVIDIA GPUs visible by default
ARG NVIDIA_VISIBLE_DEVICES=all
# Use noninteractive mode to skip confirmation when installing packages
ARG DEBIAN_FRONTEND=noninteractive
# All NVIDIA driver capabilities should preferably be used, check `NVIDIA_DRIVER_CAPABILITIES` inside the container if things do not work
ENV NVIDIA_DRIVER_CAPABILITIES all
# Enable AppImage execution in a container
ENV APPIMAGE_EXTRACT_AND_RUN 1
# System defaults that should not be changed
ENV DISPLAY :35
ENV XDG_RUNTIME_DIR /tmp/runtime-user
ENV PULSE_SERVER unix:/run/pulse/native
ENV LD_LIBRARY_PATH /usr/lib/x86_64-linux-gnu:/usr/lib/i386-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}

# Default environment variables (password is "mypasswd")
ENV TZ UTC
ENV SIZEW 1920
ENV SIZEH 1080
ENV REFRESH 60
ENV DPI 96
ENV CDEPTH 24
ENV VGL_DISPLAY egl
ENV PASSWD mypasswd
ENV NOVNC_ENABLE false
ENV WEBRTC_ENCODER nvh264enc
ENV WEBRTC_ENABLE_RESIZE false
ENV ENABLE_AUDIO true
ENV ENABLE_BASIC_AUTH false

ENV ROS_DISTRO=humble


# Set versions for components that should be manually checked before upgrading, other component versions are automatically determined by fetching the version online
ARG VIRTUALGL_VERSION=3.0.2
ARG NOVNC_VERSION=1.3.0

# Install locales to prevent X11 errors
RUN apt-get clean && \
    apt-get update && apt-get install --no-install-recommends -y locales && \
    rm -rf /var/lib/apt/lists/* && \
    locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install Xvfb and other important libraries or packages
RUN apt-get update && apt-get install --no-install-recommends -y \
        curl \
        nano \
        supervisor \
        net-tools \
        libglvnd-dev \
        libgl1-mesa-dev \
        libegl1-mesa-dev \
        libgles2-mesa-dev \
        libglvnd0 \
        libgl1 \
        libglx0 \
        libegl1 \
        libgles2 \
        libglu1 \
        libsm6 \
        vainfo \
        vdpauinfo \
        mesa-utils \
        mesa-utils-extra \
        va-driver-all \
        mesa-vulkan-drivers \
        libvulkan-dev \
        libdbus-c++-1-0v5 \
        libxrandr-dev \
        # Install Xvfb, packages above this line should be the same between docker-nvidia-glx-desktop and docker-nvidia-egl-desktop
        xvfb && \
    # Install Vulkan utilities
    if [ "${UBUNTU_RELEASE}" \< "20.04" ]; then apt-get install --no-install-recommends -y vulkan-utils; else apt-get install --no-install-recommends -y vulkan-tools; fi && \
    rm -rf /var/lib/apt/lists/* && \
    # Configure EGL manually
    mkdir -p /usr/share/glvnd/egl_vendor.d/ && \
    echo "{\n\
    \"file_format_version\" : \"1.0.0\",\n\
    \"ICD\": {\n\
        \"library_path\": \"libEGL_nvidia.so.0\"\n\
    }\n\
}" > /usr/share/glvnd/egl_vendor.d/10_nvidia.json

# Configure Vulkan manually
RUN VULKAN_API_VERSION=$(dpkg -s libvulkan1 | grep -oP 'Version: [0-9|\.]+' | grep -oP '[0-9]+(\.[0-9]+)(\.[0-9]+)') && \
    mkdir -p /etc/vulkan/icd.d/ && \
    echo "{\n\
    \"file_format_version\" : \"1.0.0\",\n\
    \"ICD\": {\n\
        \"library_path\": \"libGLX_nvidia.so.0\",\n\
        \"api_version\" : \"${VULKAN_API_VERSION}\"\n\
    }\n\
}" > /etc/vulkan/icd.d/nvidia_icd.json

# Install VirtualGL and make libraries available for preload
ARG VIRTUALGL_URL="https://sourceforge.net/projects/virtualgl/files"
RUN curl -fsSL -O "${VIRTUALGL_URL}/virtualgl_${VIRTUALGL_VERSION}_amd64.deb" && \
    apt-get update && apt-get install -y --no-install-recommends ./virtualgl_${VIRTUALGL_VERSION}_amd64.deb && \
    rm -f "virtualgl_${VIRTUALGL_VERSION}_amd64.deb" && \
    rm -rf /var/lib/apt/lists/* && \
    chmod u+s /usr/lib/libvglfaker.so && \
    chmod u+s /usr/lib/libdlfaker.so


# Install latest selkies-gstreamer (https://github.com/selkies-project/selkies-gstreamer) build, Python application, and web application, should be consistent with selkies-gstreamer documentation
RUN apt-get update && apt-get install --no-install-recommends -y \
        build-essential \
        python3-pip \
        python3-dev \
        python3-gi \
        python3 \
        python3-setuptools \
        python3-wheel \
        tzdata \
        sudo \
        udev \
        xclip \
        x11-utils \
        xdotool \
        wmctrl \
        jq \
        gdebi-core \
        x11-xserver-utils \
        xserver-xorg-core \
        libopus0 \
        libgdk-pixbuf2.0-0 \
        libsrtp2-1 \
        libxdamage1 \
        libxml2-dev \
        libwebrtc-audio-processing1 \
        libcairo-gobject2 \
        pulseaudio \
        libpulse0 \
        libpangocairo-1.0-0 \
        libgirepository1.0-dev \
        libjpeg-dev \
        libvpx-dev \
        zlib1g-dev \
        x264 && \
    if [ "${UBUNTU_RELEASE}" \> "20.04" ]; then apt-get install --no-install-recommends -y xcvt; fi && \
    rm -rf /var/lib/apt/lists/* && \
    cd /opt && \
    # Automatically fetch the latest selkies-gstreamer version and install the components
    SELKIES_VERSION=$(curl -fsSL "https://api.github.com/repos/selkies-project/selkies-gstreamer/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g') && \
    curl -fsSL "https://github.com/selkies-project/selkies-gstreamer/releases/download/v${SELKIES_VERSION}/selkies-gstreamer-v${SELKIES_VERSION}-ubuntu${UBUNTU_RELEASE}.tgz" | tar -zxf - && \
    curl -O -fsSL "https://github.com/selkies-project/selkies-gstreamer/releases/download/v${SELKIES_VERSION}/selkies_gstreamer-${SELKIES_VERSION}-py3-none-any.whl" && pip3 install "selkies_gstreamer-${SELKIES_VERSION}-py3-none-any.whl" && rm -f "selkies_gstreamer-${SELKIES_VERSION}-py3-none-any.whl" && \
    curl -fsSL "https://github.com/selkies-project/selkies-gstreamer/releases/download/v${SELKIES_VERSION}/selkies-gstreamer-web-v${SELKIES_VERSION}.tgz" | tar -zxf - && \
    cd /usr/local/cuda/lib64 && sudo find . -maxdepth 1 -type l -name "*libnvrtc.so.*" -exec sh -c 'ln -snf $(basename {}) libnvrtc.so' \;



# Add custom packages right below this comment, or use FROM in a new container and replace entrypoint.sh or supervisord.conf, and set ENTRYPOINT to /usr/bin/supervisord

# RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg && \
#     echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null && \
#     apt-get update && apt-get install --no-install-recommends -y \
#         ros-${ROS_DISTRO}-plotjuggler-ros ros-${ROS_DISTRO}-rclcpp \
#         sudo matchbox-window-manager && \
#         rm -rf /var/lib/apt/lists/*


# RUN echo 15385 > /proc/sys/user/max_user_namespaces
# RUN apt update && apt install -y vlc && \
#     echo "OK"
#     # flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && \
    # flatpak install -y --noninteractive org.kde.Platform/x86_64/5.15-22.08 && \
    # flatpak install -y --noninteractive flathub org.videolan.VLC


WORKDIR /
RUN apt-get update && apt-get install --no-install-recommends -y \
  wget

# Build and install Live555 from source
# RUN wget http://www.live555.com/liveMedia/public/live.2023.01.19.tar.gz
# RUN tar -xf live.2023.01.19.tar.gz
# WORKDIR /live
# RUN ./genMakefiles linux
# RUN make
# WORKDIR /
# RUN cp -r live /usr/lib
# RUN make install

# Build and install latest vlc from source
RUN cp /etc/apt/sources.list /etc/apt/sources.list~ 
RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
RUN apt-get update && apt-get install --no-install-recommends -y \
      git g++ make libtool automake autopoint pkg-config flex bison lua5.2
WORKDIR /
RUN git clone --branch 3.0.18 --depth 1 https://github.com/videolan/vlc.git
WORKDIR /vlc
RUN ./bootstrap
RUN apt build-dep -y vlc
RUN ./configure --enable-live555 
RUN make
RUN make install

RUN apt install -y dbus-x11

# Create user with password ${PASSWD} and assign adequate groups
RUN groupadd -g 1000 user && \
    useradd -ms /bin/bash user -u 1000 -g 1000 && \
    usermod -a -G adm,audio,cdrom,dialout,dip,fax,floppy,input,lp,plugdev,pulse-access,sudo,tape,tty,video,voice user && \
    echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    chown user:user /home/user && \
    echo "user:${PASSWD}" | chpasswd && \
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" > /etc/timezone

# Copy scripts and configurations used to start the container
COPY entrypoint.sh /etc/entrypoint.sh
RUN chmod 755 /etc/entrypoint.sh
COPY selkies-gstreamer-entrypoint.sh /etc/selkies-gstreamer-entrypoint.sh
RUN chmod 755 /etc/selkies-gstreamer-entrypoint.sh
COPY supervisord.conf /etc/supervisord.conf
RUN chmod 755 /etc/supervisord.conf

EXPOSE 8080

USER user
ENV SHELL /bin/bash
ENV USER user
WORKDIR /home/user

ENTRYPOINT ["/usr/bin/supervisord"]
