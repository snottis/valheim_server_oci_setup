#!/bin/bash

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
ORANGE=$(tput setaf 3)
BOLD=$(tput bold)
CLEAR=$(tput sgr0)

function warn { >&2 echo -en "\n\n${BOLD}${ORANGE}[-] $* ${CLEAR}\n"; }
function success { >&2 echo -en "${BOLD}${GREEN}[+] $* ${CLEAR}\n"; }
function info { >&2 echo -en "\n\n${BOLD}[ ] $* ${CLEAR}\n"; }
function error { >&2 echo -en "${BOLD}${RED}[!] $* ${CLEAR}\n"; }
function notify { >&2 echo -en "\n\n${BOLD}${ORANGE}[!] $* ${CLEAR}\n"; }

# Gives us information about the underlying OS using systemd
# shellcheck source=/dev/null
if [[ ! -r /etc/os-release ]]; then
    error "Cannot identify the operating system: /etc/os-release is missing."
    exit 1
fi
source /etc/os-release

set -e
set -o pipefail

# Environment variables / Overridable options
CROSSPLAY_SUPPORT=${CROSSPLAY_SUPPORT:-false} # Enables crossplay for a newly generated credentials file
STEAM_PLATFORM=${STEAM_PLATFORM:-linux64}     # Allow overriding the binary the steamcmd should use
USE_BOX=${USE_BOX:-false}                     # Box86/Box64 is retained as a legacy Ubuntu 22.04 option

CURRENT_USER="$(id -un)"
SERVER_HOME="${HOME}"
HOST_ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"

# FEX does not currently publish a dedicated Ubuntu 26.04 guest image through
# FEXRootFSFetcher.  The Ubuntu 24.04 guest image is compatible with the 26.04
# host and is also used by the current FEX-on-26.04 guidance.
if [[ -z ${FEX_ROOTFS_VERSION:-} ]]; then
    case ${VERSION_ID} in
    26.04) FEX_ROOTFS_VERSION=24.04 ;;
    *) FEX_ROOTFS_VERSION=${VERSION_ID} ;;
    esac
fi
FEX_ROOTFS_NAME="Ubuntu_${FEX_ROOTFS_VERSION/./_}"

SERVER_SCRIPT_PATH="${SERVER_HOME}/valheim_server/start_server.custom.sh"

function is_arm64() {
    [[ ${HOST_ARCH} == arm64 || ${HOST_ARCH} == aarch64 ]]
}

function is_x86_64() {
    [[ ${HOST_ARCH} == amd64 || ${HOST_ARCH} == x86_64 ]]
}

function perform_self_update {
    if [[ -n $NO_SELF_UPDATE ]]; then
        notify "Skipping self-update"
        return
    fi

    SETUP_SCRIPT_URL=${SETUP_SCRIPT_URL:-"https://raw.githubusercontent.com/husjon/valheim_server_oci_setup/refs/heads/main/setup_valheim_server.sh"}

    ETAG_CACHE="${HOME}/.cache/setup_valheim_server.etag"
    SETUP_SCRIPT_PATH="$(realpath "$0")"

    mkdir -p "$(dirname "${ETAG_CACHE}")"
    TEMP_SCRIPT_PATH="$(mktemp)"
    trap 'rm -f -- "${TEMP_SCRIPT_PATH}"' EXIT

    info "Checking for setup script updates"

    curl --fail --silent --show-error --etag-save "${ETAG_CACHE}" --etag-compare "${ETAG_CACHE}" -L "${SETUP_SCRIPT_URL}" -o "${TEMP_SCRIPT_PATH}"

    if [[ -s "${TEMP_SCRIPT_PATH}" ]]; then
        if ! cmp --silent "$SETUP_SCRIPT_PATH" "$TEMP_SCRIPT_PATH"; then
            echo "Setup script available, updating..."

            notify "Changes (< = removed  |  > = added):"
            diff --color --minimal "${SETUP_SCRIPT_PATH}" "${TEMP_SCRIPT_PATH}" || true
            echo
            sleep 1
            mv "${TEMP_SCRIPT_PATH}" "${SETUP_SCRIPT_PATH}"
            success "Updated setup script."
            notify "Please re-run the setup script..."
            echo
            exit 0
        fi
    fi

    success "No update available"
    echo
    rm -f -- "${TEMP_SCRIPT_PATH}"
    trap - EXIT
}

