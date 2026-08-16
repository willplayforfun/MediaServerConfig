# nordewal/kodi-gbm ships Kodi's GBM build but skips peripheral.joystick, the
# add-on that turns raw gamepad/joystick input into Kodi actions (keyboards
# and remotes don't need it - Kodi core handles those directly via libinput).
# Without it, a controller's device node is visible but nothing it sends
# reaches Kodi.
FROM nordewal/kodi-gbm:latest
# The base image's GPG trust DB and archlinux-keyring are frozen at its last
# build date, so pacman can't verify packages signed by newer packager keys
# (e.g. kodi-addon-peripheral-joystick fails with "unknown trust") until the
# keyring is refreshed from the network and the trust DB repopulated from it.
RUN pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Sy --noconfirm archlinux-keyring && \
    pacman-key --populate archlinux && \
    pacman -S --noconfirm kodi-addon-peripheral-joystick

# curl is what the "YouTube" Kodi favourite shells out to (System.Exec) to
# tell the switcher container to stop Kodi and start the youtube-tv kiosk
# browser - see switcher/compose.yml.
RUN pacman -S --noconfirm curl
