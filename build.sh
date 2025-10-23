#!/bin/bash

# AmneziaWG Build System
# Full build script for packaging and release
# Supports backend+frontend, config examples, versioning, and releases

set -e

# Configuration
PROJECT_NAME="asuswrt-merlin-amneziawg"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SOURCE_DIR}/build"
DIST_DIR="${SOURCE_DIR}/dist"
VERSION_FILE="${SOURCE_DIR}/VERSION"

# Auto-version generation
generate_version() {
    if [ -f "$VERSION_FILE" ]; then
        VERSION=$(cat "$VERSION_FILE")
    else
        # Generate version from git or default
        if git rev-parse --git-dir >/dev/null 2>&1; then
            VERSION="1.0.$(git rev-list --count HEAD 2>/dev/null || echo '0')"
        else
            VERSION="1.0.0"
        fi
        echo "$VERSION" > "$VERSION_FILE"
    fi
    echo "Build version: $VERSION"
}

# Clean previous builds
clean() {
    echo "Cleaning previous builds..."
    rm -rf "$BUILD_DIR" "$DIST_DIR"
    mkdir -p "$BUILD_DIR" "$DIST_DIR"
}

# Build backend components
build_backend() {
    echo "Building backend components..."
    
    if [ -d "${SOURCE_DIR}/src/backend" ]; then
        echo "Building WireGuard kernel module..."
        cd "${SOURCE_DIR}/src/backend"
        
        # Build AmneziaWG module
        if [ -f "Makefile" ]; then
            make clean
            make all
            
            # Copy built modules
            mkdir -p "${BUILD_DIR}/modules"
            find . -name "*.ko" -exec cp {} "${BUILD_DIR}/modules/" \;
        fi
        
        # Build userspace tools
        if [ -d "tools" ]; then
            cd tools
            make clean
            make
            
            # Copy tools
            mkdir -p "${BUILD_DIR}/bin"
            find . -type f -executable -exec cp {} "${BUILD_DIR}/bin/" \;
        fi
        
        cd "$SOURCE_DIR"
    fi
}

