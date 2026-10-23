/* SPDX-License-Identifier: MIT
 * Stateless Godot 4.6 GDExtension. No libc, C++ library, rendering calls,
 * global work buffers, worker threads, allocation outside Godot, or CPU ISA
 * extensions beyond each target's baseline. */
#include "vendor/gdextension_interface.h"
#include "readback_core.h"
#include "occlusion_core.h"

#if defined(_WIN32)
#define SW_EXPORT __declspec(dllexport)
/* MSVC ABI marker: no CRT initialization or floating-point runtime is used. */
int _fltused = 0;
#else
#define SW_EXPORT __attribute__((visibility("default")))
#endif

/* The engine constructs/destructs opaque values. This is deliberately larger
 * than every used 64-bit float/double-build ABI value (maximum Variant: 40).
 * Never read their representation or assume Godot container internals. */
typedef union { uint64_t alignment; uint8_t opaque[64]; } Value;

static GDExtensionClassLibraryPtr library;
static Value class_name, parent_name;
static GDExtensionInterfaceStringNameNewWithUtf8Chars make_name;
static GDExtensionInterfaceStringNewWithUtf8Chars make_string;
static GDExtensionInterfaceVariantGetPtrConstructor get_ctor;
static GDExtensionInterfaceVariantGetPtrDestructor get_dtor;
static GDExtensionInterfaceVariantGetPtrBuiltinMethod get_method;
static GDExtensionInterfaceGetVariantFromTypeConstructor from_type;
static GDExtensionInterfaceGetVariantToTypeConstructor to_type;
static GDExtensionInterfaceVariantGetType variant_type;
static GDExtensionInterfaceVariantDestroy destroy_variant;
static GDExtensionInterfacePackedByteArrayOperatorIndexConst bytes_at;
static GDExtensionInterfacePackedByteArrayOperatorIndex bytes_write_at;
static GDExtensionInterfacePackedFloat32ArrayOperatorIndex floats_at;
static GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst floats_read_at;
static GDExtensionInterfaceClassdbConstructObject2 construct_object;
static GDExtensionInterfaceObjectSetInstance set_instance;
static GDExtensionInterfaceClassdbRegisterExtensionClass5 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionPtrConstructor array_ctor, array_copy_ctor, floats_ctor, bytes_ctor;
static GDExtensionPtrDestructor array_dtor, floats_dtor, bytes_dtor, name_dtor, string_dtor;
static GDExtensionPtrBuiltInMethod array_append, floats_resize, bytes_size, bytes_resize, floats_size;
static GDExtensionVariantFromTypeConstructorFunc variant_from_array, variant_from_floats, variant_from_double, variant_from_bytes;
static GDExtensionTypeFromVariantConstructorFunc bytes_from_variant, int_from_variant, double_from_variant, floats_from_variant;

static GDExtensionPtrBuiltInMethod builtin(GDExtensionVariantType type, const char *name, int64_t hash) {
    Value method_name;
    make_name(&method_name, name);
    GDExtensionPtrBuiltInMethod result = get_method(type, &method_name, hash);
    name_dtor(&method_name);
    return result;
}

static void append_value(Value *array, Value *variant) {
    const GDExtensionConstTypePtr args[] = {variant};
    array_append(array, args, 0, 1);
    destroy_variant(variant);
}

/* Construct an Array in previously uninitialized result storage. */
static void parse(const void *input, int64_t width, double rest_depth, void *result) {
    array_ctor(result, 0);
    int64_t byte_count = 0;
    bytes_size((void *)input, 0, &byte_count, 0);
    if (width <= 0 || byte_count <= 0 || byte_count % 8 != 0 || !sw_finite_double(rest_depth)) return;
    int64_t count = byte_count / 8;
    /* Check square dimensions without multiplying possibly hostile int64s. */
    if (width > count || count / width != width || count % width != 0) return;
    Value fields[3];
    float *output[3];
    const GDExtensionConstTypePtr resize_args[] = {&count};
    int ready = 0;
    for (int channel = 0; channel < 3; ++channel) {
        floats_ctor(&fields[channel], 0);
        ++ready;
        int64_t error = 0;
        floats_resize(&fields[channel], resize_args, &error, 1);
        if (error != 0) goto finish;
        output[channel] = floats_at(&fields[channel], 0);
        if (!output[channel]) goto finish;
    }
    double energy = 0.0, peak = 0.0;
    const uint8_t *data = bytes_at(input, 0);
    if (!data || !sw_parse_rgba16f(data, count, rest_depth,
                                 output[0], output[1], output[2], &energy, &peak)) goto finish;
    for (int channel = 0; channel < 3; ++channel) {
        Value variant;
        variant_from_floats(&variant, &fields[channel]);
        append_value(result, &variant);
    }
    Value variant;
    variant_from_double(&variant, &energy);
    append_value(result, &variant);
    variant_from_double(&variant, &peak);
    append_value(result, &variant);
finish:
    for (int channel = 0; channel < ready; ++channel) floats_dtor(&fields[channel]);
}

