#!/usr/bin/env sh

storePaths=($(nix-store -qR $(nix-build release.nix)))
cp -n result/bin/{.tuxclockerd-wrapped,.tuxclocker-qt-wrapped} .
libPaths=( "${storePaths[@]/%/\/lib\/}" )
libPaths=( "${libPaths[@]/#/.}" )
libPathsColonSep=$(echo ${libPaths[@]} | sed 's/ /:/g')
glibPath=$(nix-build '<nixpkgs>' -A glibc --no-out-link)
qtVersion=$(nix-instantiate --eval --expr "(import <nixpkgs> {}).libsForQt5.qtbase.version" | sed s/\"//g)
qtPluginPath=.$(nix-build '<nixpkgs>' -A libsForQt5.qt5.qtbase --no-out-link)/lib/qt-$qtVersion/plugins/
tuxclockerPluginPath=.$(nix-build release.nix)/lib/tuxclocker/plugins/
chmod 777 ./.tuxclockerd-wrapped ./.tuxclocker-qt-wrapped
patchelf --set-rpath \.$glibPath/lib ./.tuxclockerd-wrapped ./.tuxclocker-qt-wrapped
patchelf --set-interpreter \.$glibPath"/lib/ld-linux-x86-64.so.2" ./.tuxclockerd-wrapped ./.tuxclocker-qt-wrapped

echo "
export DBUS_SYSTEM_BUS_ADDRESS='unix:path=/tmp/tuxclocker-dbus-socket'
export LD_LIBRARY_PATH=\"${libPathsColonSep[@]}\"
export QT_PLUGIN_PATH=\"$qtPluginPath\"
export TUXCLOCKER_PLUGIN_PATH=\"$tuxclockerPluginPath\"
nvidiaVersion=\$(cat /sys/module/nvidia/version | sed 's/\./-/g')
flatpakNvidiaPath=\$(find /var/lib/flatpak/runtime/org.freedesktop.Platform.GL.nvidia-\$nvidiaVersion/x86_64/*/active/files/lib)
sudo -E dbus-run-session --config-file=dev/dbusconf.conf \
sudo -E LD_LIBRARY_PATH=\$flatpakNvidiaPath:\"\$LD_LIBRARY_PATH\" XDG_SESSION_TYPE=\$XDG_SESSION_TYPE ./.tuxclockerd-wrapped & \
(unset LD_LIBRARY_PATH; sleep 2) && ./.tuxclocker-qt-wrapped; \
unset LD_LIBRARY_PATH && \
sudo kill \$(pidof .tuxclockerd-wrapped)
" > run.sh
chmod +x run.sh

# Script to install suitable NVIDIA runtime through Flatpak
echo "
nvidiaVersion=$(cat /sys/module/nvidia/version | sed 's/\./-/g')
flatpak install org.freedesktop.Platform.GL.nvidia-\$nvidiaVersion
" > nvidiaInstall.sh
chmod +x nvidiaInstall.sh

# Only copy libraries from Nix store (.so's)
neededLibs=$(find $(nix-store -qR $(nix-build release.nix)) | grep ".*.so")
tar cavf tuxclocker.tar.xz ${neededLibs[@]} ./.tuxclocker-qt-wrapped ./.tuxclockerd-wrapped \
	./run.sh ./dev/dbusconf.conf ./nvidiaInstall.sh

