omarchy-node-release-platform() {
  local machine_arch=${1:-$(uname -m)}

  case "$machine_arch" in
  x86_64) printf '%s\n' linux-x64 ;;
  aarch64) printf '%s\n' linux-arm64 ;;
  *)
    echo "Unsupported architecture for the bundled Node.js release: $machine_arch" >&2
    return 1
    ;;
  esac
}

omarchy-find-node-release() {
  local packages_dir=$1
  local node_platform=$2
  local -a node_archives=()

  mapfile -d '' -t node_archives < <(
    find "$packages_dir" -maxdepth 1 -type f -name "node-v*-${node_platform}.tar.gz" -print0
  )

  if ((${#node_archives[@]} != 1)); then
    echo "Expected exactly one bundled Node.js ${node_platform} release in $packages_dir; found ${#node_archives[@]}" >&2
    return 1
  fi

  printf '%s\n' "${node_archives[0]}"
}

omarchy-node-release-version() {
  local node_archive=$1
  local node_platform=$2
  local archive_name=${node_archive##*/}
  local version=${archive_name#node-v}

  version=${version%-${node_platform}.tar.gz}
  if [[ -z $version || $archive_name != "node-v${version}-${node_platform}.tar.gz" ]]; then
    echo "Invalid bundled Node.js release filename: $archive_name" >&2
    return 1
  fi

  printf '%s\n' "$version"
}
