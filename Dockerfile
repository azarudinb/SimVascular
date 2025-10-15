# ============================================================
# SimVascular + XPRA (Browser access)
# Base: Ubuntu 24.04 LTS
# ============================================================
FROM ubuntu:24.04

# --- 1. Install system dependencies ---
RUN apt update && apt install -y software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt update && apt install -y \
    sudo wget curl git python3.11 python3.11-dev python3.11-distutils python3-pip \
    build-essential cmake \
    xfce4-terminal dbus-x11 x11-utils \
    xpra xvfb xauth x11-apps xdg-utils \
    ffmpeg x264 libgl1 libglu1-mesa \
    libxrender1 libxcomposite1 libxcursor1 libxi6 libxtst6 \
    libsm6 libice6 libevent-dev libpcre2-dev libxcb-cursor0 \
    libharfbuzz0b libharfbuzz-dev libfreetype6 libfontconfig1 \
    libnss3 libnss3-dev libnspr4 libnspr4-dev \
    libdbus-1-3 libxrandr2 libxss1 libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 \
    libcups2t64 libdrm2 libgbm1 libgtk-3-0t64 libpango-1.0-0 libxdamage1 libxfixes3 \
    libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 \
    libxcb-shape0 libxcb-sync1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 \
    openbox \
    && apt clean && rm -rf /var/lib/apt/lists/*

# --- 2. Add user ---
RUN useradd -m sim && echo "sim:sim" | chpasswd && adduser sim sudo
USER sim
WORKDIR /home/sim

# --- 3. Copy and install SimVascular ---
COPY SimVascular-Ubuntu-24-2025.08.25.deb /tmp/simvascular.deb
USER root
RUN apt update && apt install -y /tmp/simvascular.deb || apt -f install -y
RUN rm /tmp/simvascular.deb

# --- 4. Create workspace ---
RUN mkdir -p /home/sim/work && chown -R sim:sim /home/sim/work

# --- 5. Create XDG runtime directory for XPRA ---
RUN mkdir -p /run/user/1001 && chown sim:sim /run/user/1001

# --- 6. Set SimVascular environment ---
ENV SV_HOME=/usr/local/sv/simvascular/2025-08-25
ENV PATH="${SV_HOME}/bin:${PATH}"
ENV SV_PLUGIN_PATH="${SV_HOME}/lib/plugins:${SV_HOME}/svExternals/lib/plugins"
ENV QT_PLUGIN_PATH="${SV_HOME}/bin"
ENV CTK_PLUGIN_PATH="${SV_HOME}/svExternals/lib/plugins"
ENV MITK_PLUGIN_PATH="${SV_HOME}/svExternals/lib/plugins"

# --- 7. Set Qt WebEngine path (search for it dynamically at runtime) ---
ENV QTWEBENGINEPROCESS_PATH="${SV_HOME}/bin/QtWebEngineProcess"

# --- 7. Fix library paths - Add ALL potential library directories ---
ENV LD_LIBRARY_PATH="${SV_HOME}/lib:${SV_HOME}/lib/plugins:${SV_HOME}/bin:${SV_HOME}/lib64:${SV_HOME}/lib/x86_64-linux-gnu:/usr/local/lib:/usr/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"

# --- 8. Create wrapper script to find all SimVascular libraries ---
USER root
RUN echo '#!/bin/bash\n\
export DISPLAY=:0\n\
export XDG_RUNTIME_DIR=/run/user/1001\n\
\n\
# Initialize with base library path\n\
SV_LIB_PATH="${SV_HOME}/lib:${SV_HOME}/lib/plugins:${SV_HOME}/bin"\n\
\n\
# Find ALL directories containing .so files in SimVascular installation\n\
echo "Searching for all library directories in ${SV_HOME}..."\n\
while IFS= read -r libdir; do\n\
    SV_LIB_PATH="${libdir}:${SV_LIB_PATH}"\n\
done < <(find ${SV_HOME} -type f -name "*.so*" -exec dirname {} \; 2>/dev/null | sort -u)\n\
\n\
# Update LD_LIBRARY_PATH with all found directories\n\
export LD_LIBRARY_PATH="${SV_LIB_PATH}:${LD_LIBRARY_PATH}"\n\
\n\
# Find QtWebEngineProcess\n\
echo ""\n\
echo "Searching for QtWebEngineProcess..."\n\
QTWEBENGINE=$(find ${SV_HOME} -type f -name "QtWebEngineProcess" 2>/dev/null | head -1)\n\
if [ -n "$QTWEBENGINE" ]; then\n\
    export QTWEBENGINEPROCESS_PATH="$QTWEBENGINE"\n\
    echo "Found QtWebEngineProcess at: $QTWEBENGINE"\n\
else\n\
    echo "WARNING: QtWebEngineProcess not found - web features may not work"\n\
fi\n\
\n\
# Show available plugins\n\
echo ""\n\
echo "Checking for MITK plugins..."\n\
if [ -d "${SV_HOME}/svExternals/lib/plugins" ]; then\n\
    echo "Found plugins in svExternals:"\n\
    ls -la "${SV_HOME}/svExternals/lib/plugins" | grep -E "org\\.mitk|liborg" | wc -l | xargs echo "  Plugin count:"\n\
fi\n\
if [ -d "${SV_HOME}/lib/plugins" ]; then\n\
    echo "Found plugins in lib:"\n\
    ls -la "${SV_HOME}/lib/plugins" | grep -E "org\\.sv|liborg" | wc -l | xargs echo "  Plugin count:"\n\
fi\n\
echo ""\n\
echo "Final LD_LIBRARY_PATH configured."\n\
echo ""\n\
\n\
# Start XPRA with SimVascular\n\
exec xpra start --bind-tcp=0.0.0.0:10000 \\\n\
    --html=on \\\n\
    --start-child="openbox-session" \\\n\
    --start-child="${SV_HOME}/bin/simvascular" \\\n\
    --exit-with-children \\\n\
    --daemon=no \\\n\
    --no-daemon\n\
' > /usr/local/bin/start-simvascular.sh && chmod +x /usr/local/bin/start-simvascular.sh

# --- 9. Switch to sim user ---
USER sim
WORKDIR /home/sim/work
ENV XDG_RUNTIME_DIR=/run/user/1001

# --- 10. Expose XPRA web port ---
EXPOSE 10000

# --- 11. Start with wrapper script ---
CMD ["/usr/local/bin/start-simvascular.sh"]