static void parse_call(void *userdata, GDExtensionClassInstancePtr instance,
                       const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
                       GDExtensionVariantPtr result, GDExtensionCallError *error) {
    (void)userdata; (void)instance;
    error->error = GDEXTENSION_CALL_OK;
    error->argument = 0;
    error->expected = 0;
    Value parsed;
    if (argc != 3) {
        error->error = argc < 3 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = 3;
        array_ctor(&parsed, 0);
    } else {
        const GDExtensionVariantType expected[] = {GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_FLOAT};
        int valid = 1;
        for (int i = 0; i < 3; ++i) {
            GDExtensionVariantType actual = variant_type(args[i]);
            if (actual != expected[i] && !(i == 2 && actual == GDEXTENSION_VARIANT_TYPE_INT)) {
                error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
                error->argument = i;
                error->expected = expected[i];
                valid = 0;
                break;
            }
        }
        if (!valid) {
            array_ctor(&parsed, 0);
        } else {
            Value bytes;
            int64_t width;
            double rest_depth;
            bytes_from_variant(&bytes, (void *)args[0]);
            int_from_variant(&width, (void *)args[1]);
            if (variant_type(args[2]) == GDEXTENSION_VARIANT_TYPE_INT) {
                int64_t depth_integer;
                int_from_variant(&depth_integer, (void *)args[2]);
                rest_depth = (double)depth_integer;
            } else double_from_variant(&rest_depth, (void *)args[2]);
            parse(&bytes, width, rest_depth, &parsed);
            bytes_dtor(&bytes);
        }
    }
    destroy_variant(result);
    variant_from_array(result, &parsed);
    array_dtor(&parsed);
}

static void parse_ptrcall(void *userdata, GDExtensionClassInstancePtr instance,
                          const GDExtensionConstTypePtr *args, GDExtensionTypePtr result) {
    (void)userdata; (void)instance;
    Value parsed;
    parse(args[0], *(const int64_t *)args[1], *(const double *)args[2], &parsed);
    const GDExtensionConstTypePtr copy_args[] = {&parsed};
    array_dtor(result);
    array_copy_ctor(result, copy_args);
    array_dtor(&parsed);
}

/* All storage is private until both full masks have succeeded. Empty boxes
 * are valid; a malformed packed shape/nonfinite component returns []. */
static void build_masks(const void *boxes, const void *lamps, void *result) {
    array_ctor(result, 0);
    int64_t box_count = 0, lamp_count = 0;
    floats_size((void *)boxes, 0, &box_count, 0);
    floats_size((void *)lamps, 0, &lamp_count, 0);
    if (box_count < 0 || box_count % 6 != 0 || lamp_count != 6) return;
    const float *box_data = box_count ? floats_read_at(boxes, 0) : 0;
    const float *lamp_data = floats_read_at(lamps, 0);
    if ((box_count && !box_data) || !lamp_data) return;
    Value masks[2];
    uint8_t *output[2];
    int64_t pixel_count = SW_MASK_PIXELS;
    const GDExtensionConstTypePtr resize_args[] = {&pixel_count};
    int ready = 0;
    for (int lamp = 0; lamp < 2; ++lamp) {
        bytes_ctor(&masks[lamp], 0);
        ++ready;
        int64_t error = 0;
        bytes_resize(&masks[lamp], resize_args, &error, 1);
        if (error != 0) goto finish;
        output[lamp] = bytes_write_at(&masks[lamp], 0);
        if (!output[lamp]) goto finish;
    }
    if (!sw_build_occlusion_masks(box_data, box_count, lamp_data, lamp_count, output[0], output[1])) goto finish;
    for (int lamp = 0; lamp < 2; ++lamp) {
        Value variant;
        variant_from_bytes(&variant, &masks[lamp]);
        append_value(result, &variant);
    }
finish:
    for (int lamp = 0; lamp < ready; ++lamp) bytes_dtor(&masks[lamp]);
}

