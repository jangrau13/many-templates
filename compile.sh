#!/bin/sh
# Whether the submission builds, which is what a patch probe rests on: a diff
# the examiner wrote and that does not compile has to come back as the
# examiner's mistake, before anything is run and before any of it is put to the
# candidate.
#
# erlc writes .beam files beside the source and /work is root-owned, so -o
# points them at /build instead.
set -eu

# $TMPDIR is set to /build/tmp by the image; the tmpfs is mounted fresh for
# each session, so the directory itself has to be made here rather than baked in.
mkdir -p "${TMPDIR:-/build/tmp}"
OUT=/build/viva-compile
rm -rf "$OUT"
mkdir -p "$OUT"

cd /work
if [ ! -f sup.erl ]; then
  echo "the submission has no sup.erl at its root"
  exit 2
fi

# Every module at the root, not only sup.erl: a submission that split its
# helpers out is still a submission that has to build.
#
# No +warnings_as_errors. erlc already exits non-zero for an error and zero for
# a warning, and that is exactly the line this script is here to draw — a patch
# refused over an unused variable would be refused for nothing.
erlc -o "$OUT" *.erl 2>&1
