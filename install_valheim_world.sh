#!/bin/bash

set -e
set -o pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SERVER_HOME="${HOME}"
readonly CREDENTIALS_FILE="${SERVER_HOME}/server_credentials"
readonly SERVER_SCRIPT_PATH="${SERVER_HOME}/valheim_server/start_server.custom.sh"

SAVE_DIR="${VALHEIM_SAVE_DIR:-${SERVER_HOME}/valheim_data}"
WORLD_DIR="${SAVE_DIR}/worlds_local"

REPLACE_EXISTING=false
NO_START=false
ZIP_FILE=""
WORLD_NAME=""

TMP_DIR=""
INSTALL_DIR=""
CREDENTIALS_BACKUP=""
WAS_ACTIVE=false
IMPORT_SUCCEEDED=false
WORLD_FORMAT=""
MEANINGFUL_ENTRIES=()

declare -a OLD_PATHS=()
declare -a ORIGINAL_PATHS=()
declare -a NEW_PATHS=()

error() {
    printf 'ERROR: %s\n' "$*" >&2
}

info() {
    printf '%s\n' "$*"
}

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [--replace] [--no-start] WORLD.zip [WORLD_NAME]

Import a Valheim world from a zip archive into ${WORLD_DIR}.

The archive may contain either:
  * a Valheim 1.0 world directory; or
  * a legacy matching WORLD.db and WORLD.fwl pair.

Options:
  --replace   Replace an existing world with the same name.
  --no-start  Leave the server stopped if it was running before import.
  -h, --help  Show this help.

If WORLD_NAME is omitted, it is taken from the archive's world directory,
legacy file names, or (for a flat 1.0 archive) the zip file name.
EOF
}

cleanup() {
    local exit_code=$?

    if [[ "${IMPORT_SUCCEEDED}" != true ]]; then
        if [[ -n "${CREDENTIALS_BACKUP}" && -f "${CREDENTIALS_BACKUP}" && -f "${CREDENTIALS_FILE}" ]]; then
            cp -- "${CREDENTIALS_BACKUP}" "${CREDENTIALS_FILE}" || true
        fi

        local index
        for index in "${!NEW_PATHS[@]}"; do
            if [[ -e "${NEW_PATHS[index]}" || -L "${NEW_PATHS[index]}" ]]; then
                rm -rf -- "${NEW_PATHS[index]}" || true
            fi
        done

        for index in "${!OLD_PATHS[@]}"; do
            if [[ -e "${OLD_PATHS[index]}" || -L "${OLD_PATHS[index]}" ]]; then
                mv -- "${OLD_PATHS[index]}" "${ORIGINAL_PATHS[index]}" || true
            fi
        done

        if [[ "${WAS_ACTIVE}" == true ]]; then
            info "Import failed; restoring the previously running server."
            valheim_server start || true
        fi
    else
        local index
        for index in "${!OLD_PATHS[@]}"; do
            if [[ -e "${OLD_PATHS[index]}" || -L "${OLD_PATHS[index]}" ]]; then
                rm -rf -- "${OLD_PATHS[index]}" || true
            fi
        done

        if [[ "${WAS_ACTIVE}" == true && "${NO_START}" != true ]]; then
            info "Starting Valheim server."
            valheim_server start || true
        fi
    fi

    if [[ -n "${CREDENTIALS_BACKUP}" ]]; then
        rm -f -- "${CREDENTIALS_BACKUP}" || true
    fi
    if [[ -n "${INSTALL_DIR}" && -d "${INSTALL_DIR}" ]]; then
        rm -rf -- "${INSTALL_DIR}" || true
    fi
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf -- "${TMP_DIR}" || true
    fi

    exit "${exit_code}"
}

trap cleanup EXIT