static void masks_call(void *userdata, GDExtensionClassInstancePtr instance,
                       const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
                       GDExtensionVariantPtr result, GDExtensionCallError *error) {
    (void)userdata; (void)instance;
    error->error = GDEXTENSION_CALL_OK;
    error->argument = 0;
    error->expected = 0;
    Value parsed;
    if (argc != 2) {
        error->error = argc < 2 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = 2;
        array_ctor(&parsed, 0);
    } else if (variant_type(args[0]) != GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY ||
               variant_type(args[1]) != GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        error->argument = variant_type(args[0]) != GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY ? 0 : 1;
        error->expected = GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY;
        array_ctor(&parsed, 0);
    } else {
        Value boxes, lamps;
        floats_from_variant(&boxes, (void *)args[0]);
        floats_from_variant(&lamps, (void *)args[1]);
        build_masks(&boxes, &lamps, &parsed);
        floats_dtor(&boxes);
        floats_dtor(&lamps);
    }
    destroy_variant(result);
    variant_from_array(result, &parsed);
    array_dtor(&parsed);
}

static void masks_ptrcall(void *userdata, GDExtensionClassInstancePtr instance,
                          const GDExtensionConstTypePtr *args, GDExtensionTypePtr result) {
    (void)userdata; (void)instance;
    Value parsed;
    build_masks(args[0], args[1], &parsed);
    const GDExtensionConstTypePtr copy_args[] = {&parsed};
    array_dtor(result);
    array_copy_ctor(result, copy_args);
    array_dtor(&parsed);
}

static void register_masks_method(void) {
    Value names[4], empty_string;
    const char *text[] = {"build_occlusion_masks", "boxes", "lamps", ""};
    for (int i = 0; i < 4; ++i) make_name(&names[i], text[i]);
    make_string(&empty_string, "");
    GDExtensionPropertyInfo args[2] = {0};
    for (int i = 0; i < 2; ++i) {
        args[i].type = GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY;
        args[i].name = &names[i + 1];
        args[i].class_name = &names[3];
        args[i].hint_string = &empty_string;
        args[i].usage = 6;
    }
    GDExtensionPropertyInfo ret = {0};
    ret.type = GDEXTENSION_VARIANT_TYPE_ARRAY;
    ret.name = &names[3]; ret.class_name = &names[3]; ret.hint_string = &empty_string; ret.usage = 6;
    GDExtensionClassMethodArgumentMetadata metadata[] = {GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE, GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE};
    GDExtensionClassMethodInfo method = {0};
    method.name = &names[0];
    method.call_func = masks_call;
    method.ptrcall_func = masks_ptrcall;
    method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_CONST;
    method.has_return_value = 1;
    method.return_value_info = &ret;
    method.argument_count = 2;
    method.arguments_info = args;
    method.arguments_metadata = metadata;
    register_method(library, &class_name, &method);
    for (int i = 0; i < 4; ++i) name_dtor(&names[i]);
    string_dtor(&empty_string);
}

#include "particle_gate_binding.inc"

static GDExtensionObjectPtr create_instance(void *userdata, GDExtensionBool notify) {
    (void)userdata; (void)notify;
    GDExtensionObjectPtr object = construct_object(&parent_name);
    if (object) set_instance(object, &class_name, object);
    return object;
}
static void free_instance(void *userdata, GDExtensionClassInstancePtr instance) {
    (void)userdata; (void)instance; /* No extension-owned instance state. */
}

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    make_name(&class_name, "SourceWaterReadback");
    make_name(&parent_name, "RefCounted");
    GDExtensionClassCreationInfo5 cls = {0};
    cls.is_exposed = 1;
    cls.create_instance_func = create_instance;
    cls.free_instance_func = free_instance;
    register_class(library, &class_name, &parent_name, &cls);
    Value names[5], empty_string;
    const char *text[] = {"parse_rgba16f", "bytes", "width", "rest_depth", ""};
    for (int i = 0; i < 5; ++i) make_name(&names[i], text[i]);
    make_string(&empty_string, "");
    GDExtensionPropertyInfo arg_info[3] = {0};
    GDExtensionVariantType types[] = {GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_FLOAT};
    for (int i = 0; i < 3; ++i) {
        arg_info[i].type = types[i];
        arg_info[i].name = &names[i + 1];
        arg_info[i].class_name = &names[4];
        arg_info[i].hint_string = &empty_string;
        arg_info[i].usage = 6; /* PROPERTY_USAGE_DEFAULT. */
    }
    GDExtensionPropertyInfo ret = {0};
    ret.type = GDEXTENSION_VARIANT_TYPE_ARRAY;
    ret.name = &names[4]; ret.class_name = &names[4]; ret.hint_string = &empty_string; ret.usage = 6;
    GDExtensionClassMethodArgumentMetadata metadata[] = {GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE, GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64, GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_DOUBLE};
    GDExtensionClassMethodInfo method = {0};
    method.name = &names[0];
    method.call_func = parse_call;
    method.ptrcall_func = parse_ptrcall;
    method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_CONST;
    method.has_return_value = 1;
    method.return_value_info = &ret;
    method.argument_count = 3;
    method.arguments_info = arg_info;
    method.arguments_metadata = metadata;
    register_method(library, &class_name, &method);
    for (int i = 0; i < 5; ++i) name_dtor(&names[i]);
    string_dtor(&empty_string);
    register_masks_method();
    register_gate_method();
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    unregister_class(library, &class_name);
    name_dtor(&class_name);
    name_dtor(&parent_name);
}

