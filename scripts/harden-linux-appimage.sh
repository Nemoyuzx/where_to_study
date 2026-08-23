#!/usr/bin/env bash
set -euo pipefail

APPDIR="${1:?Usage: harden-linux-appimage.sh APPDIR}"
LIB_DIR="$APPDIR/usr/lib"
GTK_HOOK="$APPDIR/apprun-hooks/linuxdeploy-plugin-gtk.sh"
MARKER="# Where To Study AppImage host ABI isolation"

if [[ ! -d "$LIB_DIR" ]]; then
  echo "AppImage AppDir is missing usr/lib: $APPDIR" >&2
  exit 1
fi
if [[ ! -f "$GTK_HOOK" ]]; then
  echo "AppImage AppDir is missing the GTK AppRun hook: $GTK_HOOK" >&2
  exit 1
fi

# libwayland is part of the host graphics ABI. Bundling the build host's copy
# makes newer Mesa/EGL load an older client library and can leave WebKitGTK in
# an EGL_BAD_PARAMETER white screen (tauri-apps/tauri#15665).
removed_wayland=0
while IFS= read -r -d '' library; do
  rm -f -- "$library"
  removed_wayland=$((removed_wayland + 1))
done < <(find "$LIB_DIR" -maxdepth 1 \( -type f -o -type l \) -name 'libwayland-*.so*' -print0)

if ! grep -Fq "$MARKER" "$GTK_HOOK"; then
  cat >>"$GTK_HOOK" <<'EOF'

# Where To Study AppImage host ABI isolation
# Keep the bundled GLib/GIO family from loading newer, ABI-incompatible host
# modules such as gvfs. The local VFS is sufficient for this desktop client.
wts_gio_module_dir=""
for wts_candidate in \
  "$APPDIR"/usr/lib/*-linux-gnu/gio/modules \
  "$APPDIR"/usr/lib/gio/modules; do
  if [ -d "$wts_candidate" ]; then
    wts_gio_module_dir="$wts_candidate"
    break
  fi
done
if [ -n "$wts_gio_module_dir" ]; then
  export GIO_MODULE_DIR="$wts_gio_module_dir"
  export GIO_EXTRA_MODULES="$wts_gio_module_dir"
fi
export GIO_USE_VFS=local

# Do not replace GStreamer's system plugin search with an empty AppDir path.
if [ ! -d "$APPDIR/usr/lib/gstreamer-1.0" ]; then
  unset GST_PLUGIN_SYSTEM_PATH GST_PLUGIN_SYSTEM_PATH_1_0
fi
unset wts_candidate wts_gio_module_dir
EOF
fi

echo "Hardened AppImage AppDir (removed $removed_wayland bundled Wayland libraries)."
