# Change to a new HOME and define some test_* functions and variables.

set -e

command -v tmux >/dev/null

# Export a fresh HOME, so Kakoune runs without user configuration.
HOME=$(mktemp -d)
cd "$HOME"
export TMPDIR=$HOME # Avoid interfering with other kak-lsp processes.
env=$(env)
if printf %s "$env" | grep -q ^XDG_CONFIG_HOME=; then
	XDG_CONFIG_HOME=$HOME/.config
fi
if printf %s "$env" | grep -q ^XDG_RUNTIME_DIR=; then
	XDG_RUNTIME_DIR=$HOME/xdg_runtime_dir
	mkdir -m 700 "$XDG_RUNTIME_DIR"
fi

test_kak_session=session
mkdir .config
mkdir .config/kak-lsp
mkdir .config/kak
cat > .config/kak/kakrc << 'EOF'
evaluate-commands %sh{kak-lsp --kakoune -s $kak_session}
map global user l %{: enter-user-mode lsp<ret>}
# Enable logging since this is only for testing.
set-option global lsp_cmd "%opt{lsp_cmd} -vvvv --log ./log"

# If the test uses a custom kak-lsp.toml, set the location explicitly, to support macOS.
evaluate-commands %sh{
	if [ -f .config/kak-lsp/kak-lsp.toml ]; then
		printf %s 'set-option global lsp_cmd "%opt{lsp_cmd} -c .config/kak-lsp/kak-lsp.toml"'
	fi
}

lsp-enable

EOF

test_tmux_kak_start() {
	test_tmux new-session -d -x 80 -y 7 kak -s "$test_kak_session" "$@"
	test_tmux resize-window -x 80 -y 7 ||: # Workaround for macOS.
	test_sleep
}

cat > .tmux.conf << 'EOF'
# Pass escape through with less delay, as suggested by the Kakoune FAQ.
set -sg escape-time 25
EOF

test_tmux() {
	# tmux can't handle session sockets in paths that are too long, and macOS has a very
	# long $TMPDIR, so use a relative path. Make sure no one calls us from a different dir.
	if [ "$PWD" != "$HOME" ]; then
		echo "error: test_tmux must always be run from the same directory." >&2
		return 1
	fi
	tmux -S .tmux-socket -f .tmux.conf "$@"
}

test_sleep()
{
	if [ -n "$CI" ]; then
		sleep 10
	else
		sleep 1
	fi
}

test_cleanup() {
	test_tmux kill-server ||:
	# Language servers might still be running, so ignore errors for now.
	rm -rf "$HOME" >/dev/null 2>&1 ||:
}
trap test_cleanup EXIT
