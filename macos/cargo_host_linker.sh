#!/bin/sh
# The linker cargo uses for aarch64-apple-darwin, set from the Podfile for
# super_native_extensions: Xcode's own, without chained fixups, which the
# linker of Xcode 27 writes into a dylib in a form rustc cannot read back.
exec cc "$@" -Wl,-no_fixup_chains