validate_world_name() {
    local name="$1"

    if [[ -z "${name}" || "${name}" == "." || "${name}" == ".." || "${name}" == *[/:\\\"]* ]]; then
        error "Invalid world name '${name}'. Use a single directory/file-safe name."
        exit 1
    fi
    if [[ "${name}" == *$'\n'* || "${name}" == *$'\r'* || "${name}" == *$'\t'* ]]; then
        error "World name must not contain control characters."
        exit 1
    fi
}

parse_args() {
    local -a positional=()

    while (($# > 0)); do
        case "$1" in
            --replace)
                REPLACE_EXISTING=true
                ;;
            --no-start)
                NO_START=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                while (($# > 0)); do
                    positional+=("$1")
                    shift
                done
                break
                ;;
            -* )
                error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
            *)
                positional+=("$1")
                ;;
        esac
        shift
    done

    if ((${#positional[@]} > 2)); then
        error "Too many positional arguments."
        usage >&2
        exit 1
    fi

    ZIP_FILE="${positional[0]:-}"
    WORLD_NAME="${positional[1]:-}"

    if [[ -z "${ZIP_FILE}" ]]; then
        error "A .zip world archive is required."
        usage >&2
        exit 1
    fi
}

require_commands() {
    local command_name

    for command_name in unzip find mktemp realpath awk cp mv rm systemctl valheim_server grep sort chmod mkdir basename; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            error "Required command '${command_name}' was not found. Run the server setup first."
            exit 1
        fi
    done
}

resolve_save_dir() {
    local configured_save_dir="${VALHEIM_SAVE_DIR:-}"
    local launcher_save_dir=""

    if [[ -z "${configured_save_dir}" && -f "${SERVER_SCRIPT_PATH}" ]]; then
        # Do not source the launcher: it is user-editable and executes the
        # server. Read only its SAVE_DIR assignment instead.
        launcher_save_dir="$(awk -v home="${SERVER_HOME}" '
            /^[[:space:]]*(export[[:space:]]+)?SAVE_DIR=/ {
                value = $0
                sub(/^[[:space:]]*(export[[:space:]]+)?SAVE_DIR=[[:space:]]*/, "", value)
                sub(/[[:space:]]+#.*$/, "", value)
                if (value ~ /^"/) {
                    sub(/^"/, "", value)
                    sub(/"[[:space:]]*$/, "", value)
                } else {
                    sub(/[[:space:]]+$/, "", value)
                }
                gsub(/\$\{HOME\}|\$HOME|\$\{SERVER_HOME\}|\$SERVER_HOME/, home, value)
                latest = value
            }
            END { print latest }
        ' "${SERVER_SCRIPT_PATH}")"
        if [[ -n "${launcher_save_dir}" ]]; then
            configured_save_dir="${launcher_save_dir}"
        fi
    fi

    if [[ -z "${configured_save_dir}" ]]; then
        configured_save_dir="${SERVER_HOME}/valheim_data"
    fi
    if [[ "${configured_save_dir}" != /* ]]; then
        error "The configured Valheim save directory must be an absolute path: ${configured_save_dir}"
        exit 1
    fi

    SAVE_DIR="${configured_save_dir%/}"
    WORLD_DIR="${SAVE_DIR}/worlds_local"
}

validate_archive_entries() {
    local archive_entries="$1"
    local entry

    while IFS= read -r entry; do
        case "${entry}" in
            /*|..|../*|*/../*|*/..|*\\*)
                error "Unsafe archive entry rejected: ${entry}"
                exit 1
                ;;
        esac
    done < "${archive_entries}"
}

meaningful_entries() {
    local directory="$1"

    find "${directory}" -mindepth 1 -maxdepth 1 \
        ! -name '__MACOSX' \
        ! -name '.DS_Store' \
        -print | sort
}

read_meaningful_entries() {
    local directory="$1"
    local entry

    MEANINGFUL_ENTRIES=()
    while IFS= read -r entry; do
        MEANINGFUL_ENTRIES+=("${entry}")
    done < <(meaningful_entries "${directory}")
}

prepare_source_directory() {
    local extracted_dir="$1"
    local -a entries=()
    local -a nested_entries=()

    read_meaningful_entries "${extracted_dir}"
    entries=("${MEANINGFUL_ENTRIES[@]}")
    if ((${#entries[@]} == 0)); then
        error "The archive does not contain any world files."
        exit 1
    fi

    SOURCE_DIR="${extracted_dir}"
    if ((${#entries[@]} == 1)) && [[ -d "${entries[0]}" ]]; then
        SOURCE_DIR="${entries[0]}"
        read_meaningful_entries "${SOURCE_DIR}"
        nested_entries=("${MEANINGFUL_ENTRIES[@]}")
        if ((${#nested_entries[@]} == 1)) && [[ -d "${nested_entries[0]}" ]]; then
            SOURCE_DIR="${nested_entries[0]}"
        fi
    elif ((${#entries[@]} > 1)); then
        local directory_count=0
        local entry
        for entry in "${entries[@]}"; do
            if [[ -d "${entry}" ]]; then
                ((directory_count += 1))
            fi
        done
        if ((directory_count > 0)); then
            error "The archive contains multiple top-level entries; provide one world per zip."
            exit 1
        fi
    fi
}

detect_world_format() {
    local -a db_files=()
    local -a fwl_files=()
    local db_base
    local fwl_base

    shopt -s nullglob
    db_files=("${SOURCE_DIR}"/*.db)
    fwl_files=("${SOURCE_DIR}"/*.fwl)
    shopt -u nullglob

    if ((${#db_files[@]} == 1 && ${#fwl_files[@]} == 1)); then
        db_base="$(basename "${db_files[0]}" .db)"
        fwl_base="$(basename "${fwl_files[0]}" .fwl)"
        if [[ "${db_base}" == "${fwl_base}" ]]; then
            WORLD_FORMAT="legacy"
            if [[ -z "${WORLD_NAME}" ]]; then
                WORLD_NAME="${db_base}"
            fi
            LEGACY_DB="${db_files[0]}"
            LEGACY_FWL="${fwl_files[0]}"
            return
        fi
    fi

    if ! find "${SOURCE_DIR}" -type f -print -quit | grep -q .; then
        error "The archive does not contain any regular world files."
        exit 1
    fi

    WORLD_FORMAT="folder"
    if [[ -z "${WORLD_NAME}" ]]; then
        if [[ "${SOURCE_DIR}" != "${TMP_DIR}/extracted" ]]; then
            WORLD_NAME="$(basename "${SOURCE_DIR}")"
        else
            WORLD_NAME="$(basename "${ZIP_FILE}")"
            WORLD_NAME="${WORLD_NAME%.zip}"
            WORLD_NAME="${WORLD_NAME%.ZIP}"
        fi
    fi
}

check_existing_world() {
    local folder_target="${WORLD_DIR}/${WORLD_NAME}"
    local db_target="${WORLD_DIR}/${WORLD_NAME}.db"
    local fwl_target="${WORLD_DIR}/${WORLD_NAME}.fwl"

    if [[ -e "${folder_target}" || -L "${folder_target}" || -e "${db_target}" || -L "${db_target}" || -e "${fwl_target}" || -L "${fwl_target}" ]]; then
        if [[ "${REPLACE_EXISTING}" != true ]]; then
            error "World '${WORLD_NAME}' already exists. Re-run with --replace to replace it."
            exit 1
        fi
    fi
}

update_credentials() {
    local credentials_tmp

    CREDENTIALS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/valheim-credentials.XXXXXX")"
    cp -- "${CREDENTIALS_FILE}" "${CREDENTIALS_BACKUP}"
    credentials_tmp="$(mktemp "${TMPDIR:-/tmp}/valheim-credentials-new.XXXXXX")"

    awk -v world_name="${WORLD_NAME}" '
        BEGIN { replacement = "WORLD_NAME=\"" world_name "\"" }
        /^WORLD_NAME=/ { print replacement; found = 1; next }
        { print }
        END { if (!found) print replacement }
    ' "${CREDENTIALS_FILE}" > "${credentials_tmp}"

    chmod --reference="${CREDENTIALS_FILE}" "${credentials_tmp}" 2>/dev/null || true
    mv -- "${credentials_tmp}" "${CREDENTIALS_FILE}"
}

stage_world() {
    local staged_path

    move_existing() {
        local original_path="$1"
        local backup_path="$2"

        if [[ -e "${original_path}" || -L "${original_path}" ]]; then
            OLD_PATHS+=("${backup_path}")
            ORIGINAL_PATHS+=("${original_path}")
            mv -- "${original_path}" "${backup_path}"
        fi
    }

    mkdir -p -- "${WORLD_DIR}"
    INSTALL_DIR="$(mktemp -d "${WORLD_DIR}/.import.XXXXXX")"

    if [[ "${WORLD_FORMAT}" == "folder" ]]; then
        staged_path="${INSTALL_DIR}/${WORLD_NAME}"
        mkdir -p -- "${staged_path}"
        cp -a -- "${SOURCE_DIR}/." "${staged_path}/"
        NEW_PATHS+=("${WORLD_DIR}/${WORLD_NAME}")
        move_existing "${WORLD_DIR}/${WORLD_NAME}" "${INSTALL_DIR}/previous-world"
        move_existing "${WORLD_DIR}/${WORLD_NAME}.db" "${INSTALL_DIR}/previous-${WORLD_NAME}.db"
        move_existing "${WORLD_DIR}/${WORLD_NAME}.fwl" "${INSTALL_DIR}/previous-${WORLD_NAME}.fwl"
        mv -- "${staged_path}" "${WORLD_DIR}/${WORLD_NAME}"
    else
        cp -a -- "${LEGACY_DB}" "${INSTALL_DIR}/${WORLD_NAME}.db"
        cp -a -- "${LEGACY_FWL}" "${INSTALL_DIR}/${WORLD_NAME}.fwl"

        NEW_PATHS+=("${WORLD_DIR}/${WORLD_NAME}.db" "${WORLD_DIR}/${WORLD_NAME}.fwl")
        move_existing "${WORLD_DIR}/${WORLD_NAME}" "${INSTALL_DIR}/previous-world"
        move_existing "${WORLD_DIR}/${WORLD_NAME}.db" "${INSTALL_DIR}/previous-${WORLD_NAME}.db"
        move_existing "${WORLD_DIR}/${WORLD_NAME}.fwl" "${INSTALL_DIR}/previous-${WORLD_NAME}.fwl"
        mv -- "${INSTALL_DIR}/${WORLD_NAME}.db" "${WORLD_DIR}/${WORLD_NAME}.db"
        mv -- "${INSTALL_DIR}/${WORLD_NAME}.fwl" "${WORLD_DIR}/${WORLD_NAME}.fwl"
    fi
}

parse_args "$@"

if [[ "${EUID}" -eq 0 ]]; then
    error "Run this script as the server user, not root."
    exit 1
fi

require_commands
resolve_save_dir

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    error "${CREDENTIALS_FILE} was not found. Run setup_valheim_server.sh first."
    exit 1
fi

if [[ ! -d "${SAVE_DIR}" ]]; then
    info "Creating Valheim save directory: ${SAVE_DIR}"
    mkdir -p -- "${WORLD_DIR}"
fi

if [[ ! -f "${ZIP_FILE}" ]]; then
    error "Zip archive not found: ${ZIP_FILE}"
    exit 1
fi

ZIP_FILE="$(realpath -- "${ZIP_FILE}")"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/valheim-world.XXXXXX")"
EXTRACT_DIR="${TMP_DIR}/extracted"
mkdir -p -- "${EXTRACT_DIR}"

if ! unzip -tqq -- "${ZIP_FILE}"; then
    error "The archive failed zip integrity checks: ${ZIP_FILE}"
    exit 1
fi

unzip -Z1 -- "${ZIP_FILE}" > "${TMP_DIR}/entries"
validate_archive_entries "${TMP_DIR}/entries"
unzip -q -- "${ZIP_FILE}" -d "${EXTRACT_DIR}"

if find "${EXTRACT_DIR}" -type l -print -quit | grep -q .; then
    error "Symlinks are not allowed in world archives."
    exit 1
fi

rm -rf -- "${EXTRACT_DIR}/__MACOSX" "${EXTRACT_DIR}/.DS_Store"
find "${EXTRACT_DIR}" -type f -name '.DS_Store' -delete

prepare_source_directory "${EXTRACT_DIR}"
detect_world_format
validate_world_name "${WORLD_NAME}"
check_existing_world

if [[ "${WORLD_FORMAT}" == "folder" ]]; then
    info "Detected Valheim 1.0 world directory '${WORLD_NAME}'."
else
    info "Detected legacy .db/.fwl world '${WORLD_NAME}'."
fi

if systemctl --user --quiet is-active valheim_server; then
    WAS_ACTIVE=true
fi

info "Creating a full save backup before importing."
valheim_server backup
valheim_server stop

update_credentials
stage_world

IMPORT_SUCCEEDED=true
if [[ "${WAS_ACTIVE}" == true && "${NO_START}" == true ]]; then
    info "World imported. The server was running before import and is left stopped by request."
else
    info "World '${WORLD_NAME}' imported successfully."
fi
