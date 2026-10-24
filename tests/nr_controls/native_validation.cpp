// Tests the actual SDK-independent helper extracted from the additive engine patch.
// This is NOT a Godot, Vulkan, NGX or GPU runtime test.
#include "dlss_nr_controls.h"
#include <cassert>
#include <initializer_list>
#include <limits>
int main() {
    using namespace PoolCoreNR;
    Controls defaults;
    assert(defaults.layers == 1 && defaults.intensity == 1.0f);
    assert(defaults.tone == 0.1f && defaults.structure == 0.5f);
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double inf = std::numeric_limits<double>::infinity();
    for (double invalid : {nan, inf, -inf}) {
        assert(strength(invalid, .1f) == .1f);
        assert(layers(invalid) == 1);
        assert(revision(invalid) == 0);
    }
    assert(strength(-1, .5f) == 0 && strength(2, .5f) == 1);
    assert(strength(.75, .5f) == .75f);
    assert(layers(-10) == 1 && layers(0) == 1);
    assert(layers(1) == 1 && layers(2) == 2 && layers(3) == 3 && layers(4) == 4);
    assert(layers(99) == 4 && layers(1e100) == 4 && layers(2.5) == 1);
    assert(revision(-1) == 0 && revision(1.2) == 0);
    assert(revision(3600000000.0) == 3600000000LL);
    assert(revision(2147483648.0) == 2147483648LL); // Monotonic microseconds exceed 32 bits quickly.
    assert(revision(9007199254740991.0) == 9007199254740991LL);
    assert(revision(9007199254740992.0) == 0);
    Controls revised = defaults;
    revised.revision = 42;
    assert(defaults.same_values(revised)); // A protocol revision alone is not a strength change.
    revised.layers = 4;
    assert(!defaults.same_values(revised));
    revised = defaults; revised.tone = .3f;
    assert(!defaults.same_values(revised));
    revised = defaults; revised.structure = .9f;
    assert(!defaults.same_values(revised));
    revised = defaults; revised.intensity = .2f;
    assert(!defaults.same_values(revised));
}
