#!/bin/bash

# GPU detection script for conky configurations
# Returns GPU type: amd, nvidia, or none

detect_gpu() {
    if sensors 2>/dev/null | grep -q "amdgpu"; then
        echo "amd"
        return
    fi

    if command -v nvidia-smi >/dev/null 2>&1; then
        if nvidia-smi >/dev/null 2>&1; then
            echo "nvidia"
            return
        fi
    fi

    echo "none"
}

get_gpu_temp() {
    local gpu_type=$(detect_gpu)
    case $gpu_type in
        "amd")
            # Auto-detect AMD GPU sensor
            local amd_sensor=$(sensors | grep -o "amdgpu-pci-[a-f0-9]*" | head -1)
            if [[ -n "$amd_sensor" ]]; then
                sensors "$amd_sensor" 2>/dev/null | awk '/edge:/ {print $2}' | head -1
            else
                echo "N/A"
            fi
            ;;
        "nvidia")
            nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | awk '{print $1"°C"}'
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

get_gpu_fan() {
    local gpu_type=$(detect_gpu)
    case $gpu_type in
        "amd")
            # Auto-detect AMD GPU sensor
            local amd_sensor=$(sensors | grep -o "amdgpu-pci-[a-f0-9]*" | head -1)
            if [[ -n "$amd_sensor" ]]; then
                sensors "$amd_sensor" 2>/dev/null | awk '/fan1:/ {print $2}' | sed 's/RPM//' | head -1
            else
                echo "N/A"
            fi
            ;;
        "nvidia")
            nvidia-smi --query-gpu=fan.speed --format=csv,noheader,nounits 2>/dev/null | head -1 | awk '{print $1}'
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

get_gpu_power() {
    local gpu_type=$(detect_gpu)
    case $gpu_type in
        "amd")
            # Auto-detect AMD GPU sensor
            local amd_sensor=$(sensors | grep -o "amdgpu-pci-[a-f0-9]*" | head -1)
            if [[ -n "$amd_sensor" ]]; then
                sensors "$amd_sensor" 2>/dev/null | awk '/PPT:/ {print $2}' | head -1
            else
                echo "N/A"
            fi
            ;;
        "nvidia")
            nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 | awk '{print $1"W"}'
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

get_gpu_usage() {
    local gpu_type=$(detect_gpu)
    case $gpu_type in
        "amd")
            if command -v amd-smi >/dev/null 2>&1; then
                amd-smi metric --usage --gpu 0 2>/dev/null | grep 'GFX_ACTIVITY:' | awk '{print $2}' | tr -d ' %'
            else
                echo "0"
            fi
            ;;
        "nvidia")
            nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1
            ;;
        *)
            echo "0"
            ;;
    esac
}

get_gpu_name() {
    local gpu_type=$(detect_gpu)
    case $gpu_type in
        "amd")
            local subsystem_name=$(lspci -vvv 2>/dev/null | grep -A 20 "VGA.*AMD.*03:00" | grep "Subsystem:" | head -1 | sed 's/.*Subsystem: [^[:space:]]* //')

            if [[ -n "$subsystem_name" && "$subsystem_name" =~ RX.*[0-9] ]]; then
                local rx_model=$(echo "$subsystem_name" | grep -oE "RX [0-9]+ [A-Z]*" | head -1)
                if [[ -n "$rx_model" ]]; then
                    echo "Radeon $rx_model"
                    return
                fi
            fi

            local gpu_line=$(lspci | grep -E "VGA.*AMD" | grep -v "Granite Ridge" | head -1)
            if [[ -n "$gpu_line" ]]; then
                local marketing_names=$(echo "$gpu_line" | sed -n 's/.*\[Radeon \([^]]*\)\].*/\1/p')
                if [[ -n "$marketing_names" ]]; then
                    if [[ "$marketing_names" == *"XTX"* ]]; then
                        echo "Radeon RX 7900 XTX"
                    elif [[ "$marketing_names" == *"XT"* ]]; then
                        echo "Radeon RX 7900 XT"
                    else
                        local first_name=$(echo "$marketing_names" | cut -d'/' -f1 | sed 's/^ *//')
                        echo "Radeon $first_name"
                    fi
                    return
                fi
            fi

            echo "AMD Radeon Graphics"
            ;;
        "nvidia")
            nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1
            ;;
        *)
            echo "Unknown GPU"
            ;;
    esac
}

get_cpu_name() {
    local cpu_name=$(cat /proc/cpuinfo | grep "model name" | head -1 | cut -d: -f2 | sed 's/^ *//')
    if [[ -n "$cpu_name" ]]; then
        echo "$cpu_name"
    else
        echo "Unknown CPU"
    fi
}

get_cpu_name_short() {
    local cpu_name=$(get_cpu_name)
    echo "$cpu_name" | sed 's/AMD //' | sed 's/ [0-9]*-Core Processor//' | sed 's/^ *//'
}

get_gpu_name_short() {
    local gpu_name=$(get_gpu_name)
    echo "$gpu_name" | sed 's/Radeon //'
}

case "$1" in
    "type")
        detect_gpu
        ;;
    "temp")
        get_gpu_temp
        ;;
    "fan")
        get_gpu_fan
        ;;
    "power")
        get_gpu_power
        ;;
    "usage")
        get_gpu_usage
        ;;
    "name")
        get_gpu_name
        ;;
    "cpu_name")
        get_cpu_name
        ;;
    "cpu_name_short")
        get_cpu_name_short
        ;;
    "name_short")
        get_gpu_name_short
        ;;
    *)
        echo "Usage: $0 {type|temp|fan|power|usage|name|cpu_name|cpu_name_short|name_short}"
        exit 1
        ;;
esac
