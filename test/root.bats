#!/usr/bin/env bats
#
# This suite is dedicated to calculating BATS_ROOT when going through various
# permutations of symlinks. It was inspired by the report in issue #113 that the
# calculation was broken on CentOS, where /bin is symlinked to /usr/bin.
#
# The basic test environment is (all paths relative to BATS_TEST_SUITE_TMPDIR):
#
# - /bin is a relative symlink to /usr/bin, exercising the symlink resolution of
#   the `bats` parent directory (i.e. "${0%/*}")
# - /usr/bin/bats is an absolute symlink to /opt/bats-core/bin/bats, exercising
#   the symlink resolution of the `bats` executable itself (i.e. "${0##*/}")

load test_helper

# This would make a good candidate for a one-time setup/teardown per #39.
setup() {
  make_bats_test_suite_tmpdir
  cd "$BATS_TEST_SUITE_TMPDIR"
  mkdir -p {usr/bin,opt/bats-core}
  "$BATS_ROOT/install.sh" "opt/bats-core"

  ln -s "usr/bin" "bin"

  if [[ ! -L "bin" ]]; then
    cd - >/dev/null
    skip "symbolic links aren't functional on OSTYPE=$OSTYPE"
  fi

  ln -s "$BATS_TEST_SUITE_TMPDIR/opt/bats-core/bin/bats" \
    "$BATS_TEST_SUITE_TMPDIR/usr/bin/bats"
  cd - >/dev/null
}

