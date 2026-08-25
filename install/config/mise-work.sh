# Setup default work directory (and tries)
mkdir -p "$HOME/Work"
mkdir -p "$HOME/Work/tries"

# Add ./bin to path for all items in ~/Work
cat >"$HOME/Work/.mise.toml" <<'EOF'
[env]
_.path = "{{ cwd }}/bin"
EOF

mise trust ~/Work/.mise.toml

if [[ -n ${OMARCHY_CHROOT_INSTALL:-} ]]; then
  source "$OMARCHY_INSTALL/helpers/node-release.sh"

  node_platform=$(omarchy-node-release-platform)
  NODE_TARBALL=$(omarchy-find-node-release /opt/packages "$node_platform")
  NODE_VERSION=$(omarchy-node-release-version "$NODE_TARBALL" "$node_platform")
  NODE_INSTALL_DIR="$HOME/.local/share/mise/installs/node/$NODE_VERSION"

  mkdir -p "$NODE_INSTALL_DIR"
  tar -xzf "$NODE_TARBALL" \
    --strip-components=1 \
    -C "$NODE_INSTALL_DIR"

  mise use -g node@"$NODE_VERSION"
else
  mise use -g node@latest
fi