function initial_setup() {
    mkdir -p ~/.cache

    if [[ ! -f ~/.cache/valheim_server_setup ]]; then
        info "First time setup"
        info "Updating and upgrading the OS"
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
        touch ~/.cache/valheim_server_setup
        success "Updating and upgrading the OS - Done"

        warn "Rebooting..."
        sudo reboot
    fi

    info "Installing packages"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        diffutils \
        git \
        iptables \
        iptables-persistent \
        python3 \
        software-properties-common \
        squashfs-tools \
        tar \
        unzip \
        wget
    success "Installing packages - Done"
}

function install_box86_and_box64() {
    uninstall_fex_emu

    sudo dpkg --add-architecture armhf
    sudo apt-get update

    info "Installing required packages"
    sudo apt-get install -y \
        build-essential \
        cmake \
        gcc-arm-linux-gnueabihf \
        git \
        libc6:armhf \
        libncurses6 \
        libstdc++6 \
        libpulse0
    success "Installing required packages - Done"

    if is_arm64; then
        notify "Found system to be 64bit Arm"
        # Fetch and build Box 86 and 64
        for ARCH in {86,64}; do
            cd
            if [[ ! -d "$HOME/box${ARCH}" ]]; then
                info "Fetching Box${ARCH}"
                git clone "https://github.com/ptitSeb/box${ARCH}"
                mkdir -p "box${ARCH}/build"
                success "Fetching Box${ARCH} - Done"
            fi

            info "Building Box${ARCH}"
            cd "$HOME/box${ARCH}/build"
            git fetch
            if [[ $ARCH == 64 ]] && [[ -n $BOX64_VERSION ]]; then
                TAG="${BOX64_VERSION}"
            elif [[ $ARCH == 86 ]] && [[ -n $BOX86_VERSION ]]; then
                TAG="${BOX86_VERSION}"
            else
                TAG="$(git tag | tail -n 1)"
            fi

            git checkout "${TAG}"
            cmake .. -DRPI4ARM64=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo
            make -j"$(nproc)"
            success "Building Box${ARCH} - Done"

            info "Installing Box${ARCH}"
            sudo make install
            success "Installing Box${ARCH} - Done"
        done
        sudo systemctl restart systemd-binfmt.service 2>/dev/null || true

        if ! grep -F '[valheim_server.x86_64]  #box64 v0.2.6' ~/.box64rc; then
            info "Adding box64 configuration"
            cat <<-EOF | tee -a ~/.box64rc
				[valheim_server.x86_64]  #box64 v0.2.6
				BOX64_DYNAREC_BLEEDING_EDGE=0
				BOX64_DYNAREC_STRONGMEM=3
			EOF
        fi
    fi
}

function uninstall_box86_and_box64() {
    if type box86 >/dev/null; then
        notify "Uninstalling Box86"
        pushd ~/box86/build
        sudo make uninstall
        popd
        success "Uninstalling Box86 - Done"
    fi

    if type box64 >/dev/null; then
        notify "Uninstalling Box64"
        pushd ~/box64/build
        sudo make uninstall
        popd
        success "Uninstalling Box64 - Done"
    fi

    sudo systemctl restart systemd-binfmt 2>/dev/null || true
}

