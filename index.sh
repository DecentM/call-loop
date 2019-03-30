#!/bin/sh
# shellcheck disable=SC2039

# This script is not fully POSIX compliant on purpose. Your shell MUST support
# local variables. Bash, Zsh, Dash or any modern shell should work, while ksh will
# not.
#
# Check here for further info:
#   - https://stackoverflow.com/questions/18597697/posix-compliant-way-to-scope-variables-to-a-function-in-a-shell-script
#   - https://github.com/koalaman/shellcheck/issues/502

# Exit if any error occurs within the script
set -e

# Formatting helpers
BOLD='\e[1m'
RESET='\033[0m'
RED='\e[31m'

# Variables that will be set as part of the initialisation stage
ANDROID_VERSION=''
TRANSPORT_ID=''
TARGET_NUMBER=''
BATTERY_LIMIT=''

# Variables that contain the user's settings on the phone as a backup
SCREEN_BRIGHTNESS=''
# STAY_ON=''

# Helper functions
log () {
  printf "$BOLD%s$RESET\\n" "$@"
}

warn () {
  printf "$RED$BOLD%s$RESET\\n" "$@"
}

tadb () {
  adb -t "$TRANSPORT_ID" "$@"
}

check () {
  # Run a function twice until the two outputs match. Then print the output.

  local FUNCTION
  FUNCTION="$1"

  local STATUS1
  local STATUS2

  STATUS1=$(eval "$FUNCTION" '"${@:2}"')
  sleep 1
  STATUS2=$(eval "$FUNCTION" '"${@:2}"')

  if [ "$STATUS1" = "$STATUS2" ]; then
    echo "$STATUS1"
  else
    sleep 1
    check "$@"
  fi
}

# Functions that abstract ADB commands
intent () {
  # Start an intent, optionally with data

  local INTENT
  INTENT=$1

  local DATA
  DATA=$2

  if [ -z "$DATA" ]; then
    tadb shell am start -a "$INTENT" > /dev/null
  else
    tadb shell am start -a "$INTENT" -d "$DATA" > /dev/null
  fi
}

press () {
  # Press the given keycode
  # https://developer.android.com/reference/android/view/KeyEvent.html#KEYCODE_0
  local KEYCODE
  KEYCODE=$1

  tadb shell input keyevent "$KEYCODE" >/dev/null
}

setting () {
  local KEY
  KEY=$1

  local VALUE
  VALUE=$2

  if [ -z "$VALUE" ]; then
    tadb shell settings get "$KEY"
  else
    tadb shell settings put "$KEY" "$VALUE"
  fi
}

# Functions that issue commands to the device that cause it to change state
# setStayOn () {
#   adb shell svc power stayon true
#   setting "global stay_on_while_plugged_in" 7
# }

# restoreStayOn () {
#   setting "global stay_on_while_plugged_in" "$STAY_ON"
# }

startCall () {
  # Send the call intent
  #   - https://developer.android.com/guide/components/intents-filters

  intent android.intent.action.CALL tel:"$TARGET_NUMBER"
}

endCall () {
  # Apparently, Android supports dedicated call ending buttons, even though they're not present on any device I know of.
  # Let's press that!

  press KEYCODE_ENDCALL
}

wake () {
  local STATUS
  STATUS=$(check getWakeStatus)

  if [ "$STATUS" = "ON" ]; then
    return 0
  fi

  press KEYCODE_POWER
}

lock () {
  local STATUS
  STATUS=$(check getWakeStatus)

  if [ "$STATUS" = "OFF" ]; then
    return 0
  fi

  press KEYCODE_POWER
}

getBrightness () {
  setting "system screen_brightness"
}

setBrightness () {
  setting "system screen_brightness" "$1"
}

maxBrightness () {
  setBrightness 255
}

minBrightness () {
  # On my phone, the lowest it can go from the UI is ten, but if I set it to 0, it goes to a level
  # below that. Clamp to ten, because that's the lowest it can go when set manually.
  setBrightness 10
}

restoreBrightness () {
  setBrightness $SCREEN_BRIGHTNESS
}

flashScreen () {
  trap 'restoreBrightness' SIGINT SIGTERM

  maxBrightness
  sleep 1
  restoreBrightness

  trap - SIGINT SIGTERM
}

# Functions that read specific data from the device
getWakeStatus () {
  tadb shell 'dumpsys power | grep -e "Display Power"' | cut -d '=' -f2
}

getCallStatus () {
  tadb shell dumpsys telephony.registry | grep mCallState | uniq | cut -d '=' -f 2 | cut -d " " -f 1 | head -1
}

