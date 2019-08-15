#!/bin/sh

# Replace /bin/sh to target shell to easy test.
[ "$1" = "sh" ] && exit
if [ "${1% *}" = "busybox" ] || [ -e /etc/alpine-release ] || [ -e /etc/openwrt_release ]; then
  # Avoid unsupported busybox 0.60.5 freeze
  busybox ash -c 'busybox ash -c false' && exit 0

  ln -snf /bin/busybox /bin/ash
  rm /bin/sh
  echo '#!/bin/ash' > /bin/sh
else
  mv /bin/sh /bin/default-shell
  echo '#!/bin/default-shell' > /bin/sh
fi
echo "exec $1 \"\$@\"" >> /bin/sh
chmod +x /bin/sh