SW_EXPORT GDExtensionBool source_water_library_init(GDExtensionInterfaceGetProcAddress get,
        GDExtensionClassLibraryPtr lib, GDExtensionInitialization *init) {
    library = lib;
#define LOAD(field, type, name) do { field = (type)(void *)get(name); if (!field) return 0; } while (0)
    LOAD(make_name, GDExtensionInterfaceStringNameNewWithUtf8Chars, "string_name_new_with_utf8_chars");
    LOAD(make_string, GDExtensionInterfaceStringNewWithUtf8Chars, "string_new_with_utf8_chars");
    LOAD(get_ctor, GDExtensionInterfaceVariantGetPtrConstructor, "variant_get_ptr_constructor");
    LOAD(get_dtor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
    LOAD(get_method, GDExtensionInterfaceVariantGetPtrBuiltinMethod, "variant_get_ptr_builtin_method");
    LOAD(from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
    LOAD(get_utility, GDExtensionInterfaceVariantGetPtrUtilityFunction, "variant_get_ptr_utility_function");
    LOAD(to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
    LOAD(variant_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
    LOAD(destroy_variant, GDExtensionInterfaceVariantDestroy, "variant_destroy");
    LOAD(bytes_at, GDExtensionInterfacePackedByteArrayOperatorIndexConst, "packed_byte_array_operator_index_const");
    LOAD(bytes_write_at, GDExtensionInterfacePackedByteArrayOperatorIndex, "packed_byte_array_operator_index");
    LOAD(floats_at, GDExtensionInterfacePackedFloat32ArrayOperatorIndex, "packed_float32_array_operator_index");
    LOAD(floats_read_at, GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst, "packed_float32_array_operator_index_const");
    LOAD(construct_object, GDExtensionInterfaceClassdbConstructObject2, "classdb_construct_object2");
    LOAD(set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance");
    LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass5, "classdb_register_extension_class5");
    LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
    LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
#undef LOAD
    array_ctor = get_ctor(GDEXTENSION_VARIANT_TYPE_ARRAY, 0);
    array_copy_ctor = get_ctor(GDEXTENSION_VARIANT_TYPE_ARRAY, 1);
    floats_ctor = get_ctor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, 0);
    bytes_ctor = get_ctor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
    array_dtor = get_dtor(GDEXTENSION_VARIANT_TYPE_ARRAY);
    floats_dtor = get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
    bytes_dtor = get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    name_dtor = get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    string_dtor = get_dtor(GDEXTENSION_VARIANT_TYPE_STRING);
    array_append = builtin(GDEXTENSION_VARIANT_TYPE_ARRAY, "append", INT64_C(3316032543));
    floats_resize = builtin(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, "resize", INT64_C(848867239));
    bytes_size = builtin(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, "size", INT64_C(3173160232));
    bytes_resize = builtin(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, "resize", INT64_C(848867239));
    floats_size = builtin(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, "size", INT64_C(3173160232));
    variant_from_array = from_type(GDEXTENSION_VARIANT_TYPE_ARRAY);
    variant_from_floats = from_type(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
    variant_from_double = from_type(GDEXTENSION_VARIANT_TYPE_FLOAT);
    variant_from_bytes = from_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    bytes_from_variant = to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    floats_from_variant = to_type(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
    int_from_variant = to_type(GDEXTENSION_VARIANT_TYPE_INT);
    double_from_variant = to_type(GDEXTENSION_VARIANT_TYPE_FLOAT);
    if (!array_ctor || !array_copy_ctor || !floats_ctor || !array_dtor || !floats_dtor || !bytes_dtor ||
        !name_dtor || !string_dtor || !array_append || !floats_resize || !bytes_size ||
        !variant_from_array || !variant_from_floats || !variant_from_double ||
        !bytes_from_variant || !int_from_variant || !double_from_variant ||
        !bytes_ctor || !bytes_resize || !floats_size || !variant_from_bytes || !floats_from_variant) return 0;
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    init->userdata = 0;
    init->initialize = initialize;
    init->deinitialize = deinitialize;
    return 1;
}
