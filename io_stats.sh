#!/bin/bash

# I/O statistics tracking script for conky
# Usage: io_stats.sh <device> <operation> <stat_type>
# device: nvme0n1p2, nvme0n1p3, nvme0n1, sda1, etc.
# operation: read, write
# stat_type: current, min, max, avg

STATS_DIR="$HOME/.cache/conky_io_stats"
DEVICE="$1"
OPERATION="$2"
STAT_TYPE="$3"

# Create stats directory if it doesn't exist
mkdir -p "$STATS_DIR"

# Function to get current I/O speed
get_current_io() {
    local device_path="/dev/$DEVICE"
    local io_speed
    
    case "$OPERATION" in
        "read")
            # Get current read speed from conky's diskio_read
            io_speed=$(cat /proc/diskstats | grep " ${DEVICE} " | awk '{print $6}' 2>/dev/null)
            ;;
        "write")
            # Get current write speed from conky's diskio_write
            io_speed=$(cat /proc/diskstats | grep " ${DEVICE} " | awk '{print $10}' 2>/dev/null)
            ;;
    esac
    
    # Convert sectors to bytes per second (assuming 512 bytes per sector)
    if [[ -n "$io_speed" && "$io_speed" -gt 0 ]]; then
        # Calculate speed in KB/s (multiply by 512 and divide by 1024)
        io_speed=$(echo "$io_speed" | awk '{printf "%.2f", $1 * 0.5}')
    else
        io_speed="0.00"
    fi
    
    echo "$io_speed"
}

# Function to get I/O speed using conky-like method
get_io_speed_alt() {
    local device="$DEVICE"
    local operation="$OPERATION"
    
    # Get current diskio from same method conky uses
    local current_time=$(date +%s)
    local stats_file="$HOME/.cache/conky_io_stats/io_${device}_${operation}_last"
    
    # Read current stats
    local current_stats
    case "$operation" in
        "read")
            current_stats=$(awk -v dev="$device" '$3 == dev {print $6}' /proc/diskstats 2>/dev/null)
            ;;
        "write")
            current_stats=$(awk -v dev="$device" '$3 == dev {print $10}' /proc/diskstats 2>/dev/null)
            ;;
    esac
    
    if [[ -z "$current_stats" ]]; then
        echo "0.00"
        return
    fi
    
    # If we have previous reading, calculate speed
    if [[ -f "$stats_file" ]]; then
        local last_data=$(cat "$stats_file" 2>/dev/null)
        local last_stats=$(echo "$last_data" | awk '{print $1}')
        local last_time=$(echo "$last_data" | awk '{print $2}')
        
        if [[ -n "$last_stats" && -n "$last_time" ]]; then
            local time_diff=$((current_time - last_time))
            if [[ $time_diff -gt 0 ]]; then
                local stats_diff=$((current_stats - last_stats))
                # Convert sectors to KB/s (512 bytes per sector)
                local speed=$(echo "scale=2; $stats_diff * 512 / 1024 / $time_diff" | bc -l 2>/dev/null || echo "0.00")
                if [[ "$speed" == *"-"* ]]; then
                    speed="0.00"
                fi
                echo "$speed"
            else
                echo "0.00"
            fi
        else
            echo "0.00"
        fi
    else
        echo "0.00"
    fi
    
    # Store current reading for next time
    echo "$current_stats $current_time" > "$stats_file"
}

