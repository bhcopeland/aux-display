#!/bin/bash

# Advanced FPS analysis script with CapFrameX-style metrics
# All statistics are calculated over a 10-minute sliding window
# Usage: fps_analyzer.sh [metric_type]
# metric_type: current, avg, max, min, p99, p95, p1_low, p01_low, frametime_avg, frametime_p99, variance

MANGOHUD_DIR="/tmp/mangohud"
STATS_FILE="/tmp/conky_fps_advanced_stats"
FRAMETIME_FILE="/tmp/conky_frametime_data"
METRIC_TYPE="${1:-current}"
MAX_SAMPLES=1000  # Keep last 1000 FPS readings for percentile calculations

# Function to get current FPS from MangoHUD CSV
get_current_fps() {
    local mangohud_csv=$(find "$MANGOHUD_DIR" -name "*.csv" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [[ -f "$mangohud_csv" ]]; then
        local fps=$(tail -1 "$mangohud_csv" 2>/dev/null | cut -d',' -f1)
        if [[ -n "$fps" && $(echo "$fps > 0" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
            printf "%.2f" "$fps"
            return 0
        fi
    fi
    echo "0"
    return 1
}

# Function to get current frametime (ms)
get_current_frametime() {
    local fps=$(get_current_fps)
    if [[ "$fps" != "0" ]]; then
        echo "scale=3; 1000 / $fps" | bc -l 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to clean old frametime data (older than 10 minutes)
clean_old_frametime_data() {
    if [[ -f "$FRAMETIME_FILE" ]]; then
        local current_time=$(date +%s)
        local ten_minutes_ago=$((current_time - 600)) # 10 minutes = 600 seconds
        
        # Filter out entries older than 10 minutes
        awk -v cutoff="$ten_minutes_ago" '$1 >= cutoff' "$FRAMETIME_FILE" > "${FRAMETIME_FILE}.tmp" 2>/dev/null
        mv "${FRAMETIME_FILE}.tmp" "$FRAMETIME_FILE" 2>/dev/null || rm -f "${FRAMETIME_FILE}.tmp"
    fi
}

# Function to update rolling FPS data for percentile calculations - now with 10-minute window
update_fps_history() {
    local current_fps=$(get_current_fps)
    
    if [[ "$current_fps" != "0" ]]; then
        local current_time=$(date +%s)
        
        # Clean old data first
        clean_old_frametime_data
        
        # Add current FPS with timestamp to history file
        echo "$current_time $current_fps" >> "$FRAMETIME_FILE"
    fi
}

# Function to calculate percentiles from FPS history
calculate_percentile() {
    local percentile=$1
    
    if [[ ! -f "$FRAMETIME_FILE" || ! -s "$FRAMETIME_FILE" ]]; then
        echo "0"
        return
    fi
    
    # Clean old data first
    clean_old_frametime_data
    
    # Extract FPS values (column 2) and sort for percentile calculation
    local result=$(awk '{if (NF >= 2) print $2}' "$FRAMETIME_FILE" | sort -n | awk -v p="$percentile" '
    BEGIN { 
        count = 0 
    }
    { 
        values[count++] = $1 
    }
    END {
        if (count == 0) {
            print "0"
        } else {
            # Calculate percentile position
            pos = (p / 100.0) * (count - 1)
            lower = int(pos)
            upper = lower + 1
            
            if (upper >= count) {
                print values[count-1]
            } else if (lower == pos) {
                print values[lower]
            } else {
                # Linear interpolation
                weight = pos - lower
                result = values[lower] * (1 - weight) + values[upper] * weight
                print result
            }
        }
    }')
    
    printf "%.1f" "$result"
}

# Function to calculate 1% and 0.1% lows (average of worst 1% and 0.1%)
calculate_low_percentile() {
    local percent=$1
    
    if [[ ! -f "$FRAMETIME_FILE" || ! -s "$FRAMETIME_FILE" ]]; then
        echo "0"
        return
    fi
    
    # Clean old data first
    clean_old_frametime_data
    
    # Extract FPS values (column 2) and sort for low percentile calculation
    local result=$(awk '{if (NF >= 2) print $2}' "$FRAMETIME_FILE" | sort -n | awk -v p="$percent" '
    { values[NR-1] = $1 }
    END {
        count = NR
        if (count == 0) {
            print "0"
        } else {
            # Calculate how many samples to average (worst p%)
            samples_to_avg = int(count * p / 100.0)
            if (samples_to_avg < 1) samples_to_avg = 1
            
            sum = 0
            for (i = 0; i < samples_to_avg; i++) {
                sum += values[i]
            }
            avg = sum / samples_to_avg
            print avg
        }
    }')
    
    printf "%.1f" "$result"
}

# Function to calculate frame time variance/stuttering metric
calculate_variance() {
    if [[ ! -f "$FRAMETIME_FILE" || ! -s "$FRAMETIME_FILE" ]]; then
        echo "0"
        return
    fi
    
    # Clean old data first
    clean_old_frametime_data
    
    # Extract FPS values (column 2), convert to frame times and calculate variance
    local variance=$(awk '{if (NF >= 2) print $2}' "$FRAMETIME_FILE" | awk '
    { 
        fps[NR] = $1
        frametime[NR] = 1000 / $1
        sum += frametime[NR]
    }
    END {
        if (NR == 0) {
            print "0"
        } else {
            mean = sum / NR
            variance_sum = 0
            
            for (i = 1; i <= NR; i++) {
                diff = frametime[i] - mean
                variance_sum += diff * diff
            }
            
            variance = variance_sum / NR
            print sqrt(variance)
        }
    }')
    
    printf "%.2f" "$variance"
}

# Function to clean old data (older than 10 minutes)
clean_old_basic_stats() {
    if [[ -f "$STATS_FILE" ]]; then
        local current_time=$(date +%s)
        local ten_minutes_ago=$((current_time - 600)) # 10 minutes = 600 seconds
        
        # Filter out entries older than 10 minutes
        awk -v cutoff="$ten_minutes_ago" '$1 >= cutoff' "$STATS_FILE" > "${STATS_FILE}.tmp" 2>/dev/null
        mv "${STATS_FILE}.tmp" "$STATS_FILE" 2>/dev/null || rm -f "${STATS_FILE}.tmp"
    fi
}

# Function to update basic statistics (for compatibility) - now with 10-minute window
update_basic_stats() {
    local current_fps=$(get_current_fps)
    
    if [[ "$current_fps" != "0" ]]; then
        local current_time=$(date +%s)
        
        # Clean old data first
        clean_old_basic_stats
        
        # Add new reading with timestamp
        echo "$current_time $current_fps" >> "$STATS_FILE"
    fi
}

# Main execution
update_fps_history
update_basic_stats

case "$METRIC_TYPE" in
    "current")
        fps=$(get_current_fps)
        printf "%.0f" "$fps"
        ;;
    "current_display")
        fps=$(get_current_fps)
        printf "%.0f FPS" "$fps"
        ;;
    "avg")
        if [[ -f "$STATS_FILE" && -s "$STATS_FILE" ]]; then
            # Clean old data first
            clean_old_basic_stats
            
            # Calculate average from FPS values (column 2)
            avg=$(awk '{
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
            clean_old_basic_stats
            
            # Find maximum FPS value (column 2)
            max=$(awk '{
                if (NF >= 2 && $2 > max) max = $2
            } END {
                if (max > 0) printf "%.0f", max
                else print "0"
            }' "$STATS_FILE" 2>/dev/null)
            
            if [[ -n "$max" && "$max" != "0" ]]; then
                printf "%.0f FPS" "$max"
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
            clean_old_basic_stats
            
            # Find minimum FPS value (column 2)
            min=$(awk 'BEGIN{min=999999} {
                if (NF >= 2 && $2 > 0 && $2 < min) min = $2
            } END {
                if (min < 999999) printf "%.0f", min
                else print "0"
            }' "$STATS_FILE" 2>/dev/null)
            
            if [[ -n "$min" && "$min" != "0" ]]; then
                printf "%.0f FPS" "$min"
            else
                echo "N/A"
            fi
        else
            echo "N/A"
        fi
        ;;
    "p99")
        p99=$(calculate_percentile 99)
        echo "${p99} FPS"
        ;;
    "p95")
        p95=$(calculate_percentile 95)
        echo "${p95} FPS"
        ;;
    "p1_low")
        p1_low=$(calculate_low_percentile 1)
        echo "${p1_low} FPS"
        ;;
    "p01_low")
        p01_low=$(calculate_low_percentile 0.1)
        echo "${p01_low} FPS"
        ;;
    "frametime_avg")
        frametime=$(get_current_frametime)
        printf "%.1f ms" "$frametime"
        ;;
    "frametime_p99")
        # Convert 1st percentile FPS to frame time (worst frame times)
        p1_fps=$(calculate_percentile 1)
        if [[ "$p1_fps" != "0" ]]; then
            frametime_p99=$(echo "scale=1; 1000 / $p1_fps" | bc -l 2>/dev/null || echo "0")
            echo "${frametime_p99} ms"
        else
            echo "N/A"
        fi
        ;;
    "variance")
        variance=$(calculate_variance)
        echo "${variance} ms"
        ;;
    "game")
        # Get current game name
        local game_process=$(ps aux | grep -E "(GoW\.exe|steam.*app)" | grep -v grep | head -1 | awk '{print $11}' | sed 's/.*\///' | cut -d'.' -f1)
        if [[ -n "$game_process" ]]; then
            echo "$game_process"
        else
            echo "No Game"
        fi
        ;;
    *)
        echo "Usage: $0 [current|avg|max|min|p99|p95|p1_low|p01_low|frametime_avg|frametime_p99|variance|game]"
        ;;
esac