# Build frontend components
build_frontend() {
    echo "Building frontend components..."
    
    if [ -d "${SOURCE_DIR}/src/frontend" ]; then
        cd "${SOURCE_DIR}/src/frontend"
        
        # Web UI build
        if [ -f "package.json" ]; then
            echo "Building web interface..."
            npm install
            npm run build
            
            # Copy built assets
            mkdir -p "${BUILD_DIR}/www"
            if [ -d "dist" ]; then
                cp -r dist/* "${BUILD_DIR}/www/"
            elif [ -d "build" ]; then
                cp -r build/* "${BUILD_DIR}/www/"
            fi
        fi
        
        # Copy server scripts
        if [ -f "app.js" ]; then
            mkdir -p "${BUILD_DIR}/server"
            cp -r *.js "${BUILD_DIR}/server/" 2>/dev/null || true
            cp -r lib "${BUILD_DIR}/server/" 2>/dev/null || true
            cp -r routes "${BUILD_DIR}/server/" 2>/dev/null || true
        fi
        
        cd "$SOURCE_DIR"
    fi
}

# Create configuration examples
create_configs() {
    echo "Creating configuration examples..."
    
    CONFIG_DIR="${BUILD_DIR}/configs"
    mkdir -p "$CONFIG_DIR"
    
    # AmneziaWG server config example
    cat > "${CONFIG_DIR}/awg-server.conf.example" << 'EOF'
[Interface]
# Server configuration for AmneziaWG
PrivateKey = SERVER_PRIVATE_KEY_HERE
Address = 10.0.0.1/24
ListenPort = 51820

# AmneziaWG specific parameters
Jc = 4
Jmin = 50
Jmax = 1000
S1 = 86
S2 = 68
H1 = 1234567890
H2 = 9876543210
H3 = 5555555555
H4 = 1111111111

# Client peer
[Peer]
PublicKey = CLIENT_PUBLIC_KEY_HERE
AllowedIPs = 10.0.0.2/32
EOF

    # AmneziaWG client config example
    cat > "${CONFIG_DIR}/awg-client.conf.example" << 'EOF'
[Interface]
# Client configuration for AmneziaWG
PrivateKey = CLIENT_PRIVATE_KEY_HERE
Address = 10.0.0.2/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
# Server peer
PublicKey = SERVER_PUBLIC_KEY_HERE
Endpoint = YOUR_SERVER_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

# AmneziaWG specific parameters (must match server)
Jc = 4
Jmin = 50
Jmax = 1000
S1 = 86
S2 = 68
H1 = 1234567890
H2 = 9876543210
H3 = 5555555555
H4 = 1111111111
EOF

    # ASUSWRT-Merlin integration script
    cat > "${CONFIG_DIR}/install-asuswrt.sh" << 'EOF'
#!/bin/sh
# ASUSWRT-Merlin installation script for AmneziaWG

AWG_DIR="/jffs/addons/amneziawg"
SERVICE_DIR="/opt/etc/init.d"

# Create directories
mkdir -p "$AWG_DIR"
mkdir -p "$SERVICE_DIR"

# Copy binaries and modules
cp bin/* /usr/local/bin/
cp modules/*.ko /lib/modules/$(uname -r)/

# Install web interface
cp -r www/* /www/

# Create service script
cat > "${SERVICE_DIR}/S99amneziawg" << 'SRV'
#!/bin/sh

case "$1" in
  start)
    echo "Starting AmneziaWG..."
    modprobe amneziawg
    awg-quick up /jffs/configs/awg-server.conf
    ;;
  stop)
    echo "Stopping AmneziaWG..."
    awg-quick down /jffs/configs/awg-server.conf
    rmmod amneziawg
    ;;
  restart)
    $0 stop
    $0 start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
    ;;
esac
SRV

chmod +x "${SERVICE_DIR}/S99amneziawg"

echo "AmneziaWG installed successfully!"
echo "Configure your settings in /jffs/configs/awg-server.conf"
EOF

    chmod +x "${CONFIG_DIR}/install-asuswrt.sh"
    
    echo "Configuration examples created in ${CONFIG_DIR}"
}

# Package everything
package() {
    echo "Creating packages..."
    
    cd "$BUILD_DIR"
    
    # Create main package
    tar -czf "${DIST_DIR}/${PROJECT_NAME}-${VERSION}.tar.gz" .
    
    # Create modules-only package
    if [ -d "modules" ]; then
        tar -czf "${DIST_DIR}/${PROJECT_NAME}-modules-${VERSION}.tar.gz" modules/
    fi
    
    # Create web UI package
    if [ -d "www" ]; then
        tar -czf "${DIST_DIR}/${PROJECT_NAME}-webui-${VERSION}.tar.gz" www/ server/
    fi
    
    # Create checksums
    cd "$DIST_DIR"
    sha256sum *.tar.gz > checksums.sha256
    
    cd "$SOURCE_DIR"
    echo "Packages created in ${DIST_DIR}"
}

# Create release
create_release() {
    echo "Creating release documentation..."
    
    cat > "${DIST_DIR}/RELEASE-${VERSION}.md" << EOF
# ${PROJECT_NAME} Release ${VERSION}

Release Date: $(date '+%Y-%m-%d')
Build Date: $(date)

## Package Contents

- **${PROJECT_NAME}-${VERSION}.tar.gz**: Complete package with all components
- **${PROJECT_NAME}-modules-${VERSION}.tar.gz**: Kernel modules only
- **${PROJECT_NAME}-webui-${VERSION}.tar.gz**: Web interface and server components
- **checksums.sha256**: SHA256 checksums for all packages

## Installation

1. Download the appropriate package for your system
2. Extract: \`tar -xzf ${PROJECT_NAME}-${VERSION}.tar.gz\`
3. Run: \`./configs/install-asuswrt.sh\` (for ASUSWRT-Merlin)

## Configuration

Configuration examples are included in the \`configs/\` directory:

- \`awg-server.conf.example\`: Server configuration
- \`awg-client.conf.example\`: Client configuration
- \`install-asuswrt.sh\`: ASUSWRT-Merlin installer

## Changes

- Full build system implementation
- Backend and frontend compilation
- Configuration examples
- Automated packaging and versioning

EOF

    echo "Release documentation created: ${DIST_DIR}/RELEASE-${VERSION}.md"
}

# Help function
show_help() {
    cat << EOF
AmneziaWG Build Script

Usage: $0 [COMMAND]

Commands:
  clean         Clean build directories
  backend       Build backend components only
  frontend      Build frontend components only
  build         Build all components (default)
  package       Create distribution packages
  release       Create full release with documentation
  version       Show/generate version
  help          Show this help

Examples:
  $0              # Full build and package
  $0 clean build  # Clean then build
  $0 release      # Create release packages

EOF
}

# Main build function
main_build() {
    generate_version
    clean
    build_backend
    build_frontend
    create_configs
    package
    
    echo "Build completed successfully!"
    echo "Version: $VERSION"
    echo "Packages available in: $DIST_DIR"
}

# Command handling
case "${1:-build}" in
    clean)
        clean
        ;;
    backend)
        generate_version
        clean
        build_backend
        ;;
    frontend)
        generate_version
        clean
        build_frontend
        ;;
    build)
        main_build
        ;;
    package)
        generate_version
        package
        ;;
    release)
        main_build
        create_release
        echo "Release ${VERSION} created successfully!"
        ;;
    version)
        generate_version
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
