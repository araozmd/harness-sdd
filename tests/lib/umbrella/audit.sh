AU="$(mktemp -d 2>/dev/null || mktemp -d -t harness-audit)"
# mk_umb <dir> <child>... — an umbrella with git children, each with one commit.
mk_umb() {
  _u="$1"; shift
  mkdir -p "$_u"
  for _ch in "$@"; do
    mkdir -p "$_u/$_ch"
    git -C "$_u/$_ch" init -q .
    git -C "$_u/$_ch" config user.email "test@harness.local"
    git -C "$_u/$_ch" config user.name "harness test"
    echo seed > "$_u/$_ch/README.md"
    git -C "$_u/$_ch" add -A
    git -C "$_u/$_ch" commit -q -m init
  done
}
cascade() {  # cascade <umbrella> [extra args...] -> AU_OUT / AU_RC
  _u="$1"; shift
  AU_OUT="$(CODEX_HOME="$_u/.ch" HOME="$_u/.home" sh "$SRC/harness-install.sh" --umbrella "$_u" --agents=claude "$@" 2>&1)" && AU_RC=0 || AU_RC=$?
}
land() { git -C "$1" add -A && git -C "$1" commit -q -m "land the harness"; }
