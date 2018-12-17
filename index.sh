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

BOLD='\e[1m'
RESET='\033[0m'

bool () {
  return "$((!${#1}))"
}

startCall () {
  # Send the call intent
  #   - https://developer.android.com/guide/components/intents-filters

  adb shell am start -a android.intent.action.CALL -d tel:$number > /dev/null
}

endCall () {
  # Apparently, Android supports dedicated call ending buttons.
  # Let's press that!

  adb shell input keyevent KEYCODE_ENDCALL > /dev/null
}

getCallStatus () {
  adb shell dumpsys telephony.registry | grep mCallState | uniq | cut -d '=' -f 2 | cut -d " " -f 1 | head -1
}

checkCallStatus () {
  # 0 = idle
  # 1 = incoming call waiting to be picked up, we're not interested in this
  # 2 = in call

  local STATUS1
  local STATUS2

  STATUS1=$(getCallStatus)
  sleep 1
  STATUS2=$(getCallStatus)

  if [ "$STATUS1" = "$STATUS2" ]; then
    echo "$STATUS1"
  else
    sleep 1
    checkCallStatus
  fi
}

getServiceStatus () {
  adb shell dumpsys telephony.registry | grep mServiceState | uniq | cut -d '=' -f 2 | cut -d " " -f 1 | head -1
}

checkServiceStatus () {
  # 0 = idle
  # 1 = incoming call waiting to be picked up, we're not interested in this
  # 2 = in call

  local STATUS1
  local STATUS2

  STATUS1=$(getServiceStatus)
  sleep 1
  STATUS2=$(getServiceStatus)

  if [ "$STATUS1" = "$STATUS2" ]; then
    echo "$STATUS1"
  else
    sleep 1
    checkServiceStatus
  fi
}

requireService () {
  local SERVICE_STATUS
  SERVICE_STATUS=$(checkServiceStatus)

  case $SERVICE_STATUS in
    0)
      ;;
    1)
      printf "Your device is reporting that no signal is available or that it's otherwise out of service. Try moving to an area with coverage\\n"
      exit 1
      ;;
    2)
      printf "Your device is in emergency only mode. Try moving to an area with coverage.\\n"
      exit 1
      ;;
    3)
      printf "Your device's radio facilities are powered off. Please check that airplane mode is turned off, or reboot.\\n"
      exit 1
      ;;
    *)
      printf "Unhandled service status: %s\\n" "$SERVICE_STATUS"
      exit 2
      ;;
  esac
}

deviceInfo () {
  local OS_VERSION
  OS_VERSION=$(adb shell getprop ro.build.version.release)

  local CARRIER
  CARRIER=$(adb shell getprop ro.carrier)

  local CODENAME
  CODENAME=$(adb shell getprop ro.product.device)

  local MODEL
  MODEL=$(adb shell getprop ro.product.model)

  local IP
  IP=$(adb shell ip a s wlan0 | grep -oP "(?<=inet ).*(?=/)")

  local SERIAL
  SERIAL=$(adb shell getprop ro.serialno)

  printf '%15s\t  %-s\n' "Android version" "$OS_VERSION"
  printf '%15s\t  %-s\n' "Carrier" "$CARRIER"
  printf '%15s\t  %-s\n' "Codename" "$CODENAME"
  printf '%15s\t  %-s\n' "Model" "$MODEL"
  printf '%15s\t  %-s\n' "Address" "$IP"
  printf '%15s\t  %-s\n' "Serial" "$SERIAL"
}

doCallLoop () {
  local RUNNING
  RUNNING=true

  local PREV_STATUS
  PREV_STATUS=0

  printf "Beginning call loop. Press $BOLD%s$RESET to exit (will not hang up)\\n\\n" "CTRL+C"

  while $RUNNING; do
    local STATUS
    STATUS=$(checkCallStatus)

    # adb shell dumpsys telephony.registry | grep mCallState
    # printf "[debug] Status: %s\\n" "$STATUS"
    # printf "[debug] Previous status: %s\\n" "$PREV_STATUS"

    case $STATUS in
      0)
        # idle
        sleep 1

        if [ "$PREV_STATUS" != 0 ]; then
          printf "Phone entered idle status, dialing %s\\n" "$number"
        fi

        startCall
        ;;
      2)
        # in call (ringing or picked up)
        if [ "$PREV_STATUS" != 2 ]; then
          printf "Phone entered off-hook status, waiting for change\\n"
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

  printf "Call loop finished\\n"
}

if ! type "adb" > /dev/null; then
  printf "ADB is not found in your path. Please install it and try again"
  exit 1
fi

printf "Waiting for a device to connect...\\n"
adb wait-for-device

printf "$BOLD%s$RESET\\n" "Device connected:"
deviceInfo

printf "\\n"
printf "Checking service status...\\n"
requireService

printf "\\n"
printf "$BOLD%s$RESET" "Phone number to call: "
read "number"

doCallLoop