# Function to update statistics
update_stats() {
    local current_speed=$(get_io_speed_alt)
    local stats_file="$STATS_DIR/${DEVICE}_${OPERATION}.stats"
    
    # Validate speed is a number
    if ! echo "$current_speed" | grep -E '^[0-9]+\.?[0-9]*$' >/dev/null; then
        current_speed="0.00"
    fi
    
    # Skip if speed is 0 (no activity)
    if [[ "$current_speed" == "0.00" ]]; then
        return
    fi
    
    # Initialize stats file if it doesn't exist
    if [[ ! -f "$stats_file" ]]; then
        echo "$current_speed $current_speed $current_speed 1" > "$stats_file"
        return
    fi
    
    # Validate existing stats file has data
    if [[ ! -s "$stats_file" ]]; then
        echo "$current_speed $current_speed $current_speed 1" > "$stats_file"
        return
    fi
    
    # Read existing stats and update
    local stats_content
    if stats_content=$(cat "$stats_file" 2>/dev/null); then
        local new_stats
        new_stats=$(echo "$stats_content" | awk -v current="$current_speed" '
        {
            min_speed = $1
            max_speed = $2
            sum_speed = $3
            count = $4
            
            # Validate existing data
            if (min_speed == "" || max_speed == "" || sum_speed == "" || count == "" || count <= 0) {
                min_speed = current
                max_speed = current
                sum_speed = current
                count = 1
            } else {
                # Update min/max
                if (current < min_speed) min_speed = current
                if (current > max_speed) max_speed = current
                
                # Update sum and count
                sum_speed = sum_speed + current
                count = count + 1
            }
            
            # Output updated stats
            print min_speed, max_speed, sum_speed, count
        }' 2>/dev/null)
        
        # Only update file if we got valid output
        if [[ -n "$new_stats" ]]; then
            echo "$new_stats" > "$stats_file"
        fi
    else
        # File read failed, reinitialize
        echo "$current_speed $current_speed $current_speed 1" > "$stats_file"
    fi
}

# Function to format speed output
format_speed() {
    local speed="$1"
    if [[ -z "$speed" || "$speed" == "0.00" ]]; then
        echo "0 B/s"
        return
    fi
    
    # Convert to appropriate units - clean the speed value first
    local clean_speed=$(echo "$speed" | tr -d '\n' | tr -d ' ')
    local speed_int=$(echo "$clean_speed" | cut -d'.' -f1)
    if [[ -z "$speed_int" || ! "$speed_int" =~ ^[0-9]+$ ]]; then
        speed_int=0
    fi
    
    if [[ $speed_int -ge 1048576 ]]; then
        echo "$(echo "scale=1; $clean_speed / 1048576" | bc -l 2>/dev/null || echo "0")GB/s"
    elif [[ $speed_int -ge 1024 ]]; then
        echo "$(echo "scale=1; $clean_speed / 1024" | bc -l 2>/dev/null || echo "0")MB/s"
    else
        echo "$(echo "scale=0; $clean_speed" | bc -l 2>/dev/null || echo "0")KB/s"
    fi
}

# Function to get statistics
get_stat() {
    local stats_file="$STATS_DIR/${DEVICE}_${OPERATION}.stats"
    local current_speed=$(get_io_speed_alt)
    
    case "$STAT_TYPE" in
        "current")
            format_speed "$current_speed"
            ;;
        "min")
            if [[ -f "$stats_file" ]]; then
                local min_speed=$(awk '{print $1}' "$stats_file" 2>/dev/null)
                if [[ -n "$min_speed" ]]; then
                    format_speed "$min_speed"
                else
                    printf "%8s" "N/A"
                fi
            else
                printf "%8s" "N/A"
            fi
            ;;
        "max")
            if [[ -f "$stats_file" ]]; then
                local max_speed=$(awk '{print $2}' "$stats_file" 2>/dev/null)
                if [[ -n "$max_speed" ]]; then
                    format_speed "$max_speed"
                else
                    printf "%8s" "N/A"
                fi
            else
                printf "%8s" "N/A"
            fi
            ;;
        "avg")
            if [[ -f "$stats_file" ]]; then
                local avg_speed=$(awk '{if($4>0) printf "%.2f", $3/$4; else print "0"}' "$stats_file" 2>/dev/null)
                if [[ -n "$avg_speed" && "$avg_speed" != "nan" && "$avg_speed" != "0" ]]; then
                    format_speed "$avg_speed"
                else
                    printf "%8s" "N/A"
                fi
            else
                printf "%8s" "N/A"
            fi
            ;;
    esac
}

# Update stats first, then return requested value
update_stats
get_stat