bats_root_sanity_check() {
  if (( $# < 1 )); then
    set -- "$BASH" "${BATS_TEST_SUITE_TMPDIR}/bin/bats"
  fi

  run "$@" -v
  [ "$status" -eq 0 ]
  [ "${output%% *}" == 'Bats' ]
}

# Mock up executables in the temporary test suite root's /bin/ subdir.
bats_root_link_executables() {
  local path=''

  for path in "$@"; do
    ln -s "$path" "${BATS_TEST_SUITE_TMPDIR}/bin/${path##*/}"
  done
}

# Clean up symlinks in the temporary test suite root's /bin/ subdir.
bats_root_unlink_executables() {
  local path=''

  for path in "$@"; do
    unlink "${BATS_TEST_SUITE_TMPDIR}/bin/${path##*/}"
  done
}

# Mock up executables in the temporary test suite root's /bin/ subdir if and
# only if they can be found by the `command` builtin.
bats_root_link_executables_conditional() {
  local path=''
  local present=()
  local missing=()

  for path in "$@"; do
    command_path=''
    if command_path="$(command -v "$path")"; then
      present+=("$command_path")
    else
      missing+=("$path")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    skip "required executables not available: ${missing[@]}"
  else
    bats_root_link_executables "${present[@]}" "$BASH"
  fi
}

# Run a command with the named executable in the temporary test suite root's
# /bin/ subdir, then clean up after ourselves.
bats_root_with_linked_executable() {
    local cmd="$1"
    shift

    bats_root_link_executables_conditional "$cmd"
    "$@"
    bats_root_unlink_executables "$cmd"
}

# The resolution scheme here is:
#
# - /bin => /usr/bin (relative directory)
# - /usr/bin/foo => /usr/bin/bar (relative executable)
# - /usr/bin/bar => /opt/bats/bin0/bar (absolute executable)
# - /opt/bats/bin0 => /opt/bats/bin1 (relative directory)
# - /opt/bats/bin1 => /opt/bats/bin2 (absolute directory)
# - /opt/bats/bin2/bar => /opt/bats-core/bin/bar (absolute executable)
# - /opt/bats-core/bin/bar => /opt/bats-core/bin/baz (relative executable)
# - /opt/bats-core/bin/baz => /opt/bats-core/bin/bats (relative executable)
bats_root_extreme_symlink_resolution_with_linked_executable() {
  _bats_root_extreme_symlink_resolution_with_linked_executable() {
    cd "$BATS_TEST_SUITE_TMPDIR"
    mkdir -p "opt/bats/bin2"

    ln -s bar usr/bin/foo
    ln -s "$BATS_TEST_SUITE_TMPDIR/opt/bats/bin0/bar" usr/bin/bar
    ln -s bin1 opt/bats/bin0
    ln -s "$BATS_TEST_SUITE_TMPDIR/opt/bats/bin2" opt/bats/bin1
    ln -s "$BATS_TEST_SUITE_TMPDIR/opt/bats-core/bin/bar" opt/bats/bin2/bar
    ln -s baz opt/bats-core/bin/bar
    ln -s bats opt/bats-core/bin/baz

    cd - >/dev/null

    PATH="${BATS_TEST_SUITE_TMPDIR}/bin" bats_root_sanity_check "$BASH" "$BATS_TEST_SUITE_TMPDIR/bin/foo"

    unset -f "${FUNCNAME[0]}"
  }

  if (( $# > 0 )); then
    local cmd="$1"
    shift
  else
    "_${FUNCNAME[0]}"
  fi

  bats_root_with_linked_executable "$cmd" "_${FUNCNAME[0]}" "$@"
}

# Test that Bats can find BATS_ROOT when run via `/bin/bash bats`.
bats_root_non_absolute_path_with_linked_executable() {
  _bats_root_non_absolute_path_with_linked_executable() {
    PATH="${BATS_TEST_SUITE_TMPDIR}/bin" bats_root_sanity_check "$BASH" bats
    unset -f "${FUNCNAME[0]}"
  }

  if (( $# > 0 )); then
    local cmd="$1"
    shift

    bats_root_with_linked_executable "$cmd" "_${FUNCNAME[0]}" "$@"
  else
    "_${FUNCNAME[0]}"
  fi
}

@test "#113: set BATS_ROOT when /bin is a symlink to /usr/bin" {
  bats_root_sanity_check
}

@test "set BATS_ROOT with extreme symlink resolution (realpath)" {
  bats_root_extreme_symlink_resolution_with_linked_executable realpath
}

@test "set BATS_ROOT with extreme symlink resolution (greadlink)" {
  bats_root_extreme_symlink_resolution_with_linked_executable greadlink
}

@test "set BATS_ROOT with extreme symlink resolution (readlink)" {
  bats_root_extreme_symlink_resolution_with_linked_executable readlink
}

@test "set BATS_ROOT with extreme symlink resolution (ruby)" {
  bats_root_extreme_symlink_resolution_with_linked_executable ruby
}

@test "set BATS_ROOT with extreme symlink resolution (perl)" {
  bats_root_extreme_symlink_resolution_with_linked_executable perl
}

@test "set BATS_ROOT with extreme symlink resolution (python)" {
  bats_root_extreme_symlink_resolution_with_linked_executable python
}

@test "set BATS_ROOT with extreme symlink resolution (default)" {
  skip "pure-Bash bats_realpath cannot handle symlink in final path component"
  bats_root_extreme_symlink_resolution_with_linked_executable
}

@test "set BATS_ROOT when bats invoked as a non-absolute path (realpath)" {
  bats_root_non_absolute_path_with_linked_executable realpath
}

@test "set BATS_ROOT when bats invoked as a non-absolute path (greadlink)" {
  bats_root_non_absolute_path_with_linked_executable greadlink
}

@test "set BATS_ROOT when bats invoked as a non-absolute path (readlink)" {
  bats_root_non_absolute_path_with_linked_executable readlink
}

@test "set BATS_ROOT when bats invoked as a non-absolute path (ruby)" {
  bats_root_non_absolute_path_with_linked_executable ruby
}

@test "set BATS_ROOT when bats invoked as a non-absolute path (perl)" {
  bats_root_non_absolute_path_with_linked_executable perl
}

@test "set BATS_ROOT when bats invoked as a non-absolute path (python)" {
  bats_root_non_absolute_path_with_linked_executable python
}

@test "set BATS_ROOT when bats invoked as a non-absolute path (default)" {
  skip "pure-Bash bats_realpath cannot handle symlink in final path component"
  bats_root_non_absolute_path_with_linked_executable
}
