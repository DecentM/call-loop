#!/bin/sh
set -e

if ! type "adb" > /dev/null; then
  printf "ADB is not found in your path. Please install it and try again"
  exit 1
fi

printf "Phone number to call: "
read "number"

re='^[0-9]{0,}+$'

if ! [[ $number =~ $re ]] ; then
   printf "Phone number must consist of only numbers, got $number\n"
   exit 1
fi

if [[ -z "$number" ]]; then
   printf "You've entered an empty phone number. "
   printf "Your device will immediately hang up after starting the call.\n"
   printf "This is used to test this script.\n\n"
fi

printf "Waiting for a device to connect\n"
adb wait-for-device

device=$(adb shell getprop ro.product.model)
printf "Connection estabilished with $device\n"

printf "\nContinue? (y/N) "

function startCall () {
  adb shell am start -a android.intent.action.CALL -d tel:$number > /dev/null
}

function endCall () {
  adb shell input keyevent KEYCODE_ENDCALL > /dev/null
}

function doCallLoop () {
  printf "Beginning call loop. Press CTRL+C to cancel\n"

  while true; do
    printf "Sending call intent for $number\n"
    startCall
    printf "Hanging up in 25 seconds\n"
    sleep 20
    printf "Hanging up in 05 seconds\n"
    sleep 5
    printf "Hanging up\n"
    endCall
    printf "Backing off for one second before redialing\n"
    sleep 1
  done
}

read "yn"
case $yn in
  [Yy]* ) doCallLoop; break;;
  * ) printf "Bailing - input must be one of (Y, y) to continue.\n" && exit 1;;
esac
