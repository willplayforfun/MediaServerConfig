# Kodi from Arch's own packages, on the official Arch image. Arch's kodi
# package includes the GBM (DRM/KMS) build, picked with --windowing=gbm.
#  - inputstream-adaptive plays DASH/HLS streams (the YouTube add-on needs it).
#  - peripheral-joystick turns raw gamepad input into Kodi actions. Keyboards
#    and remotes don't need it (Kodi core reads those through libinput).
#  - nss/nspr: Widevine (DRM-protected streams) links against them.
FROM archlinux:base

# Keeps downloaded packages between builds.
RUN --mount=type=cache,target=/var/cache/pacman/pkg,sharing=locked \
    pacman -Syu --noconfirm \
        kodi \
        kodi-addon-inputstream-adaptive \
        kodi-addon-peripheral-joystick \
        nss \
        nspr

CMD ["/usr/bin/kodi-standalone", "--windowing=gbm"]