function determine_arm_instruction_set() {
    # https://en.wikipedia.org/wiki/Comparison_of_ARM_processors (see: ARM part numbers)

    CPU_PART=$(grep -i 'CPU part' /proc/cpuinfo | head -n 1 | grep -Eo '0x\w+' || true)

    case "$CPU_PART" in
    0xd0c)
        # 0xd0c=Ampere Altra / Neoverse N1
        echo 8.2
        ;;
    *)
        # use 8.4 in case we can't determine the instruction set
        notify "Could not determine ARM instruction set, using version 8.4"
        sleep 2
        echo 8.4
        ;;
    esac
}

function install_fex_emu() {
    uninstall_box86_and_box64

    info "Installing FEX Emu"

    ARM_INSTRUCTION_SET=${ARM_INSTRUCTION_SET:-$(determine_arm_instruction_set)}

    sudo add-apt-repository -y ppa:fex-emu/fex
    sudo apt-get update

    sudo apt-get install -y \
        fex-emu-armv"${ARM_INSTRUCTION_SET}" \
        fex-emu-binfmt32 \
        fex-emu-binfmt64

    if ! fex_rootfs_is_installed; then
        notify "Creating FEX ${FEX_ROOTFS_NAME} RootFS, this might take a while"
        FEXRootFSFetcher \
            -y \
            -x \
            -a \
            --distro-name=ubuntu \
            --distro-version="${FEX_ROOTFS_VERSION}"
        success "Creating RootFS - Done"
    fi

    success "Installing FEX Emu - Done"
}

function fex_rootfs_is_installed() {
    local rootfs_base

    for rootfs_base in \
        "${HOME}/.local/share/fex-emu/RootFS" \
        "${HOME}/.fex-emu/RootFS"; do
        if [[ -d "${rootfs_base}/${FEX_ROOTFS_NAME}" ]] || \
            [[ -f "${rootfs_base}/${FEX_ROOTFS_NAME}.sqsh" ]] || \
            [[ -f "${rootfs_base}/${FEX_ROOTFS_NAME}.ero" ]]; then
            return 0
        fi
    done

    return 1
}

function uninstall_fex_emu() {
    ARM_INSTRUCTION_SET=${ARM_INSTRUCTION_SET:-$(determine_arm_instruction_set)}

    if type FEXInterpreter >/dev/null; then
        notify "Uninstalling FEX"
        sudo apt-get purge -y \
            fex-emu-armv"${ARM_INSTRUCTION_SET}" \
            fex-emu-binfmt32 \
            fex-emu-binfmt64

        sudo add-apt-repository -y --remove ppa:fex-emu/fex

        sudo systemctl restart systemd-binfmt 2>/dev/null || true
        success "Uninstalling FEX - Done"
    fi
}

function install_steamcmd() {
    if [[ ! -f "${SERVER_HOME}/steamcmd/steamcmd.sh" ]]; then
        if is_x86_64; then
            sudo dpkg --add-architecture i386
            sudo apt-get update
            sudo apt-get install -y lib32gcc-s1
        fi

        info "Fetching steamcmd"
        mkdir -p "${SERVER_HOME}/steamcmd"
        cd "${SERVER_HOME}/steamcmd"
        curl --fail --silent --show-error --location "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar --extract --gzip --verbose

        STEAM_PLATFORM=${STEAM_PLATFORM} ./steamcmd.sh +quit

        success "Fetching steamcmd - Done"
    fi
    # Add steamcmd steamclient.so symlink
    info "Adding steamclient.so symlink"
    mkdir -p "${SERVER_HOME}/.steam/sdk64"
    ln -frs "${SERVER_HOME}/steamcmd/linux64/steamclient.so" "${SERVER_HOME}/.steam/sdk64/"
}

function install_valheim_dedicated_server() {
    sudo apt-get install -y \
        libatomic1 \
        libpulse-dev \
        libpulse0

    if [[ ! -x "${SERVER_HOME}/valheim_server/valheim_server.x86_64" ]]; then
        info "Installing Valheim Dedicated Server"
        cd "${SERVER_HOME}/steamcmd"
        STEAM_PLATFORM=${STEAM_PLATFORM} ./steamcmd.sh \
            +@sSteamCmdForcePlatformType linux \
            +force_install_dir "${SERVER_HOME}/valheim_server" \
            +login anonymous \
            +app_update 896660 validate \
            +quit
        success "Installing Valheim Dedicated Server - Done"
    fi
}

