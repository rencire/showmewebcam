#!/bin/sh

# Eventually we want to disable the serial interface by default
# As it can be used as a persistence exploitation vector
CONFIGURE_USB_SERIAL=false
CONFIGURE_USB_WEBCAM=true

# Now apply settings from the boot config
if [ -f "/boot/enable-serial-debug" ] ; then
  CONFIGURE_USB_SERIAL=true
fi

VIDEO_FORMATS_FILE=/etc/video_formats.txt

# location of video_formats.txt file if overwritten by the user
VIDEO_FORMATS_USER_FILE=/boot/video_formats.txt

CONFIG=/sys/kernel/config/usb_gadget/piwebcam
mkdir -p "$CONFIG"
cd "$CONFIG" || exit 1

echo 0x1d6b > idVendor
echo 0x0104 > idProduct
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB

echo 0xEF > bDeviceClass
echo 0x02 > bDeviceSubClass
echo 0x01 > bDeviceProtocol
echo 0x40 > bMaxPacketSize0

mkdir -p strings/0x409
mkdir -p configs/c.2
mkdir -p configs/c.2/strings/0x409

SERIAL=$(cat /sys/firmware/devicetree/base/serial-number)
echo "$SERIAL"                > strings/0x409/serialnumber
echo "Show-me Webcam Project" > strings/0x409/manufacturer
echo "Piwebcam"               > strings/0x409/product
echo "Piwebcam"               > configs/c.2/strings/0x409/configuration
echo 500                      > configs/c.2/MaxPower

config_usb_serial () {
  mkdir -p functions/acm.usb0
  ln -s functions/acm.usb0 configs/c.2/acm.usb0
}

config_frame () {
  FORMAT=$1
  NAME=$2
  WIDTH=$3
  HEIGHT=$4

  FRAMEDIR="functions/uvc.usb0/streaming/$FORMAT/$NAME/${HEIGHT}p"

  mkdir -p "$FRAMEDIR"

  echo "$WIDTH"                    > "$FRAMEDIR"/wWidth
  echo "$HEIGHT"                   > "$FRAMEDIR"/wHeight
  echo 333333                      > "$FRAMEDIR"/dwDefaultFrameInterval
  echo $((WIDTH * HEIGHT * 80))    > "$FRAMEDIR"/dwMinBitRate
  echo $((WIDTH * HEIGHT * 160))   > "$FRAMEDIR"/dwMaxBitRate
  echo $((WIDTH * HEIGHT * 2))     > "$FRAMEDIR"/dwMaxVideoFrameBufferSize
  cat <<EOF > "$FRAMEDIR"/dwFrameInterval
333333
400000
666666
EOF
}

config_usb_webcam () {
  mkdir -p functions/uvc.usb0/control/header/h

  if [ -r $VIDEO_FORMATS_USER_FILE ] ; then
    FORMATS_FILE=$VIDEO_FORMATS_USER_FILE
  else
    FORMATS_FILE=$VIDEO_FORMATS_FILE
  fi

  grep -E "^(mjpeg|uncompressed)[[:space:]]+[[:digit:]]+[[:space:]]+[[:digit:]]+" $FORMATS_FILE | while read -r line
  do
    VIDEO_FORMAT=$(echo "$line" | awk '{print $1}')
    HDR_DESC=$(echo "$VIDEO_FORMAT" | cut -c 1)
    X=$(echo "$line" | awk '{print ($2+0)}')
    Y=$(echo "$line" | awk '{print ($3+0)}')
    echo "Enabling video format ${X}x${Y} ($VIDEO_FORMAT)"
    config_frame "$VIDEO_FORMAT" "$HDR_DESC" "$X" "$Y"
  done

  mkdir -p functions/uvc.usb0/streaming/header/h
  ln -s functions/uvc.usb0/streaming/mjpeg/m        functions/uvc.usb0/streaming/header/h
  ln -s functions/uvc.usb0/streaming/uncompressed/u functions/uvc.usb0/streaming/header/h
  ln -s functions/uvc.usb0/streaming/header/h       functions/uvc.usb0/streaming/class/fs
  ln -s functions/uvc.usb0/streaming/header/h       functions/uvc.usb0/streaming/class/hs
  ln -s functions/uvc.usb0/control/header/h         functions/uvc.usb0/control/class/fs

  ln -s functions/uvc.usb0 configs/c.2/uvc.usb0
}

# Check if camera is installed correctly
if [ ! -e /dev/video0 ] ; then
  echo "I did not detect a camera connected to the Pi. Please check your hardware."
  CONFIGURE_USB_WEBCAM=false
  # Nobody can read the error if we don't have serial enabled!
  CONFIGURE_USB_SERIAL=true
fi

if [ "$CONFIGURE_USB_WEBCAM" = true ] ; then
  echo "Configuring USB gadget webcam interface"
  config_usb_webcam
fi

if [ "$CONFIGURE_USB_SERIAL" = true ] ; then
  echo "Configuring USB gadget serial interface"
  config_usb_serial
fi

ls /sys/class/udc > UDC

# Ensure any configfs changes are picked up
udevadm settle -t 5 || :
