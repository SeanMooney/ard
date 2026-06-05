#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=${DRY_RUN:-0}
SKIP_PACKAGES=${SKIP_PACKAGES:-0}
SKIP_UV_INSTALL=${SKIP_UV_INSTALL:-0}
SKIP_SUBMODULES=${SKIP_SUBMODULES:-0}

log() {
    printf '==> %s\n' "$*"
}

run() {
    if [[ "${DRY_RUN}" == "1" ]]; then
        printf '+ %q' "$1"
        shift || true
        for arg in "$@"; do
            printf ' %q' "$arg"
        done
        printf '\n'
    else
        "$@"
    fi
}

have() {
    command -v "$1" >/dev/null 2>&1
}

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "Required file not found: $1" >&2
        exit 1
    fi
}

source_os_release() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
    else
        echo "Cannot detect host OS: /etc/os-release is missing" >&2
        exit 1
    fi
}

select_package_manager() {
    source_os_release
    if have apt-get; then
        PACKAGE_MANAGER=apt
    elif have dnf; then
        PACKAGE_MANAGER=dnf
    else
        echo "Unsupported host: expected apt-get or dnf" >&2
        exit 1
    fi
    log "Detected ${PRETTY_NAME:-${ID:-unknown}} using ${PACKAGE_MANAGER}"
}

install_minimal_bootstrap_packages() {
    [[ "${SKIP_PACKAGES}" == "1" ]] && return 0

    case "${PACKAGE_MANAGER}" in
        apt)
            run sudo apt-get update
            run sudo apt-get install -y python3 python3-pip curl ca-certificates
            ;;
        dnf)
            run sudo dnf -y --setopt=install_weak_deps=False install \
                python3 python3-pip curl ca-certificates
            ;;
    esac
}

ensure_uv() {
    if have uv; then
        log "uv is already available: $(command -v uv)"
        return 0
    fi

    if [[ "${SKIP_UV_INSTALL}" == "1" ]]; then
        echo "uv is not available and SKIP_UV_INSTALL=1 was set" >&2
        exit 1
    fi

    log "Installing uv"
    if [[ "${DRY_RUN}" == "1" ]]; then
        echo '+ curl -LsSf https://astral.sh/uv/install.sh | sh'
    else
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    export PATH="${HOME}/.local/bin:${PATH}"
    if ! have uv; then
        echo "uv installation completed but uv is not on PATH" >&2
        echo "Add ${HOME}/.local/bin to PATH and re-run this script." >&2
        exit 1
    fi
}

install_bindep_packages() {
    [[ "${SKIP_PACKAGES}" == "1" ]] && return 0
    require_file bindep.txt

    log "Resolving OS packages with bindep"
    if [[ "${DRY_RUN}" == "1" ]]; then
        echo '+ uvx --from bindep bindep -b'
        echo '+ sudo <package-manager> install $(uvx --from bindep bindep -b)'
        return 0
    fi

    mapfile -t packages < <(uvx --from bindep bindep -b)
    if [[ ${#packages[@]} -eq 0 ]]; then
        log "bindep reported no missing binary packages"
        return 0
    fi

    log "Installing ${#packages[@]} bindep package(s): ${packages[*]}"
    case "${PACKAGE_MANAGER}" in
        apt)
            sudo apt-get update
            sudo apt-get install -y "${packages[@]}"
            ;;
        dnf)
            sudo dnf -y --setopt=install_weak_deps=False install "${packages[@]}"
            ;;
    esac
}

sync_python_environment() {
    log "Syncing uv environment"
    run uv sync
}

sync_submodules() {
    [[ "${SKIP_SUBMODULES}" == "1" ]] && return 0
    log "Updating git submodules"
    run git submodule update --init --recursive
}

check_command() {
    if have "$1"; then
        log "Found $1: $(command -v "$1")"
    else
        echo "Missing required command: $1" >&2
        return 1
    fi
}

check_local_libvirt() {
    log "Checking local ARD/libvirt commands"
    check_command virsh
    check_command qemu-img
    check_command cloud-localds
    check_command setfacl

    if [[ "${DRY_RUN}" != "1" ]]; then
        if virsh --connect qemu:///system uri >/dev/null 2>&1; then
            log "libvirt qemu:///system is reachable"
        else
            echo "WARNING: libvirt qemu:///system is not reachable by this user." >&2
        fi
    fi

    if groups | grep -Eq '(^| )(libvirt|qemu)( |$)'; then
        log "Current user appears to be in a libvirt/qemu access group"
    else
        cat >&2 <<EOF
WARNING: Current user is not in a libvirt/qemu access group.
You may need one of:

  sudo usermod -a -G libvirt ${USER}
  sudo usermod -a -G qemu ${USER}

Then log out and back in, or use newgrp for the relevant group.
EOF
    fi
}

main() {
    cd "$(dirname "$0")"
    select_package_manager
    install_minimal_bootstrap_packages
    ensure_uv
    install_bindep_packages
    sync_python_environment
    sync_submodules
    check_local_libvirt
    log "Bootstrap complete"
}

main "$@"
