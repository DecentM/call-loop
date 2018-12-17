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

checkStatus () {
  # 0 = idle
  # 1 = ringing
  # 2 = in call

  adb shell dumpsys telephony.registry | grep mCallState | uniq | cut -d '=' -f 2 | cut -d " " -f 1 | head -1
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

  printf '%15s\t  %-s\n' "Android version" "$OS_VERSION"
  printf '%15s\t  %-s\n' "Carrier" "$CARRIER"
  printf '%15s\t  %-s\n' "Codename" "$CODENAME"
  printf '%15s\t  %-s\n' "Model" "$MODEL"
  printf '%15s\t  %-s\n' "Address" "$IP"
}

doCallLoop () {
  local RUNNING
  RUNNING=true

  local PREV_STATE
  PREV_STATE=0

  printf "Beginning call loop. Press CTRL+C to cancel\\n"

  while $RUNNING; do
    local STATUS
    STATUS=$(checkStatus)

    case $STATUS in
      0)
        # idle
        sleep 1

        if [ "$PREV_STATE" != "0" ]; then
          printf "Dialing %s\\n" "$number"
        fi

        startCall
        ;;
      1)
        # ringing
        if [ "$PREV_STATE" != "1" ]; then
          printf "Currently ringing, waiting for state change\\n"
        fi

        sleep 3
        ;;
      2)
        # in call
        printf "Call has been picked up, terminating loop\\n"
        RUNNING=false
        ;;
      *)
        printf "Unknown status: \"%s\"\\n" "$STATUS"
        exit 1
        ;;
    esac

    sleep 2
    PREV_STATE=$STATUS
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
printf "$BOLD%s$RESET" "Phone number to call: "
read "number"

doCallLoop