getBatteryLevel () {
  tadb shell dumpsys battery | grep level | cut -d ':' -f2 | cut -d ' ' -f2
}

getServiceStatus () {
  case $ANDROID_VERSION in
  7*)
    tadb shell dumpsys telephony.registry | grep mServiceState | uniq | cut -d '=' -f 2 | cut -d " " -f 1 | head -1
    ;;
  8*)
    tadb shell dumpsys telephony.registry | grep mServiceState | uniq | cut -d '=' -f 3 | cut -d "(" -f 1 | head -1
    ;;
  esac
}

# Functions that assert things about the device
assertService () {
  # Makes sure that the user has service. If there's no service, we exit with an error code.

  local SERVICE_STATUS
  SERVICE_STATUS=$(check getServiceStatus)

  case $SERVICE_STATUS in
  0)
    printf "Your device is reporting a working service status\\n"
    ;;
  1)
    warn "Your device is reporting that no signal is available or that it's otherwise out of service. Try moving to an area with coverage.\\n"
    exit 1
    ;;
  2)
    warn "Your device is in emergency only mode. Try moving to an area with coverage.\\n"
    exit 1
    ;;
  3)
    warn "Your device's radio facilities are powered off. Check that airplane mode is turned off, or reboot.\\n"
    exit 1
    ;;
  *)
    printf "This script has encountered an unknown service status: %s. It will assume you have service.\\n" "$SERVICE_STATUS"
    ;;
  esac
}

assertBattery () {
  # Make sure the user has more battery than specified. If not, print an error message, then exit with code 0.

  local REQUIRED_LEVEL
  REQUIRED_LEVEL=$1

  local LEVEL
  LEVEL=$(check getBatteryLevel)

  if [ "$REQUIRED_LEVEL" -gt "$LEVEL" ]; then
    local DIFF
    DIFF=$(("$LEVEL" - "$REQUIRED_LEVEL"))
    DIFF=$(("$DIFF" * -1))

    warn "Your battery has reached the minimum level. It's on $LEVEL% and the limit is $REQUIRED_LEVEL% ($DIFF% below limit)"

    printf "\\n"
    log "Reducing screen brightness..."
    setBrightness 0

    log "Locking device..."
    lock
    exit 0
  fi
}

# Functions that show informative data to the user
deviceInfo () {
  local OS_VERSION
  OS_VERSION=$(tadb shell getprop ro.build.version.release)

  local CARRIER
  CARRIER=$(tadb shell getprop ro.carrier)

  local CODENAME
  CODENAME=$(tadb shell getprop ro.product.device)

  local MODEL
  MODEL=$(tadb shell getprop ro.product.model)

  local IP
  IP=$(tadb shell ip a s wlan0 | grep -oP "(?<=inet ).*(?=/)")

  local SERIAL
  SERIAL=$(tadb shell getprop ro.serialno)

  printf '%15s\t  %-s\n' "Android version" "$OS_VERSION"
  printf '%15s\t  %-s\n' "Carrier" "$CARRIER"
  printf '%15s\t  %-s\n' "Codename" "$CODENAME"
  printf '%15s\t  %-s\n' "Model" "$MODEL"
  printf '%15s\t  %-s\n' "Address" "$IP"
  printf '%15s\t  %-s\n' "Serial" "$SERIAL"
}

batteryInfo () {
  local REQUIRED_LEVEL
  REQUIRED_LEVEL=$1

  local LEVEL
  LEVEL=$(check getBatteryLevel)

  local DIFF
  DIFF=$(("$LEVEL" - "$REQUIRED_LEVEL"))

  printf "%s%% battery remaining until reaching the configured minimum of %s%%\\n" "$DIFF" "$REQUIRED_LEVEL"
}

getDevicesByTransportId () {
  local ALL_DEVICES
  ALL_DEVICES=$(adb devices -l | grep transport_id:)

  echo "$ALL_DEVICES" | while read -r device; do
    local DEVICE_TRANSPORT_ID
    DEVICE_TRANSPORT_ID=$(printf "%s" "$device" | awk -F 'transport_id:' '{print $2}' | cut -d ' ' -f1)

    local DEVICE_MODEL
    DEVICE_MODEL=$(printf "%s" "$device" | awk -F 'model:' '{print $2}' | cut -d ' ' -f1)

    printf "%s=%s" "$DEVICE_TRANSPORT_ID" "$DEVICE_MODEL"
  done
}

