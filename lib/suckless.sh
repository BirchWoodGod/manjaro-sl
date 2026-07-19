#!/usr/bin/env bash
# Build helpers for the suckless components and j4-dmenu-desktop.

component_selected() {
  local target="$1"
  for component in "${COMPONENTS[@]}"; do
    if [ "$component" = "$target" ]; then
      return 0
    fi
  done
  return 1
}

clean_build_artifacts() {
  echo "==> Cleaning build artifacts"

  # Remove binary executables
  local binaries=(
    "${REPO_ROOT}/dwm/dwm"
    "${REPO_ROOT}/dmenu/dmenu"
    "${REPO_ROOT}/dmenu/stest"
    "${REPO_ROOT}/st/st"
    "${REPO_ROOT}/slstatus/slstatus"
    "${REPO_ROOT}/dmenu/j4-dmenu-desktop/j4-dmenu-desktop"
    "${REPO_ROOT}/doomfire/doomfire"
    "${REPO_ROOT}/xmatrix/xmatrix"
  )

  for binary in "${binaries[@]}"; do
    if [ -f "$binary" ]; then
      rm -f "$binary"
      echo "Removed: $(basename "$binary")"
    fi
  done

  # Remove object files from component directories
  local components=("dwm" "dmenu" "st" "slstatus" "doomfire" "xmatrix")
  for component in "${components[@]}"; do
    local component_dir="${REPO_ROOT}/${component}"
    if [ -d "$component_dir" ]; then
      find "$component_dir" -name "*.o" -type f -delete 2>/dev/null || true
    fi
  done

  # Remove j4-dmenu-desktop object files
  local j4_dir="${REPO_ROOT}/dmenu/j4-dmenu-desktop"
  if [ -d "$j4_dir" ]; then
    find "$j4_dir" -name "*.o" -type f -delete 2>/dev/null || true
  fi

  # Remove patch artifacts
  find "$REPO_ROOT" -name "*.orig" -type f -not -path '*/.git/*' -delete 2>/dev/null || true
  find "$REPO_ROOT" -name "*.rej" -type f -not -path '*/.git/*' -delete 2>/dev/null || true

  # Remove j4-dmenu-desktop build directories
  local build_dir
  for build_dir in "${REPO_ROOT}/dmenu/j4-dmenu-desktop/build" "${REPO_ROOT}/dmenu/j4-dmenu-desktop/build-cmake"; do
    if [ -d "$build_dir" ]; then
      rm -rf "$build_dir"
      echo "Removed: j4-dmenu-desktop/$(basename "$build_dir")/"
    fi
  done

  echo "Build artifacts cleaned."
  echo
}

build_j4_with_meson() {
  local j4_dir="$1"
  local build_dir="${j4_dir}/build"

  command -v meson >/dev/null 2>&1 || return 1

  if [ ! -d "$build_dir" ]; then
    if ! (cd "$j4_dir" && ./meson-setup.sh build); then
      echo "Warning: meson setup for j4-dmenu-desktop failed (it needs meson >= 1.1)." >&2
      rm -rf "$build_dir"
      return 1
    fi
  fi
  if ! (cd "$j4_dir" && meson compile -C build); then
    echo "Warning: j4-dmenu-desktop meson build failed." >&2
    return 1
  fi
  (cd "$j4_dir" && run_with_privilege meson install -C build)
}

build_j4_with_cmake() {
  local j4_dir="$1"
  local build_dir="${j4_dir}/build-cmake"

  command -v cmake >/dev/null 2>&1 || return 1

  if [ ! -d "$build_dir" ]; then
    mkdir -p "$build_dir"
    if ! (cd "$build_dir" && cmake ..); then
      echo "Warning: cmake setup for j4-dmenu-desktop failed." >&2
      rm -rf "$build_dir"
      return 1
    fi
  fi
  if ! (cd "$build_dir" && make); then
    echo "Warning: j4-dmenu-desktop cmake build failed." >&2
    return 1
  fi
  (cd "$build_dir" && run_with_privilege make install)
}

build_j4_dmenu_desktop() {
  local j4_dir="${REPO_ROOT}/dmenu/j4-dmenu-desktop"

  if [ ! -d "$j4_dir" ]; then
    echo "Warning: j4-dmenu-desktop directory not found at ${j4_dir}. Skipping j4-dmenu-desktop build." >&2
    return
  fi

  echo "==> Building j4-dmenu-desktop"

  # Prefer meson, but fall back to cmake if the meson path fails — distro
  # releases with meson < 1.1 (e.g. 22.04-based Pop!_OS) can't parse its
  # meson.build.
  if build_j4_with_meson "$j4_dir" || build_j4_with_cmake "$j4_dir"; then
    echo "j4-dmenu-desktop build complete."
  else
    echo "Warning: could not build j4-dmenu-desktop (needs meson >= 1.1 or cmake >= 3.16)." >&2
    echo "dmenu itself is unaffected; install one of those and re-run for desktop entry support." >&2
  fi
  echo
}

build_components() {
  for component in "${COMPONENTS[@]}"; do
    target_dir="${REPO_ROOT}/${component}"
    if [ ! -d "${target_dir}" ]; then
      echo "Skipping ${component}: directory not found." >&2
      continue
    fi

    echo "==> Building ${component}";
    # Build as the invoking user so the repo doesn't fill with root-owned
    # artifacts; only the install step needs privilege.
    (cd "${target_dir}" && make clean && make)
    (cd "${target_dir}" && run_with_privilege make install)
    echo
    echo "${component} build complete."
    echo

    # Build j4-dmenu-desktop after dmenu is built
    if [ "$component" = "dmenu" ]; then
      build_j4_dmenu_desktop
    fi

  done

  echo "All requested components built."
}
