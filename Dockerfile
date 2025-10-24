FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV XPRA_PORT=14500

# Install dependencies with retry logic
RUN apt-get clean && \
    (apt-get update --fix-missing || sleep 10 && apt-get update || sleep 20 && apt-get update) && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    gnupg \
    software-properties-common \
    build-essential \
    gfortran \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install OpenMPI
RUN apt-get update && apt-get install -y \
    openmpi-bin \
    openmpi-common \
    libopenmpi-dev \
    && rm -rf /var/lib/apt/lists/*

# Install additional dependencies for SimVascular
RUN apt-get update && apt-get install -y \
    libharfbuzz-dev \
    libxcb-cursor0 \
    && rm -rf /var/lib/apt/lists/*

# Install XCB libraries
RUN apt-get update && apt-get install -y \
    '^libxcb.*-dev' \
    libx11-xcb-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy and install SimVascular packages
COPY SimVascular-Ubuntu-24-2025.08.25.deb /tmp/
COPY svMultiPhysics-Ubuntu-24-2025.06.20.deb /tmp/
COPY oneD-solver-Ubuntu-24-2025.07.02.deb /tmp/
COPY svZeroDSolver-Ubuntu-24-2025-07-02.deb /tmp/
RUN dpkg -i /tmp/SimVascular-Ubuntu-24-2025.08.25.deb /tmp/svMultiPhysics-Ubuntu-24-2025.06.20.deb /tmp/oneD-solver-Ubuntu-24-2025.07.02.deb /tmp/svZeroDSolver-Ubuntu-24-2025-07-02.deb || apt-get install -f -y && \
    rm /tmp/*.deb



# Install additional dependencies 
RUN apt-get update && apt-get install -y \
    xterm \
    x11-apps \
    python3 \
    python3-dev \
    libpython3-dev \
    && rm -rf /var/lib/apt/lists/*

# Add Xpra repository and key
RUN wget -q -O /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc && \
    echo "deb [signed-by=/usr/share/keyrings/xpra.asc] https://xpra.org/ noble main" > /etc/apt/sources.list.d/xpra.list && \
    apt-get update && apt-get install -y xpra && \
    rm -rf /var/lib/apt/lists/*

# Ensure HTML5 client directory exists before copying config
RUN mkdir -p /etc/xpra/html5-client/
COPY settings.txt /etc/xpra/html5-client/default-settings.txt

# Set base SimVascular path (don't set Python env globally to avoid xpra conflicts)
ENV SV_HOME=/usr/local/sv/simvascular/2025-08-25

# Expose Xpra HTML5 port
EXPOSE ${XPRA_PORT}

# Create projects directory and set as volume
RUN mkdir -p /projects
VOLUME ["/projects"]

# Create startup script to set environment only for SimVascular
RUN echo '#!/bin/bash\n\
export PYTHONHOME=${SV_HOME}/svExternals\n\
export PYTHONPATH=${SV_HOME}/svExternals/lib/python3.11\n\
export PATH="${SV_HOME}/bin:${SV_HOME}/svExternals/bin:/usr/bin:${PATH}"\n\
export SV_PLUGIN_PATH="${SV_HOME}/lib/plugins:${SV_HOME}/svExternals/lib/plugins"\n\
export QT_PLUGIN_PATH="${SV_HOME}/bin"\n\
export QT_QPA_PLATFORM_PLUGIN_PATH="${SV_HOME}/bin/platforms"\n\
export CTK_PLUGIN_PATH="${SV_HOME}/svExternals/lib/plugins"\n\
export MITK_PLUGIN_PATH="${SV_HOME}/svExternals/lib/plugins"\n\
export QTWEBENGINEPROCESS_PATH="${SV_HOME}/svExternals/bin/QtWebEngineProcess"\n\
export LD_LIBRARY_PATH="${SV_HOME}/lib:${SV_HOME}/lib/plugins:${SV_HOME}/bin:${SV_HOME}/lib64:${SV_HOME}/lib/x86_64-linux-gnu:${SV_HOME}/svExternals/lib:${SV_HOME}/svExternals/lib/plugins:${SV_HOME}/svExternals/bin:/usr/local/lib:/usr/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"\n\
export QT_QPA_PLATFORM=xcb\n\
export QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox"\n\
export OMPI_ALLOW_RUN_AS_ROOT=1\n\
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1\n\
cd /projects\n\
exec "${SV_HOME}/bin/simvascular" --qt-gui "$@"\n' > /usr/local/bin/start-simvascular.sh && \
chmod +x /usr/local/bin/start-simvascular.sh

# Start Xpra with SimVascular
CMD ["sh", "-c", "xpra start --bind-tcp=0.0.0.0:14500 --html=on --start-child='/usr/local/bin/start-simvascular.sh' --daemon=no --tray=no --system-tray=no --notifications=no --sharing=yes --exit-with-client=no"]