function install_crossplay_library() {
    local crossplay_enabled=${CROSSPLAY_SUPPORT}
    local library_source=""
    local rootfs_base
    local target="${SERVER_HOME}/valheim_server/linux64/libpulse-mainloop-glib.so.0"

    if ! is_arm64; then
        rm -f -- "${target}"
        return
    fi

    # Credentials are the source of truth after the first installer run.  Do
    # not source this file because it also contains the server password.
    if [[ -f "${SERVER_HOME}/server_credentials" ]] && \
        grep -q '^CROSSPLAY=1$' "${SERVER_HOME}/server_credentials"; then
        crossplay_enabled=true
    fi

    if [[ ${crossplay_enabled} != true ]]; then
        rm -f -- "${target}"
        return
    fi

    if [[ -f ${target} ]]; then
        return
    fi

    info "Looking for the x86_64 PulseAudio library required by crossplay"
    for rootfs_base in \
        "${HOME}/.local/share/fex-emu/RootFS" \
        "${HOME}/.fex-emu/RootFS" \
        "${SERVER_HOME}/steamcmd"; do
        [[ -d ${rootfs_base} ]] || continue
        library_source="$(find "${rootfs_base}" \( -type f -o -type l \) -path '*/usr/lib/x86_64-linux-gnu/libpulse-mainloop-glib.so.0' -print -quit 2>/dev/null)"
        [[ -n ${library_source} ]] && break
    done

    if [[ -n ${library_source} ]]; then
        cp -L -- "${library_source}" "${target}"
        success "Installing libpulse-mainloop-glib.so.0:x86_64 - Done"
    else
        warn "Could not find the x86_64 PulseAudio library in the FEX RootFS. Crossplay may not start; rerun the installer after the RootFS is available."
    fi
}

function update_firewall() {
    info "Updating firewall rules"
    local server_port=2456
    local configured_port

    configured_port="$(grep -E '^PORT=[0-9]+$' "${SERVER_HOME}/server_credentials" | tail -n 1 | cut -d= -f2 || true)"
    if [[ ${configured_port} =~ ^[0-9]+$ ]]; then
        server_port=${configured_port}
    fi

    RULES=(
        "INPUT -p udp -m state --state NEW -m udp --dport ${server_port} -j ACCEPT"
        "INPUT -p udp -m state --state NEW -m udp --dport $((server_port + 1)) -j ACCEPT"
    )
    FIREWALL_RULES_ADDED=false
    for RULE in "${RULES[@]}"; do
        # shellcheck disable=SC2086 # We need the variable to be split
        if ! sudo iptables -C ${RULE} 2>/dev/null; then
            # shellcheck disable=SC2086 # We need the variable to be split
            sudo iptables -I ${RULE}
            FIREWALL_RULES_ADDED=true
        fi
    done
    if $FIREWALL_RULES_ADDED; then
        sudo install -d -m 0755 /etc/iptables
        if [[ -f /etc/iptables/rules.v4 ]]; then
            sudo cp /etc/iptables/rules.v4 /etc/iptables/rules.v4.bak
        fi

        TMP_FILE=$(mktemp)
        sudo iptables-save | sudo tee "${TMP_FILE}" >/dev/null
        sudo install -m 0644 "${TMP_FILE}" /etc/iptables/rules.v4
        rm -f -- "${TMP_FILE}"
        sudo systemctl enable netfilter-persistent.service >/dev/null 2>&1 || true
    fi
    success "Done"
}

