#!/bin/sh

# Eventually we want to disable the serial interface by default
# As it can be used as a persistence exploitation vector
CONFIGURE_USB_SERIAL=false
CONFIGURE_USB_WEBCAM=true
CONFIGURE_USB_NETWORK=false

# Now apply settings from the boot config
if [ -f "/boot/enable-serial-debug" ] ; then
  CONFIGURE_USB_SERIAL=true
fi

USB_NETWORK_FILE=/boot/enable-usb-network
if [ -f "$USB_NETWORK_FILE" ] ; then
  CONFIGURE_USB_NETWORK=true
  _USB_NETWORK_TYPE=$(head -n1 "$USB_NETWORK_FILE")
  case "$_USB_NETWORK_TYPE" in
    RNDIS)
      USB_NETWORK_TYPE=$_USB_NETWORK_TYPE
      ;;
    *)
      # Default to ECM networking
      USB_NETWORK_TYPE=ECM
      ;;
  esac
fi

# Windows & Mac users might need to disable USB Webcam
# when they enable network
if [ -f "/boot/disable-webcam" ] ; then
  echo "Disabling usb webcam functionalities"
  CONFIGURE_USB_WEBCAM=false
fi

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
echo 100000000d2386db         > strings/0x409/serialnumber
echo "Show-me Webcam Project" > strings/0x409/manufacturer
echo "Piwebcam"               > strings/0x409/product
echo 500                      > configs/c.2/MaxPower
echo "Piwebcam"               > configs/c.2/strings/0x409/configuration


config_usb_network_rndis () {
  mkdir -p functions/rndis.usb0
  echo "$1" > functions/rndis.usb0/host_addr
  echo "$2" > functions/rndis.usb0/dev_addr

  mkdir -p os_desc
  echo "0x80"     > configs/c.2/bmAttributes
  echo "1"        > os_desc/use
  echo "0xbc"     > os_desc/b_vendor_code
  echo "MSFT100"  > os_desc/qw_sign

  mkdir -p functions/rndis.usb0/os_desc/interface.rndis
  echo "RNDIS"    > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
  echo "5162001"  > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id

  ln -s functions/rndis.usb0 configs/c.2/
  ln -s configs/c.2/ os_desc
}

config_usb_network_ecm () {
  mkdir -p functions/ecm.usb0
  echo "$1" > functions/ecm.usb0/host_addr
  echo "$2" > functions/ecm.usb0/dev_addr
  ln -s functions/ecm.usb0 configs/c.2/
}

config_usb_network () {
  MAC_PREFIX_PI="ca:fe" # No one has taken this prefix yet
  MAC_PREFIX_HOST="ca:ff" # No one has taken this prefix yet
  PI_SERIAL="$(grep Serial /proc/cpuinfo | sed 's/Serial\s*: 0000\(\w*\)/\1/')"
  MAC_SUFFIX=$(echo "${PI_SERIAL}" | sed 's/\(\w\w\)/:\1/g' | cut -b 7-)
  MAC_HOST="${MAC_PREFIX_HOST}${MAC_SUFFIX}" # Mac address for host PC
  MAC_PI="${MAC_PREFIX_PI}${MAC_SUFFIX}" # MAC address for PiCam

  case "$USB_NETWORK_TYPE" in
    RNDIS)
      config_usb_network_rndis "$MAC_HOST" "$MAC_PI"
      ;;
    ECM)
      config_usb_network_ecm "$MAC_HOST" "$MAC_PI"
      ;;
    *)
      echo "Sorry, $USB_NETWORK_TYPE is not a valid USB Network type"
      ;;
  esac
}


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
  echo $((WIDTH * HEIGHT * 80))  > "$FRAMEDIR"/dwMinBitRate
  echo $((WIDTH * HEIGHT * 160)) > "$FRAMEDIR"/dwMaxBitRate
  echo $((WIDTH * HEIGHT * 2))   > "$FRAMEDIR"/dwMaxVideoFrameBufferSize
  cat <<EOF > "$FRAMEDIR"/dwFrameInterval
333333
400000
666666
EOF
}

config_usb_webcam () {
  mkdir -p functions/uvc.usb0/control/header/h

  config_frame mjpeg m  640  360
  config_frame mjpeg m  640  480
  config_frame mjpeg m  800  600
  config_frame mjpeg m 1024  768
  config_frame mjpeg m 1280  720
  config_frame mjpeg m 1280  960
  config_frame mjpeg m 1440 1080
  config_frame mjpeg m 1536  864
  config_frame mjpeg m 1600  900
  config_frame mjpeg m 1600 1200
  config_frame mjpeg m 1920 1080

  mkdir -p functions/uvc.usb0/streaming/header/h
  ln -s functions/uvc.usb0/streaming/mjpeg/m  functions/uvc.usb0/streaming/header/h
  ln -s functions/uvc.usb0/streaming/header/h functions/uvc.usb0/streaming/class/fs
  ln -s functions/uvc.usb0/streaming/header/h functions/uvc.usb0/streaming/class/hs
  ln -s functions/uvc.usb0/control/header/h   functions/uvc.usb0/control/class/fs

  ln -s functions/uvc.usb0 configs/c.2/uvc.usb0
}

# Check if camera is installed correctly
if [ ! -e /dev/video0 ] ; then
  echo "I did not detect a camera connected to the Pi. Please check your hardware."
  CONFIGURE_USB_WEBCAM=false
fi

if [ "$CONFIGURE_USB_WEBCAM" = true ] ; then
  echo "Configuring USB gadget webcam interface"
  config_usb_webcam
fi

if [ "$CONFIGURE_USB_SERIAL" = true ] ; then
  echo "Configuring USB gadget serial interface"
  config_usb_serial
fi

if [ "$CONFIGURE_USB_NETWORK" = true ] ; then
  echo "Configuring USB gadget network interface ($USB_NETWORK_TYPE)"
  config_usb_network
fi

udevadm settle -t 5 || :
ls /sys/class/udc > UDC

if [ "$CONFIGURE_USB_NETWORK" = true ] ; then
  echo "Configuring USB network interface link-local address"
  if [ -x /usr/sbin/avahi-autoipd ]; then
    interface=usb0
    /usr/sbin/avahi-autoipd -c $interface || /usr/sbin/avahi-autoipd -wD $interface --no-chroot
  fi
fi