listDevicesByTransportId () {
  local ALL_DEVICES
  ALL_DEVICES=$1

  echo "$ALL_DEVICES" | while read -r device; do
    local DEVICE_TRANSPORT_ID
    DEVICE_TRANSPORT_ID=$(printf "%s" "$device" | cut -d '=' -f1)

    local DEVICE_MODEL
    DEVICE_MODEL=$(printf "%s" "$device" | cut -d '=' -f2)

    printf "$BOLD%s$RESET: %s\t  $BOLD%s$RESET: %-s\\n" "Model" "$DEVICE_MODEL" "ID" "$DEVICE_TRANSPORT_ID"
  done
}

# Main logic
doCallLoop () {
  local RUNNING
  RUNNING=true

  local PREV_STATUS
  PREV_STATUS=0

  printf "Beginning call loop. Press $BOLD%s$RESET to exit (will not hang up)\\n\\n" "CTRL+C"

  while $RUNNING; do
    assertBattery "$BATTERY_LIMIT"

    local STATUS
    STATUS=$(check getCallStatus)

    # adb shell dumpsys telephony.registry | grep mCallState
    # printf "[debug] Status: %s\\n" "$STATUS"
    # printf "[debug] Previous status: %s\\n" "$PREV_STATUS"

    case $STATUS in
    0)
      # idle
      sleep 1

      if [ "$PREV_STATUS" != 0 ]; then
        printf "Phone entered idle status, dialing %s\\n" "$TARGET_NUMBER"
      fi

      startCall
      ;;
    2)
      # in call (ringing or picked up)
      if [ "$PREV_STATUS" != 2 ]; then
        printf "Phone is either ringing or has been picked up, waiting for change\\n"
      fi
      ;;
    *)
      printf "Unknown status: \"%s\"\\n" "$STATUS"
      exit 2
      ;;
    esac

    sleep 2
    PREV_STATUS=$STATUS
  done
}

initialise () {
  local DEVICE_LIST
  DEVICE_LIST=$(getDevicesByTransportId)

  local DEVICE_COUNT
  DEVICE_COUNT=$(echo "$DEVICE_LIST" | wc -l)

  if [ "$DEVICE_COUNT" -eq 1 ]; then
    local ID
    ID=$(echo "$DEVICE_LIST" | cut -d '=' -f1)

    local MODEL
    MODEL=$(echo "$DEVICE_LIST" | cut -d '=' -f2)

    log "A single device was detected. Moving forward with $MODEL (ID: $ID)"
    TRANSPORT_ID=$ID
  else
    log "List of connected devices:"
    listDevicesByTransportId "$DEVICE_LIST"

    log "Enter the ID of the device you'd like to use: "
    read -r "TRANSPORT_ID"
  fi

  printf "\\n"
  log "Initialising..."

  ANDROID_VERSION=$(tadb shell getprop ro.build.version.release)
  SCREEN_BRIGHTNESS=$(check getBrightness)
  # STAY_ON=$(setting "global stay_on_while_plugged_in")
}

undo () {
  printf "\\n"

  log "Cleaning up..."
  restoreBrightness
}

teardown () {
  undo

  log "Locking device..."
  lock
}

checkRequirements () {
  if ! type "adb" >/dev/null; then
    printf "ADB is not found in your path. Install it and try again"
    exit 1
  fi
}

checkRequirements

log "Waiting for at least one device to connect..."
adb wait-for-device

# Read current settings from the device and save them so that we can restore them later
printf "\\n"
initialise

trap 'teardown' SIGINT SIGTERM

log "Waiting for device $TRANSPORT_ID to connect..."
tadb wait-for-device

printf "\\n"
log "Reading device info..."
deviceInfo

printf "\\n"
log "Checking service..."
assertService

printf "\\n"
log "Enter the battery level at which the calls should cease (default: 25):"

# Remove the trap while the user is typing, because read works in a weird way with a trap
trap - SIGINT SIGTERM
read -r 'BATTERY_LIMIT'

BATTERY_LIMIT=${BATTERY_LIMIT:-25}

# Restore the trap
trap 'teardown' SIGINT SIGTERM

printf "\\n"
log "Checking battery..."
assertBattery "$BATTERY_LIMIT"
batteryInfo "$BATTERY_LIMIT"

printf "\\n"
log "Waking device..."
wake

# Flash the screen so that the user knows for sure which device will be doing the call
sleep 1
flashScreen

printf "\\n"
log "Enter the phone number you want to call:"

# Remove the trap while the user is typing, because read works in a weird way with a trap
trap - SIGINT SIGTERM
read -r "TARGET_NUMBER"

# Restore the trap, but don't lock the device since some models end the call when locked
trap 'undo' SIGINT SIGTERM

doCallLoop

trap - SIGINT SIGTERM