function install_valheim_server_helper() {
    info "Creating Valheim Server helper"
    mkdir -p /usr/sbin
    cat <<-EOF | sudo tee /usr/sbin/valheim_server >/dev/null
		#!/bin/bash

		# Stop on error
		set -e

		function show_usage {
		    echo "Usage:  \$(basename \$0) COMMAND"
		    echo
		    echo "Commands:"
		    echo "  update      Backs up, stops and updates the Valheim server"
		    echo "  backup      Stops briefly and creates a full save backup"
		    echo "  start       Start the Valheim server"
		    echo "  stop        Stops the Valheim server"
		    echo "  restart     Restart the Valheim server"
		    echo "  logs        Shows the logs of the Valheim server"
		    echo "  logs-live   Shows the live logs of the Valheim server"
		    echo "  help        Shows this help message"
		    echo
		}

		function start_server {
		    if ! systemctl --user --quiet is-active valheim_server; then
		        echo "Starting Server..."
		        systemctl --user start valheim_server

		        sleep 2     # sleeping to allow service to start up before validating.

		        systemctl --user --quiet is-active valheim_server && \
		            echo "Server Started"
		    else
		        echo "Server already running"
		    fi
		}

		function stop_server {
		    if systemctl --user --quiet is-active valheim_server; then
		        echo "Stopping Server, please wait..."
		        systemctl --user stop valheim_server
		        echo "Server Stopped"
		    else
		        echo "Server already stopped"
		    fi
		}

		function restart_server {
		    stop_server && start_server
		}

		function create_backup {
		    mkdir -p "${SERVER_HOME}/valheim_data" "${SERVER_HOME}/valheim_backups"
		    local archive="${SERVER_HOME}/valheim_backups/valheim_data-\$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
		    tar --create --gzip --file="\${archive}" --directory="${SERVER_HOME}" valheim_data
		    echo "Backup created: \${archive}"
		}

		function backup_server {
		    local was_active=false

		    if systemctl --user --quiet is-active valheim_server; then
		        was_active=true
		        stop_server
		    fi
		    if ! create_backup; then
		        if \${was_active}; then
		            start_server
		        fi
		        return 1
		    fi
		    if \${was_active}; then
		        start_server
		    fi
		}

		function update_server {
		    local was_active=false
		    if systemctl --user --quiet is-active valheim_server; then
		        was_active=true
		        stop_server
		    fi
		    # Valheim 1.0 worlds are directories containing many files.  Archive
		    # the complete save root before updating instead of copying .db/.fwl.
		    if ! create_backup; then
		        if \${was_active}; then
		            start_server
		        fi
		        return 1
		    fi

		    if ! STEAM_PLATFORM=${STEAM_PLATFORM} "${SERVER_HOME}/steamcmd/steamcmd.sh" \\
		        +@sSteamCmdForcePlatformType linux \\
		        +force_install_dir "${SERVER_HOME}/valheim_server" \\
		        +login anonymous \\
		        +app_update 896660 validate \\
		        +quit; then
		        if \${was_active}; then
		            start_server
		        fi
		        return 1
		    fi
		    echo
		    echo "Server updated."
		    echo "Start the server with \"valheim_server start\""
		}


		case \$1 in
		    update)
		        update_server;;
		    backup)
		        backup_server;;

		    start|stop|restart)
		        \${1}_server;;
		    logs)
		        journalctl --user -u valheim_server;;
		    logs-live)
		        journalctl --user -f -u valheim_server;;
		    help|--help|-h|*)
		        show_usage;;
		esac
	EOF
    sudo chmod +x /usr/sbin/valheim_server
}

