/* Isolated candidate ABI extension; no production library is replaced. */
static GDExtensionInterfaceVariantGetPtrUtilityFunction get_utility;
static GDExtensionPtrUtilityFunction engine_lerpf;
static double sw_particle_lerp_engine(double a, double b, double t) {
    double result;
    const GDExtensionConstTypePtr args[] = {&a, &b, &t};
    engine_lerpf(&result, args, 3);
    return result;
}
/* Use the engine's own scalar lerpf implementation, including any architecture
 * specific compiler behavior, rather than assume matching FMA contraction. */
#define SW_PARTICLE_LERP sw_particle_lerp_engine
#include "particle_gate_core.h"
static GDExtensionVariantFromTypeConstructorFunc variant_from_int;
static const GDExtensionVariantType gate_types[8] = {
    GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,
    GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
    GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_FLOAT,
    GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT
};
static int64_t next_candidate(const void *data, const void *previous,
        const void *removed, const void *emerged, int64_t start,
        double blend, double base, double h) {
    int64_t size = 0, old_size = 0, removed_size = 0, emerged_size = 0;
    floats_size((void *)data, 0, &size, 0);
    floats_size((void *)previous, 0, &old_size, 0);
    bytes_size((void *)removed, 0, &removed_size, 0);
    bytes_size((void *)emerged, 0, &emerged_size, 0);
    if (size < 0 || size % 20 != 0 || old_size != size || start < 0) return -1;
    const int64_t count = size / 20;
    if (removed_size != count || emerged_size != count) return -1;
    if (start >= count) return count;
    const float *current_data = floats_read_at(data, 0);
    const float *old_data = floats_read_at(previous, 0);
    const uint8_t *removed_data = bytes_at(removed, 0), *emerged_data = bytes_at(emerged, 0);
    if (!current_data || !old_data || !removed_data || !emerged_data) return -1;
    return sw_next_particle_candidate(current_data, old_data, removed_data, emerged_data,
                                     count, start, blend, base, h);
}
static void gate_call(void *userdata, GDExtensionClassInstancePtr instance,
        const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    (void)userdata; (void)instance;
    error->error = GDEXTENSION_CALL_OK; error->argument = 0; error->expected = 0;
    int64_t found = -1;
    if (argc != 8) {
        error->error = argc < 8 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = 8;
    } else {
        int valid = 1;
        for (int i = 0; i < 8; ++i) {
            GDExtensionVariantType actual = variant_type(args[i]);
            if (actual != gate_types[i] && !(i >= 5 && actual == GDEXTENSION_VARIANT_TYPE_INT)) {
                error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
                error->argument = i; error->expected = gate_types[i]; valid = 0; break;
            }
        }
        if (valid) {
            Value arrays[4]; int64_t start; double scalars[3];
            floats_from_variant(&arrays[0], (void *)args[0]);
            floats_from_variant(&arrays[1], (void *)args[1]);
            bytes_from_variant(&arrays[2], (void *)args[2]);
            bytes_from_variant(&arrays[3], (void *)args[3]);
            int_from_variant(&start, (void *)args[4]);
            for (int i = 0; i < 3; ++i) {
                if (variant_type(args[i + 5]) == GDEXTENSION_VARIANT_TYPE_INT) {
                    int64_t value; int_from_variant(&value, (void *)args[i + 5]); scalars[i] = (double)value;
                } else double_from_variant(&scalars[i], (void *)args[i + 5]);
            }
            found = next_candidate(&arrays[0], &arrays[1], &arrays[2], &arrays[3], start,
                                   scalars[0], scalars[1], scalars[2]);
            floats_dtor(&arrays[0]); floats_dtor(&arrays[1]);
            bytes_dtor(&arrays[2]); bytes_dtor(&arrays[3]);
        }
    }
    destroy_variant(result); variant_from_int(result, &found);
}
static void gate_ptrcall(void *userdata, GDExtensionClassInstancePtr instance,
        const GDExtensionConstTypePtr *args, GDExtensionTypePtr result) {
    (void)userdata; (void)instance;
    *(int64_t *)result = next_candidate(args[0], args[1], args[2], args[3],
        *(const int64_t *)args[4], *(const double *)args[5], *(const double *)args[6], *(const double *)args[7]);
}
static void register_gate_method(void) {
    Value lerp_name;
    make_name(&lerp_name, "lerpf");
    engine_lerpf = get_utility(&lerp_name, INT64_C(998901048));
    name_dtor(&lerp_name);
    if (!engine_lerpf) return;
    variant_from_int = from_type(GDEXTENSION_VARIANT_TYPE_INT);
    if (!variant_from_int) return;
    Value names[10], empty_string;
    const char *text[] = {"find_next_particle_candidate", "data", "previous", "removed", "emerged", "start", "blend", "base", "h", ""};
    for (int i = 0; i < 10; ++i) make_name(&names[i], text[i]);
    make_string(&empty_string, "");
    GDExtensionPropertyInfo args[8];
    GDExtensionClassMethodArgumentMetadata metadata[8];
    for (int i = 0; i < 8; ++i) {
        args[i].type = gate_types[i]; args[i].name = &names[i + 1];
        args[i].class_name = &names[9]; args[i].hint = 0; args[i].hint_string = &empty_string; args[i].usage = 6;
        metadata[i] = i == 4 ? GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64 :
            (i >= 5 ? GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_DOUBLE : GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE);
    }
    GDExtensionPropertyInfo ret = {0};
    ret.type = GDEXTENSION_VARIANT_TYPE_INT; ret.name = &names[9];
    ret.class_name = &names[9]; ret.hint_string = &empty_string; ret.usage = 6;
    GDExtensionClassMethodInfo method = {0};
    method.name = &names[0]; method.call_func = gate_call; method.ptrcall_func = gate_ptrcall;
    method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_CONST;
    method.has_return_value = 1; method.return_value_info = &ret;
    method.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
    method.argument_count = 8; method.arguments_info = args; method.arguments_metadata = metadata;
    register_method(library, &class_name, &method);
    for (int i = 0; i < 10; ++i) name_dtor(&names[i]);
    string_dtor(&empty_string);
}
