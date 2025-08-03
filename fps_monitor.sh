#!/bin/bash

# FPS monitoring script for conky
# Reads MangoHUD log file to get current FPS
# Statistics are calculated over a 10-minute sliding window
# Usage: fps_monitor.sh [current|avg|min|max|game]

MANGOHUD_LOG="$HOME/.local/share/MangoHud/MangoHud.log"
STATS_FILE="/tmp/conky_fps_stats"
STAT_TYPE="${1:-current}"

# Function to get current game process
get_current_game() {
    # Look for common game processes
    local game_process=$(ps aux | grep -E "(steam|\.exe|wine|lutris|heroic)" | grep -v grep | grep -v "steam.sh" | grep -v "steamwebhelper" | head -1 | awk '{print $11}' | sed 's/.*\///')
    
    if [[ -n "$game_process" ]]; then
        echo "$game_process"
    else
        echo "No Game"
    fi
}

# Function to get FPS from MangoHUD log
get_mangohud_fps() {
    # Check for MangoHUD CSV files (newest first)
    local mangohud_csv=$(find /tmp/mangohud -name "*.csv" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [[ -f "$mangohud_csv" ]]; then
        # Get the most recent FPS reading from CSV (first column)
        local fps=$(tail -1 "$mangohud_csv" 2>/dev/null | cut -d',' -f1)
        if [[ -n "$fps" && $(echo "$fps > 0" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
            printf "%.0f" "$fps"
            return
        fi
    fi
    
    # Fallback: check traditional log locations
    local mangohud_logs=(
        "/tmp/mangohud/MangoHud.log"
        "$HOME/.local/share/MangoHud/MangoHud.log"
    )
    
    for log_file in "${mangohud_logs[@]}"; do
        if [[ -f "$log_file" ]]; then
            local fps=$(tail -5 "$log_file" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+|[0-9]+' | tail -1)
            if [[ -n "$fps" && $(echo "$fps > 0" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
                printf "%.0f" "$fps"
                return
            fi
        fi
    done
    
    echo "0"
}

# Alternative method: Check for gaming processes and estimate FPS
get_gaming_fps() {
    # Look for active gaming processes
    local gaming_processes=$(ps aux | grep -E "(steam.*app|\.exe|wine.*exe|lutris|heroic|gamescope)" | grep -v grep | grep -v "steamwebhelper" | wc -l)
    
    if [[ "$gaming_processes" -gt 0 ]]; then
        # If gaming process detected, try to get GPU usage as FPS indicator
        local gpu_util=$(/opt/rocm/bin/rocm-smi --showuse 2>/dev/null | grep 'GPU\[0\]' | awk -F': ' '{print $3}' | tr -d ' %' || echo "0")
        
        if [[ "$gpu_util" -gt 80 ]]; then
            echo "120" # Very high GPU usage
        elif [[ "$gpu_util" -gt 60 ]]; then
            echo "90" # High GPU usage
        elif [[ "$gpu_util" -gt 40 ]]; then
            echo "60" # Medium-high GPU usage
        elif [[ "$gpu_util" -gt 20 ]]; then
            echo "30" # Medium GPU usage
        elif [[ "$gpu_util" -gt 5 ]]; then
            echo "15" # Low GPU usage
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Function to clean old data (older than 10 minutes)
clean_old_data() {
    if [[ -f "$STATS_FILE" ]]; then
        local current_time=$(date +%s)
        local ten_minutes_ago=$((current_time - 600)) # 10 minutes = 600 seconds
        
        # Filter out entries older than 10 minutes
        awk -v cutoff="$ten_minutes_ago" '$1 >= cutoff' "$STATS_FILE" > "${STATS_FILE}.tmp" 2>/dev/null
        mv "${STATS_FILE}.tmp" "$STATS_FILE" 2>/dev/null || rm -f "${STATS_FILE}.tmp"
    fi
}

# Function to update FPS statistics
update_fps_stats() {
    local current_fps=$(get_mangohud_fps)
    
    # If MangoHUD doesn't have data, fall back to estimation
    if [[ "$current_fps" == "0" ]]; then
        current_fps=$(get_gaming_fps)
    fi
    
    # Only update stats if we have a valid numeric FPS (allow decimal)
    if [[ "$current_fps" =~ ^[0-9]+\.?[0-9]*$ && $(echo "$current_fps > 0" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
        local current_time=$(date +%s)
        
        # Clean old data first
        clean_old_data
        
        # Add new reading with timestamp
        echo "$current_time $current_fps" >> "$STATS_FILE"
    fi
}

# Function to get statistics
get_fps_stat() {
    case "$STAT_TYPE" in
        "current")
            local fps=$(get_mangohud_fps)
            if [[ "$fps" == "0" ]]; then
                fps=$(get_gaming_fps)
            fi
            echo "${fps}"
            ;;
        "current_display")
            local fps=$(get_mangohud_fps)
            if [[ "$fps" == "0" ]]; then
                fps=$(get_gaming_fps)
            fi
            
            if [[ "$fps" =~ ^[0-9]+$ ]]; then
                echo "${fps} FPS"
            else
                echo "$fps"
            fi
            ;;
        "avg")
            if [[ -f "$STATS_FILE" && -s "$STATS_FILE" ]]; then
                # Clean old data first
                clean_old_data
                
                # Calculate average from FPS values (column 2)
                local avg=$(awk '{
                    if (NF >= 2 && $2 > 0) {
                        sum += $2
                        count++
                    }
                } END {
                    if (count > 0) printf "%.0f", sum/count
                    else print "0"
                }' "$STATS_FILE" 2>/dev/null)
                
                if [[ -n "$avg" && "$avg" != "0" ]]; then
                    echo "${avg} FPS"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
        "max")
            if [[ -f "$STATS_FILE" && -s "$STATS_FILE" ]]; then
                # Clean old data first
                clean_old_data
                
                # Find maximum FPS value (column 2)
                local max=$(awk '{
                    if (NF >= 2 && $2 > max) max = $2
                } END {
                    if (max > 0) printf "%.0f", max
                    else print "0"
                }' "$STATS_FILE" 2>/dev/null)
                
                if [[ -n "$max" && "$max" != "0" ]]; then
                    echo "${max} FPS"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
        "min")
            if [[ -f "$STATS_FILE" && -s "$STATS_FILE" ]]; then
                # Clean old data first
                clean_old_data
                
                # Find minimum FPS value (column 2)
                local min=$(awk 'BEGIN{min=999999} {
                    if (NF >= 2 && $2 > 0 && $2 < min) min = $2
                } END {
                    if (min < 999999) printf "%.0f", min
                    else print "0"
                }' "$STATS_FILE" 2>/dev/null)
                
                if [[ -n "$min" && "$min" != "0" ]]; then
                    echo "${min} FPS"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
        "game")
            get_current_game
            ;;
    esac
}

# Update stats and return requested value
update_fps_stats
get_fps_stat