function install_server_script() {
    info "Setting up Server script"

    if [[ ! -f $SERVER_SCRIPT_PATH ]]; then
        cat <<-EOF >"${SERVER_SCRIPT_PATH}"
			#!/bin/bash

			# This script was generated by \`setup_valheim_server.sh\` and serves the purpose of starting the Valheim dedicated server.
			# If this startup script stops working, please rename it and re-run the setup script, this will regenerate it.

			SERVER_DIR="${SERVER_HOME}/valheim_server"
			SAVE_DIR="${SERVER_HOME}/valheim_data"

			cd "\${SERVER_DIR}"

			export LD_LIBRARY_PATH=./linux64:\$LD_LIBRARY_PATH

			# Valheim 1.0 saves worlds as directories containing chunk files and metadata.
			# Keep the complete SAVE_DIR together when backing up or migrating worlds.
			launch_args=(
			    -nographics
			    -batchmode
			    -port        "\${PORT}"
			    -public      "\${PUBLIC}"
			    -name        "\${SERVER_NAME}"
			    -world       "\${WORLD_NAME}"
			    -password    "\${PASSWORD}"
			    -savedir     "\${SAVE_DIR}"
			    -saveinterval "\${SAVE_INTERVAL:-1800}"
			    -backups     "\${BACKUPS:-4}"
			    -backupshort "\${BACKUP_SHORT:-7200}"
			    -backuplong  "\${BACKUP_LONG:-43200}"
			)

			if [[ \${CROSSPLAY:-0} == 1 ]]; then
			    launch_args+=( -crossplay )
			fi

			exec "\${SERVER_DIR}/valheim_server.x86_64" "\${launch_args[@]}"

			# More flags can be found at:
			# https://www.valheimgame.com/support/a-guide-to-dedicated-servers/#:~:text=List%20of%20console%20commands
		EOF
    else
        notify "Already exists, skipping"
    fi

    chmod +x "${SERVER_SCRIPT_PATH}"
}

function install_systemd_service() {
    info "Setting up Systemd Service"
    mkdir -p "${SERVER_HOME}/.config/systemd/user/"

    cat <<-EOF >"${SERVER_HOME}/.config/systemd/user/valheim_server.service"
		[Unit]
		Description=Valheim Dedicated Server

		[Service]
		KillSignal=SIGINT
		TimeoutStopSec=30

		Restart=always
		RestartSec=5

		WorkingDirectory=${SERVER_HOME}/valheim_server
		EnvironmentFile=${SERVER_HOME}/server_credentials

		Environment=SteamAppId=892970

		ExecStart=$SERVER_SCRIPT_PATH

		[Install]
		WantedBy=default.target
	EOF

    # Reload Systemd
    systemctl --user daemon-reload

    # Enable Valheim Systemd service allowing it to start automatically on boot
    systemctl --user enable valheim_server.service
    success "Setting up Systemd Service - Done"
}

function install_readmefile() {
    info "Creating Readme"
    cat <<-EOF >"${SERVER_HOME}/Readme.md"
		# Valheim Server Helper Commands
		## Help
		valheim_server help

		## Start server
		valheim_server start

		## Stop server
		valheim_server stop

		## Updating the server
		valheim_server update

		## Creating a full save backup
		valheim_server backup
		# Backups are stored under ~/valheim_backups.

		# Enable / Disable crossplay
		Edit CROSSPLAY in ~/server_credentials: 1 enables crossplay, 0 disables it.
	EOF
    success "Creating Readme - Done"
}

