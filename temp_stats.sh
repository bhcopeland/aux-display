#!/bin/bash

# Temperature statistics tracking script for conky
# Usage: temp_stats.sh <sensor_type> <stat_type>
# sensor_type: cpu_package, cpu_core0, cpu_core1, cpu_core2, cpu_core3, gpu_edge, gpu_junction, gpu_mem, nvme_composite, nvme_sensor2
# stat_type: current, min, max, avg

STATS_DIR="$HOME/.cache/conky_temp_stats"
SENSOR_TYPE="$1"
STAT_TYPE="$2"

# Create stats directory if it doesn't exist
mkdir -p "$STATS_DIR"

# Function to get current temperature
get_current_temp() {
    local temp
    case "$SENSOR_TYPE" in
        "cpu_package")
            temp=$(sensors | grep 'Tctl:' | awk '{print $2}' | sed 's/[^0-9.]*//g' | head -1)
            ;;
        "cpu_core0"|"cpu_core1"|"cpu_core2"|"cpu_core3")
            temp=$(sensors | grep 'Tctl:' | awk '{print $2}' | sed 's/[^0-9.]*//g' | head -1)
            ;;
        "gpu_edge")
            gpu_type=$(./gpu_detect.sh type)
            if [[ "$gpu_type" == "amd" ]]; then
                # Auto-detect AMD GPU sensor
                local amd_sensor=$(sensors | grep -o "amdgpu-pci-[a-f0-9]*" | head -1)
                if [[ -n "$amd_sensor" ]]; then
                    temp=$(sensors "$amd_sensor" | awk '/edge:/ {print $2}' | sed 's/[^0-9.]*//g')
                fi
            elif [[ "$gpu_type" == "nvidia" ]]; then
                temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
            fi
            ;;
        "gpu_junction")
            gpu_type=$(./gpu_detect.sh type)
            if [[ "$gpu_type" == "amd" ]]; then
                # Auto-detect AMD GPU sensor
                local amd_sensor=$(sensors | grep -o "amdgpu-pci-[a-f0-9]*" | head -1)
                if [[ -n "$amd_sensor" ]]; then
                    temp=$(sensors "$amd_sensor" | awk '/junction:/ {print $2}' | sed 's/[^0-9.]*//g')
                fi
            elif [[ "$gpu_type" == "nvidia" ]]; then
                temp=$(nvidia-smi --query-gpu=temperature.memory --format=csv,noheader,nounits 2>/dev/null | head -1)
            fi
            ;;
        "gpu_mem")
            gpu_type=$(./gpu_detect.sh type)
            if [[ "$gpu_type" == "amd" ]]; then
                # Auto-detect AMD GPU sensor
                local amd_sensor=$(sensors | grep -o "amdgpu-pci-[a-f0-9]*" | head -1)
                if [[ -n "$amd_sensor" ]]; then
                    temp=$(sensors "$amd_sensor" | awk '/mem:/ {print $2}' | sed 's/[^0-9.]*//g')
                fi
            elif [[ "$gpu_type" == "nvidia" ]]; then
                temp=$(nvidia-smi --query-gpu=temperature.memory --format=csv,noheader,nounits 2>/dev/null | head -1)
            fi
            ;;
        "nvme_composite")
            # Auto-detect first NVMe sensor
            local nvme_sensor=$(sensors | grep -o "nvme-pci-[a-f0-9]*" | head -1)
            if [[ -n "$nvme_sensor" ]]; then
                temp=$(sensors "$nvme_sensor" 2>/dev/null | awk '/Composite:/ {print $2}' | sed 's/[^0-9.]*//g')
            fi
            ;;
        "nvme_sensor2")
            # Auto-detect first NVMe sensor
            local nvme_sensor=$(sensors | grep -o "nvme-pci-[a-f0-9]*" | head -1)
            if [[ -n "$nvme_sensor" ]]; then
                temp=$(sensors "$nvme_sensor" 2>/dev/null | awk '/Sensor 2:/ {print $3}' | sed 's/[^0-9.]*//g')
            fi
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
            if [[ -n "$current_temp" && "$current_temp" != "0" && "$current_temp" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                printf "%.1f°C" "$current_temp"
            else
                echo "N/A"
            fi
            ;;
        "min")
            if [[ -f "$stats_file" ]]; then
                local min_temp=$(awk '{print $1}' "$stats_file" | head -1)
                if [[ -n "$min_temp" && "$min_temp" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                    printf "%.1f°C" "$min_temp"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
        "max")
            if [[ -f "$stats_file" ]]; then
                local max_temp=$(awk '{print $2}' "$stats_file" | head -1)
                if [[ -n "$max_temp" && "$max_temp" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                    printf "%.1f°C" "$max_temp"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
        "avg")
            if [[ -f "$stats_file" ]]; then
                local avg_temp=$(awk '{printf "%.1f", $3/$4}' "$stats_file" | head -1)
                if [[ -n "$avg_temp" && "$avg_temp" != "nan" && "$avg_temp" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                    printf "%.1f°C" "$avg_temp"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
    esac
}

update_stats
get_stat
