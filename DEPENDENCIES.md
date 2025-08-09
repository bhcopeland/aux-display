# Dependencies

## Required Packages

```bash
# Ubuntu/Debian
sudo apt install conky-all lm-sensors pciutils sysstat bc gawk amd-smi

# Arch Linux
sudo pacman -S conky lm_sensors pciutils sysstat bc gawk

# Fedora
sudo dnf install conky lm_sensors pciutils sysstat bc gawk
```

## Hardware Specific

- **AMD GPU**: `amd-smi` package
- **NVIDIA GPU**: `nvidia-smi` (comes with drivers)
- **FPS Monitoring**: `mangohud` (optional)

## Setup

```bash
# Configure sensors
sudo sensors-detect

# Make scripts executable
chmod +x *.sh

# Test everything works
./gpu_detect.sh type
```

## Notes

- Scripts auto-detect your hardware
- Missing tools show "N/A" instead of errors
- AMD SMI needs user in `render` group: `sudo usermod -a -G render $USER`
