# Third-party notices

Nothing here is built. CMake fetches pocketfft and, when live audio is on,
PortAudio at the versions pinned in `cmake/ThirdParty.cmake`. CLI11 and Catch2
use installed system packages where available, or the pinned versions otherwise.

What stays is the licence text each dependency asks to travel with binaries
that include it. `THIRD-PARTY-NOTICES.md` in the repository root is assembled
from these files and is what a release carries.

pocketfft's is the notice block from `pocketfft_hdronly.h` itself rather than
the repository's `LICENSE.md`: the header is what gets compiled in, and it
carries the fuller copyright block of the two.