function main {
    # Stop on error
    set -e

    if [[ $ID != ubuntu ]] || [[ $VERSION_ID != 22.04 && $VERSION_ID != 24.04 && $VERSION_ID != 26.04 ]]; then
        error "The release \"$PRETTY_NAME\" is not supported. Use Ubuntu 22.04, 24.04, or 26.04 LTS."
        echo "See https://github.com/husjon/valheim_server_oci_setup?tab=readme-ov-file#ubuntu-version for more information"
        echo
        exit 1
    fi

    if [[ $USE_BOX = true ]]; then
        if [[ $VERSION_ID != 22.04 ]]; then
            error "Box86/Box64 is only supported here on Ubuntu 22.04; use the default FEX emulator on $PRETTY_NAME."
            echo "See https://github.com/husjon/valheim_server_oci_setup?tab=readme-ov-file#ubuntu-version for more information"
            echo
            exit 1
        fi
    fi

    cd "${SERVER_HOME}"

    while :; do
        echo "This script will install the Valheim Dedicated server "
        echo -n "Are you sure? [yes/no]  "

        read -r answer

        case $answer in
        YES | Yes | yes | y)
            break
            ;;
        NO | No | no | n)
            echo Aborting
            exit
            ;;
        esac
    done
    echo

    # Update and upgrade the system
    initial_setup

    # Only install Box or FEX if on ARM
    if is_arm64; then
        # Prepare x86_64 emulation
        if [[ $USE_BOX == true ]]; then
            install_box86_and_box64
        else
            install_fex_emu
        fi
    fi

    # Fetch and initialize steamcmd
    install_steamcmd

    # Install the Valheim Dedicated Server from Steam
    install_valheim_dedicated_server

    # Initialize the Server Credentials file
    if [[ ! -f "${SERVER_HOME}/server_credentials" ]]; then
        info "Generating server_credentials file"
        PASSWORD="$(tr -dc "a-zA-Z0-9" </dev/urandom | fold -w "32" | head -n 1)"
        CROSSPLAY_DEFAULT=0
        [[ $CROSSPLAY_SUPPORT == true ]] && CROSSPLAY_DEFAULT=1
        cat <<-EOF >"${SERVER_HOME}/server_credentials"
			SERVER_NAME="My server"
			WORLD_NAME="My World"

			# NOTE: Minimum password length is 5 characters & Password cant be in the server name.
			PASSWORD="${PASSWORD}"

			# If the server should be listed publically. (1=yes, 0=no)
			PUBLIC=0

			PORT=2456

			# Valheim 1.0 save and automatic backup settings
			SAVE_INTERVAL=1800
			BACKUPS=4
			BACKUP_SHORT=7200
			BACKUP_LONG=43200

			# Crossplay backend (1=yes, 0=no)
			CROSSPLAY=${CROSSPLAY_DEFAULT}
		EOF
        success "Generating server_credentials file - Done"
    fi

    # Keep older credentials files compatible with the new generated launcher.
    if ! grep -q '^CROSSPLAY=' "${SERVER_HOME}/server_credentials"; then
        CROSSPLAY_DEFAULT=0
        [[ $CROSSPLAY_SUPPORT == true ]] && CROSSPLAY_DEFAULT=1
        echo "CROSSPLAY=${CROSSPLAY_DEFAULT}" >>"${SERVER_HOME}/server_credentials"
    fi

    # The FEX RootFS contains the x86_64 library needed by crossplay; this
    # avoids pinning the installer to a removed Ubuntu 22.04 package URL.
    install_crossplay_library

    # Update firewall
    update_firewall

    # Add Valheim helper
    install_valheim_server_helper

    # Add Valheim script
    install_server_script

    # Set up the Systemd Service
    install_systemd_service

    # Enable Lingering Systemd user sessions
    loginctl enable-linger "${CURRENT_USER}"

    # Create Readme.md file in home directory
    install_readmefile

    # Start the Valheim Systemd service
    success "Setup finished"
    echo "A file named 'server_credentials' have been placed in the home directory"
    echo "Edit as you see fit with f.ex 'nano ~/server_credentials'"
    echo "Within nano, when done editing, press 'Ctrl+X', then 'y', finally 'Enter'"
    echo
    echo "Finally, to start the server, the following command can be used:"
    echo "  valheim_server start"
    echo
    echo "A readme with additional commands have also been placed in the home directory"
}

if [ "$(id -u)" -eq 0 ]; then
    error Please run this script as a regular user.

    exit 1
fi

perform_self_update

# Pinned versions for Box 64 / 86
BOX64_VERSION="${BOX64_VERSION:-v0.2.6}"
BOX86_VERSION="${BOX86_VERSION:-1e749beb2e84401344337b2f3865f156a667d946}"

main | tee install_valheim_server.log

# vim: sw=4 ts=4
