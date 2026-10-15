# Third-party notices

Nothing here is built. CMake fetches pocketfft, CLI11 and Catch2 at the
versions pinned in `cmake/ThirdParty.cmake`, and PortAudio the same way when
live audio is on, or uses a system package where one is installed.

What stays is the licence text each dependency asks to travel with binaries
that include it. `THIRD-PARTY-NOTICES.md` in the repository root is assembled
from these files and is what a release carries.

pocketfft's is the notice block from `pocketfft_hdronly.h` itself rather than
the repository's `LICENSE.md`: the header is what gets compiled in, and it
carries the fuller copyright block of the two.
