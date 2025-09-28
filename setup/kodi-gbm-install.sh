#!/usr/bin/env bash

YW=`echo "\033[33m"`
RD=`echo "\033[01;31m"`
BL=`echo "\033[36m"`
GN=`echo "\033[1;92m"`
CL=`echo "\033[m"`
RETRY_NUM=10
RETRY_EVERY=3
NUM=$RETRY_NUM
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
BFR="\\r\\033[K"
HOLD="-"
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR

function error_exit() {
  trap - ERR
  local reason="Unknown failure occurred."
  local msg="${1:-$reason}"
  local flag="${RD}‼ ERROR ${CL}$EXIT@$LINE"
  echo -e "$flag $msg" 1>&2
  exit $EXIT
}

function msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
    local msg="$1"
    echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
    local msg="$1"
    echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

msg_info "Setting up Container OS "
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
while [ "$(hostname -I)" = "" ]; do
  1>&2 echo -en "${CROSS}${RD} No Network! "
  sleep $RETRY_EVERY
  ((NUM--))
  if [ $NUM -eq 0 ]
  then
    1>&2 echo -e "${CROSS}${RD} No Network After $RETRY_NUM Tries${CL}"    
    exit 1
  fi
done
msg_ok "Set up Container OS"
msg_ok "Network Connected: ${BL}$(hostname -I)"

if nc -zw1 8.8.8.8 443; then  msg_ok "Internet Connected"; else  msg_error "Internet NOT Connected"; exit 1; fi;
RESOLVEDIP=$(nslookup "github.com" | awk -F':' '/^Address: / { matched = 1 } matched { print $2}' | xargs)
if [[ -z "$RESOLVEDIP" ]]; then msg_error "DNS Lookup Failure";  else msg_ok "DNS Resolved github.com to $RESOLVEDIP";  fi;

msg_info "Updating Container OS"
apt-get update &>/dev/null
apt-get -y upgrade &>/dev/null
msg_ok "Updated Container OS"

msg_info "Installing Dependencies"
apt-get install -y curl &>/dev/null
apt-get install -y sudo &>/dev/null
apt-get install -y gnupg &>/dev/null
msg_ok "Installed Dependencies"

msg_info "Setting Up Hardware Acceleration and GBM Support"  
apt-get -y install \
    va-driver-all \
    ocl-icd-libopencl1 \
    libgbm1 \
    libdrm2 \
    libegl1-mesa \
    libgl1-mesa-dri \
    mesa-vulkan-drivers &>/dev/null 
set +e
alias die=''
apt-get install --ignore-missing -y beignet-opencl-icd &>/dev/null
alias die='EXIT=$? LINE=$LINENO error_exit'
set -e
    
msg_ok "Set Up Hardware Acceleration and GBM Support"  

msg_info "Setting Up kodi user"
useradd -d /home/kodi -m kodi &>/dev/null
gpasswd -a kodi audio &>/dev/null
gpasswd -a kodi video &>/dev/null
gpasswd -a kodi render &>/dev/null
gpasswd -a kodi input &>/dev/null
gpasswd -a kodi tty &>/dev/null
msg_ok "Set Up kodi user"

msg_info "Installing kodi"
# Add PPA for Kodi (ubuntuhandbook1)
add-apt-repository -y ppa:ubuntuhandbook1/kodi
apt-get update &>/dev/null
apt-get install -y kodi &>/dev/null
set +e
alias die=''
apt-get install --ignore-missing -y kodi-peripheral-joystick &>/dev/null
alias die='EXIT=$? LINE=$LINENO error_exit'
set -e
msg_ok "Installed kodi"

msg_info "Setting up Kodi GBM service"
cat <<EOF >/etc/systemd/system/kodi-gbm.service
[Unit]
Description=Kodi standalone (GBM)
After=systemd-user-sessions.service network.target sound.target
Wants=network.target

[Service]
User=kodi
Group=kodi
Type=simple
PAMName=login
TTYPath=/dev/tty7
ExecStartPre=/bin/chvt 7
ExecStart=/usr/bin/kodi-standalone --windowing=gbm
Restart=always
RestartSec=15
KillMode=mixed
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Set up Kodi GBM service"

msg_info "Setting up udev rules for input devices"
cat <<EOF >/etc/udev/rules.d/99-kodi-permissions.rule
# Allow kodi user access to input devices
KERNEL=="event[0-9]*", GROUP="input", MODE="0664"
KERNEL=="js[0-9]*", GROUP="input", MODE="0664"
KERNEL=="mouse[0-9]*", GROUP="input", MODE="0664"
# Allow kodi user access to video devices  
SUBSYSTEM=="drm", GROUP="video", MODE="0664"
KERNEL=="card[0-9]*", GROUP="video", MODE="0664"
KERNEL=="controlD[0-9]*", GROUP="render", MODE="0664"
KERNEL=="renderD[0-9]*", GROUP="render", MODE="0664"
EOF
msg_ok "Set up udev rules for input devices"

msg_info "Creating Kodi configuration directory"
mkdir -p /home/kodi/.kodi/userdata
cat <<EOF >/home/kodi/.kodi/userdata/guisettings.xml
<settings version="2">
    <setting id="system.playlistspath" default="true">special://profile/playlists/</setting>
    <setting id="filelists.showaddsourcebuttons" default="true">true</setting>
    <setting id="filelists.showextensions" default="true">true</setting>
    <setting id="filelists.showparentdiritems" default="true">true</setting>
    <setting id="filelists.showhidden" default="true">false</setting>
    <setting id="general.addonupdates" default="true">0</setting>
    <setting id="general.addonforeignfilter" default="true">false</setting>
    <setting id="general.addonbrokenfilter" default="true">true</setting>
    <setting id="videoscreen.screen" default="true">0</setting>
    <setting id="videoscreen.resolution" default="true">19</setting>
    <setting id="videoplayer.usevaapi" default="true">true</setting>
    <setting id="videoplayer.usevdpau" default="true">true</setting>
</settings>
EOF
chown -R kodi:kodi /home/kodi/.kodi
msg_ok "Created Kodi configuration directory"

msg_info "Enabling Kodi GBM service"
systemctl daemon-reload
systemctl enable kodi-gbm.service
msg_ok "Enabled Kodi GBM service"

PASS=$(grep -w "root" /etc/shadow | cut -b6);
  if [[ $PASS != $ ]]; then
msg_info "Customizing Container"
chmod -x /etc/update-motd.d/*
touch ~/.hushlogin
GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
mkdir -p $(dirname $GETTY_OVERRIDE)
cat << EOF > $GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
systemctl daemon-reload
systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')
msg_ok "Customized Container"
  fi
  
msg_info "Cleaning up"
apt-get autoremove >/dev/null
apt-get autoclean >/dev/null
msg_ok "Cleaned"

msg_info "Starting Kodi GBM service"
systemctl start kodi-gbm.service
msg_ok "Started Kodi GBM service"
