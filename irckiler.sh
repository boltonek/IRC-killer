#!/bin/bash
# IRC Killer - Script for terminating IRC processes
# Splits handling between IPv4 and IPv6, works via lsof
# Locks account after exceeding the limit n times
# Records statistics and writes logs
# Version: IRC Killer v2

set -euo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

# Number of violations before the account gets locked
BLOCK_AFTER=3

# Statistics file path
STATS_FILE="/usr/src/ircKiller/irc_killer"

# ============================================================
# DEFAULT VARIABLE VALUES
# ============================================================
DEBUG="NO"
DB="/dev/null"
LOG_FILE="/dev/null"

# ============================================================
# BANNER
# ============================================================
cat << 'EOF'
 __   .__.__  .__
 |  | _|__|  | |  |   ___________
 |  |/ /  |  | |  | _/ __ \_  __ \
 |    <|  |  |_|  |_\  ___/|  | \/
 |__|_ \__|____/____/\___  >__|
      \/                 \/
EOF

# ============================================================
# FUNCTIONS
# ============================================================

# If DEBUG == YES, print the message to stdout
debug() {
    if [[ "$DEBUG" == "YES" ]]; then
        printf "Processes -> %s\n" "$1"
    fi
}

# Write a timestamped message to the log file
log() {
    local TIMESTAMP
    TIMESTAMP=$(date "+%x %X")
    if ! echo "$TIMESTAMP $1" >> "$LOG_FILE" 2>/dev/null; then
        printf "Error: Cannot write to log file!\n" >&2
        exit 1
    fi
}

# Add user to statistics; lock account if violation limit is exceeded
record_stats() {
    local USER="$1"
    local TMP
    TMP=$(mktemp)

    # Append user to the statistics file
    if ! echo "$USER" >> "$STATS_FILE" 2>/dev/null; then
        printf "Error: Cannot write to statistics file! (Permission problem?)\n" >&2
        rm -f "$TMP"
        exit 1
    fi

    # Check how many times this user has violated the limit
    local COUNT
    COUNT=$(grep -wc "$USER" "$STATS_FILE" || true)

    if (( COUNT > BLOCK_AFTER )); then
        debug "\"$USER\" locked for repeatedly exceeding IRC process limits."
        log "\"$USER\" locked for repeatedly exceeding IRC process limits."

        # Remove user from statistics file
        grep -wv "$USER" "$STATS_FILE" > "$TMP" || true
        mv "$TMP" "$STATS_FILE"

        # Lock the user's login shell
        if ! chsh -s /bin/false "$USER" 2>/dev/null; then
            log "Warning: Failed to lock shell for \"$USER\"."
        fi
    else
        rm -f "$TMP"
    fi
}

# Clean up temporary files on script exit
cleanup() {
    [[ -n "${TMP_FILE:-}" && -f "$TMP_FILE" ]] && rm -f "$TMP_FILE"
}
trap cleanup EXIT

# ============================================================
# ARGUMENT PARSING
# ============================================================

usage() {
    printf "Usage: %s [-d] users.db log_file.txt\n" "$0"
    printf "Database format:\n\tuser1:max_v4:max_v6\n\tuser2:max_v4:max_v6\n"
    exit 1
}

if (( $# < 2 || $# > 3 )); then
    usage
fi

if [[ "$1" == "-d" ]]; then
    if (( $# != 3 )); then
        usage
    fi
    DEBUG="YES"
    shift
elif (( $# == 3 )); then
    printf "Error: Unknown argument \"%s\"!\n" "$1" >&2
    usage
fi

DB="$1"
LOG_FILE="$2"

# Check that the database file exists
if [[ ! -f "$DB" ]]; then
    printf "Error: Database file \"%s\" does not exist!\n" "$DB" >&2
    exit 1
fi

# Create the statistics file if it doesn't exist yet
if [[ ! -f "$STATS_FILE" ]]; then
    mkdir -p "$(dirname "$STATS_FILE")"
    touch "$STATS_FILE"
fi

# ============================================================
# COLLECT ACTIVE IRC CONNECTIONS (TCP ports 6660-6669)
# ============================================================

TMP_FILE=$(mktemp)

if ! lsof -n -iTCP:6660-6669 2>/dev/null | awk '{ print $3, $5, $8 }' > "$TMP_FILE"; then
    printf "Error: Problem with lsof or writing to temporary file.\n" >&2
    exit 1
fi

# ============================================================
# MAIN LOOP: check process limits for each user
# ============================================================

while IFS=: read -r USER MAX_V4 MAX_V6; do
    # Skip empty lines and comments
    [[ -z "$USER" || "$USER" == \#* ]] && continue

    # Count active IRC processes
    ACTIVE_V4=$(grep -w "IPv4" "$TMP_FILE" | grep -wc "$USER" || true)
    ACTIVE_V6=$(grep -w "IPv6" "$TMP_FILE" | grep -wc "$USER" || true)

    debug "$(printf "\e[1;32m=>\e[0m%s\e[1;32m<=\e[0m\t\e[1;29mIPv4\e[0m:[ \e[1;31mMax\e[0m: \e[1;41m%s\e[0m -> \e[1;31mHas\e[0m: \e[1;41m%s\e[0m ]  \e[1;29mIPv6\e[0m:[ \e[1;31mMax\e[0m: \e[1;41m%s\e[0m -> \e[1;31mHas\e[0m: \e[1;41m%s\e[0m ]" \
        "$USER" "$MAX_V4" "$ACTIVE_V4" "$MAX_V6" "$ACTIVE_V6")"

    # Check IPv4 limit
    if (( ACTIVE_V4 > MAX_V4 )); then
        log "\"$USER\" exceeded IRC process limit for IPv4 by $(( ACTIVE_V4 - MAX_V4 ))"
        debug "\"$USER\" exceeded IRC process limit for IPv4 by $(( ACTIVE_V4 - MAX_V4 ))"
        record_stats "$USER"
        pkill -9 -u "$USER" || true

    # Check IPv6 limit
    elif (( ACTIVE_V6 > MAX_V6 )); then
        log "\"$USER\" exceeded IRC process limit for IPv6 by $(( ACTIVE_V6 - MAX_V6 ))"
        debug "\"$USER\" exceeded IRC process limit for IPv6 by $(( ACTIVE_V6 - MAX_V6 ))"
        record_stats "$USER"
        pkill -9 -u "$USER" || true
    fi

done < "$DB"
