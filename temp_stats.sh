#!/bin/bash

# Temperature statistics tracking script for conky
# Usage: temp_stats.sh <sensor_type> <stat_type>
# sensor_type: cpu_package, cpu_core0, cpu_core1, cpu_core2, cpu_core3, gpu_edge, gpu_junction, gpu_mem
# stat_type: current, min, max, avg

STATS_DIR="/tmp/conky_temp_stats"
SENSOR_TYPE="$1"
STAT_TYPE="$2"

# Create stats directory if it doesn't exist
mkdir -p "$STATS_DIR"

# Function to get current temperature
get_current_temp() {
    local temp
    case "$SENSOR_TYPE" in
        "cpu_package")
            temp=$(sensors | grep 'Tctl:' | awk '{print $2}' | sed 's/[^0-9.]*//g')
            ;;
        "cpu_core0"|"cpu_core1"|"cpu_core2"|"cpu_core3")
            temp=$(sensors | grep 'Tctl:' | awk '{print $2}' | sed 's/[^0-9.]*//g')
            ;;
        "gpu_edge")
            temp=$(sensors amdgpu-pci-0300 | awk '/edge:/ {print $2}' | sed 's/[^0-9.]*//g')
            ;;
        "gpu_junction")
            temp=$(sensors amdgpu-pci-0300 | awk '/junction:/ {print $2}' | sed 's/[^0-9.]*//g')
            ;;
        "gpu_mem")
            temp=$(sensors amdgpu-pci-0300 | awk '/mem:/ {print $2}' | sed 's/[^0-9.]*//g')
            ;;
    esac
    echo "$temp"
}

# Function to update statistics using awk for all math
update_stats() {
    local current_temp=$(get_current_temp)
    local stats_file="$STATS_DIR/${SENSOR_TYPE}.stats"
    
    # If no current temp or invalid, return
    if [[ -z "$current_temp" || "$current_temp" == "0" ]]; then
        return
    fi
    
    # Validate temperature is a number
    if ! echo "$current_temp" | grep -E '^[0-9]+\.?[0-9]*$' >/dev/null; then
        return
    fi
    
    # Initialize stats file if it doesn't exist
    if [[ ! -f "$stats_file" ]]; then
        echo "$current_temp $current_temp $current_temp 1" > "$stats_file"
        return
    fi
    
    # Validate existing stats file has data
    if [[ ! -s "$stats_file" ]]; then
        echo "$current_temp $current_temp $current_temp 1" > "$stats_file"
        return
    fi
    
    # Read existing stats and update using a more robust approach
    local stats_content
    if stats_content=$(cat "$stats_file" 2>/dev/null); then
        local new_stats
        new_stats=$(echo "$stats_content" | awk -v current="$current_temp" '
        {
            min_temp = $1
            max_temp = $2
            sum_temp = $3
            count = $4
            
            # Validate existing data
            if (min_temp == "" || max_temp == "" || sum_temp == "" || count == "" || count <= 0) {
                min_temp = current
                max_temp = current
                sum_temp = current
                count = 1
            } else {
                # Update min/max
                if (current < min_temp) min_temp = current
                if (current > max_temp) max_temp = current
                
                # Update sum and count
                sum_temp = sum_temp + current
                count = count + 1
            }
            
            # Output updated stats
            print min_temp, max_temp, sum_temp, count
        }' 2>/dev/null)
        
        # Only update file if we got valid output
        if [[ -n "$new_stats" ]]; then
            echo "$new_stats" > "$stats_file"
        fi
    else
        # File read failed, reinitialize
        echo "$current_temp $current_temp $current_temp 1" > "$stats_file"
    fi
}

# Function to get statistics
get_stat() {
    local stats_file="$STATS_DIR/${SENSOR_TYPE}.stats"
    local current_temp=$(get_current_temp)
    
    case "$STAT_TYPE" in
        "current")
            if [[ -n "$current_temp" && "$current_temp" != "0" ]]; then
                echo "${current_temp}°C"
            else
                echo "N/A"
            fi
            ;;
        "min")
            if [[ -f "$stats_file" ]]; then
                local min_temp=$(awk '{print $1}' "$stats_file")
                if [[ -n "$min_temp" ]]; then
                    echo "${min_temp}°C"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
        "max")
            if [[ -f "$stats_file" ]]; then
                local max_temp=$(awk '{print $2}' "$stats_file")
                if [[ -n "$max_temp" ]]; then
                    echo "${max_temp}°C"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
        "avg")
            if [[ -f "$stats_file" ]]; then
                local avg_temp=$(awk '{printf "%.1f", $3/$4}' "$stats_file")
                if [[ -n "$avg_temp" && "$avg_temp" != "nan" ]]; then
                    echo "${avg_temp}°C"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
    esac
}

# Update stats first, then return requested value
update_stats
get_stat