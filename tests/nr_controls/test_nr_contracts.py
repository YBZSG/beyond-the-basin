"""CPU-only source/launch contracts. Never imports, builds or starts Godot/NGX."""
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASE_PATCH = ROOT / "tools/dlss/engine-dlss-nr.patch"
CONTROLS_PATCH = ROOT / "tools/dlss/engine-dlss-nr-controls.patch"
EFFECTS = "servers/rendering/renderer_rd/effects"
spec = importlib.util.spec_from_file_location("nr_run_qa", ROOT / "tools/dlss/run_qa.py")
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)  # main guard must prevent launch side effects.


def new_file_from_patch(text, name):
    part = text.split("+++ b/" + name + "\n", 1)[1].split("\n--- ", 1)[0]
    return "\n".join(line[1:] for line in part.splitlines() if line.startswith("+")) + "\n"


def apply_controls_fixture(directory):
    """Apply the real incremental patch to original source embedded in the base patch.

    This checks only these exact files/contexts, NOT the entire pinned engine tree.
    """
    text = BASE_PATCH.read_text()
    for name in ("dlss_nr.cpp", "dlss_nr.h"):
        path = directory / EFFECTS / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(new_file_from_patch(text, EFFECTS + "/" + name))
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith("+\tif (can_use_storage && !dest_is_msaa_2d"))
    end = next(i for i in range(start, len(lines)) if "render_target_disable_clear_request(render_target)" in lines[i])
    renderer = directory / "servers/rendering/renderer_rd/renderer_scene_render_rd.cpp"
    renderer.write_text("\n".join(line[1:] for line in lines[start:end + 1]) + "\n")
    # Exact read-only source context independently verified at pinned NVIDIA Godot commit:
    # 135dff3887a3d2ccf45cafbd9bdffa7b718e1e76, graph.cpp lines 1952-1961.
    graph = directory / "servers/rendering/rendering_device_graph.cpp"
    graph.write_text('void RenderingDeviceGraph::add_driver_callback(RDD::DriverCallback p_callback, void *p_userdata, VectorView<ResourceTracker *> p_trackers, VectorView<RenderingDeviceGraph::ResourceUsage> p_usages) {\n\tDEV_ASSERT(p_trackers.size() == p_usages.size());\n\n\tint32_t command_index;\n\tRecordedDriverCallbackCommand *command = static_cast<RecordedDriverCallbackCommand *>(_allocate_command(sizeof(RecordedDriverCallbackCommand), command_index));\n\tcommand->type = RecordedCommand::TYPE_DRIVER_CALLBACK;\n\tcommand->callback = p_callback;\n\tcommand->userdata = p_userdata;\n\t_add_command_to_graph((ResourceTracker **)p_trackers.ptr(), (ResourceUsage *)p_usages.ptr(), p_trackers.size(), command_index, command);\n}\n')
    subprocess.run(["git", "apply", "--check", str(CONTROLS_PATCH)], cwd=directory, check=True, capture_output=True, text=True)
    subprocess.run(["git", "apply", str(CONTROLS_PATCH)], cwd=directory, check=True, capture_output=True, text=True)
    return (directory / EFFECTS / "dlss_nr.cpp").read_text()


class ProfileRoutingTests(unittest.TestCase):
    def test_nr_cli_overrides_copied_saved_value_both_directions(self):
        for mode, saved, expected in (("on", "false", "true"), ("off", "true", "false")):
            text = f'[graphics]\nnr={saved}\nframe_generation=true\ndlss="Performance"\nnr_layers=4\nwater="Ultra"\n'
            result = qa.configure_nr_profile(text, mode)
            self.assertIn(f"nr={expected}\n", result)
            self.assertIn("frame_generation=false\n", result)
            self.assertIn('dlss="DLAA"\n', result)
            self.assertIn("nr_layers=4\n", result)
            self.assertIn('water="Ultra"\n', result)

    def test_missing_section_and_key_and_explicit_rt(self):
        result = qa.configure_nr_profile("[other]\nnr=false\n", "on", "on")
        self.assertTrue(result.startswith("[other]\nnr=false\n"))
        self.assertIn("[graphics]\nnr=true\n", result)
        self.assertIn("raytracing=true\n", result)

    def test_only_graphics_section_changes_and_duplicates_collapse(self):
        result = qa.configure_nr_profile("[other]\nnr=true\n[graphics]\n nr = true\nnr=true\n[after]\nnr=true\n", "off")
        graphics = result.split("[graphics]\n")[1].split("[after]")[0]
        self.assertEqual(len(re.findall(r"^nr=", graphics, re.M)), 1)
        self.assertIn("nr=false\n", graphics)
        self.assertTrue(result.startswith("[other]\nnr=true\n"))
        self.assertTrue(result.endswith("[after]\nnr=true\n"))

    def test_launch_configuration_does_not_prevent_later_explicit_change(self):
        launch = qa.configure_nr_profile("[graphics]\nnr=false\n", "on")
        live = qa.set_graphics_values(launch, {"nr": "false"})
        self.assertIn("nr=false\n", live)
        self.assertNotIn("nr=true\n", live)

    def test_log_contract_catches_wrong_off_baseline(self):
        ok = "PoolCore NR dispatch OK frame=1 layers=4"
        failure = ok + "\nPoolCore NR evaluate FAILED"
        self.assertTrue(qa.nr_evidence_failed("off", False, ok))
        self.assertFalse(qa.nr_evidence_failed("off", False, ""))
        self.assertTrue(qa.nr_evidence_failed("on", False, ""))
        self.assertTrue(qa.nr_evidence_failed("on", False, failure))
        self.assertFalse(qa.nr_evidence_failed("on", False, ok))
        self.assertTrue(qa.nr_evidence_failed("on", True, ok))
        self.assertFalse(qa.nr_evidence_failed("on", True, ""))
        self.assertFalse(qa.nr_evidence_failed(None, False, ""))


class NativeSourceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory(prefix="poolcore-nr-contract-")
        cls.directory = Path(cls.fixture.name)
        cls.source = apply_controls_fixture(cls.directory)

    @classmethod
    def tearDownClass(cls):
        cls.fixture.cleanup()

    def test_build_applies_additive_patch_last(self):
        source = (ROOT / "tools/dlss/build_nr.py").read_text()
        self.assertIn('"engine-dlss-nr.patch", "engine-dlss-nr-controls.patch"]', source)

    def test_distinct_features_outputs_and_history_reset(self):
        source = self.source
        self.assertIn("*features[PoolCoreNR::MAX_LAYERS]", source)
        self.assertIn("&nr.features[layer]", source)
        self.assertIn("nr.features[layer] == nr.features[previous]", source)
        self.assertIn("sdk_returned_shared_history_handle", source)
        self.assertIn("NVSDK_NGX_FAILED(result) || !nr.features[layer]", source)
        self.assertLess(source.index("sdk_returned_shared_history_handle"), source.index("NVSDK_NGX_FAILED(result) || !nr.features[layer]"))
        self.assertIn("layer == 0 ? frame.input : frame.outputs[layer - 1]", source)
        self.assertIn("NGX_VULKAN_EVALUATE_DLSSNR_EXT(cmd, nr.features[layer]", source)
        self.assertIn("frame.reset || nr.history_frames[layer] == 0", source)
        self.assertIn("nr.controls.layers - 1", source)
        self.assertIn("VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT", source)
        self.assertIn("resources, 4 + nr.controls.layers", source)

    def test_failure_restores_original_not_partial_and_never_marks_partial_success(self):
        restore = self.source.split("void restore_original(", 1)[1].split("void evaluate(", 1)[0]
        self.assertIn("resource(frame.input, false)", restore)
        self.assertIn("frame.outputs[frame.controls.layers - 1]", restore)
        failure = self.source.split("PoolCore NR evaluate FAILED", 1)[1].split("nr.history_frames[layer]++", 1)[0]
        self.assertIn("restore_original(cmd, frame)", failure)
        self.assertIn("return;", failure)
        self.assertNotIn("status.applied_layers =", failure)

    def test_resource_validation_precedes_allocation_and_callback_owns_only_on_success(self):
        process = self.source.split("void RendererRD::DLSSNR::process(", 1)[1].split("void RendererRD::DLSSNR::bypass(", 1)[0]
        for rid in ("target", "nr.input", "nr.mask", "depth", "velocity", "nr.outputs[layer]"):
            self.assertIn("rd->texture_is_valid(" + rid + ")", process)
        invalid_guard = process.index("if (!valid_resources)")
        self.assertLess(invalid_guard, process.index("rd->texture_clear("))
        self.assertLess(invalid_guard, process.index("memnew(NRFrame)"))
        self.assertIn('fail("invalid_or_retired_texture_resource")', process)
        self.assertIn("const Error enqueue_error = rd->driver_callback_add", process)
        enqueue_failure = process.split("if (enqueue_error != OK)", 1)[1].split("String capture", 1)[0]
        self.assertIn("memdelete(frame)", enqueue_failure)
        self.assertIn("callback_enqueue_failed_", enqueue_failure)
        self.assertIn("return;", enqueue_failure)
        self.assertNotIn("copy_to_fb_rect", enqueue_failure)
        self.assertLess(process.index("if (enqueue_error != OK)"), process.index("copy->copy_to_fb_rect(nr.outputs"))
        callback = self.source.split("void evaluate(", 1)[1].split("void RendererRD::DLSSNR::process(", 1)[0]
        self.assertIn("memdelete(static_cast<NRFrame *>(userdata))", callback)

    def test_strength_fields_and_process_local_fresh_status(self):
        for key in ("process_id", "emitted_msec", "successful_frames", "requested_revision", "applied_revision", "requested_layers", "applied_layers"):
            self.assertIn('data["' + key + '"]', self.source)
        self.assertIn("now - status.last_emit_msec < 1000", self.source)
        self.assertIn("p.InIntensity = frame.controls.intensity", self.source)
        self.assertIn("p.InLocalToneStrength = frame.controls.tone", self.source)
        self.assertIn("p.InLocalStructureStrength = frame.controls.structure", self.source)
        self.assertIn('inactive_status(false, "bypassed", "engine_without_nr_sdk")', self.source)
        self.assertIn("if (parser.parse(raw) != OK) { return cached; }", self.source)

    def test_locked_primary_reports_small_or_multiview_bypass(self):
        candidate = self.source.split("bool is_main_candidate(", 1)[1].split("void release_features(", 1)[0]
        self.assertLess(candidate.index("if (!nr.primary_target.is_null())"), candidate.index("rb->get_view_count() == 1"))
        self.assertIn("return nr.primary_target == rb->get_render_target()", candidate)
        process = self.source.split("void RendererRD::DLSSNR::process(", 1)[1].split("void RendererRD::DLSSNR::bypass(", 1)[0]
        self.assertIn("rb->get_view_count() != 1 || rb->get_target_size().x < 960", process)
        self.assertIn('inactive_status(true, "bypassed", "requires_single_view_width_at_least_960")', process)

    def test_resize_layers_preset_cleanup_and_outer_bypass(self):
        self.assertIn("status.requested.layers != nr.allocated_layers", self.source)
        self.assertIn("size != nr.size", self.source)
        self.assertIn("preset != nr.preset", self.source)
        self.assertIn("vkDeviceWaitIdle(nr.device); release_features()", self.source)
        self.assertIn('rb->clear_context(SNAME("PoolCoreNR"))', self.source)
        renderer = (self.directory / "servers/rendering/renderer_rd/renderer_scene_render_rd.cpp").read_text()
        self.assertIn('DLSSNR::bypass(rb, "requires_storage_sdr_without_2d_msaa")', renderer)

    def test_external_callback_has_entry_exit_execution_stages(self):
        graph = (self.directory / "servers/rendering/rendering_device_graph.cpp").read_text()
        self.assertIn("command->self_stages = RDD::PIPELINE_STAGE_ALL_COMMANDS_BIT;", graph)
        self.assertLess(graph.index("command->self_stages"), graph.index("_add_command_to_graph"))

    def test_off_fg_device_sdk_boundaries_and_no_per_layer_device_idle(self):
        process = self.source.split("void RendererRD::DLSSNR::process(", 1)[1].split("void RendererRD::DLSSNR::bypass(", 1)[0]
        self.assertIn('inactive_status(true, "off", "not_requested")', process)
        self.assertIn('inactive_status(true, "bypassed", "frame_generation_enabled")', process)
        self.assertIn('inactive_status(true, "bypassed", "requires_vulkan")', process)
        self.assertIn('inactive_status(true, "bypassed", "requires_dlss_motion_inputs")', process)
        self.assertIn('status.capability = "unavailable"', self.source)
        self.assertIn('inactive_status(false, "bypassed", "engine_without_nr_sdk")', self.source)
        evaluate = self.source.split("void evaluate(", 1)[1].split("void RendererRD::DLSSNR::process(", 1)[0]
        release = self.source.split("void release_features(", 1)[1].split("void fail(", 1)[0]
        self.assertNotIn("vkDeviceWaitIdle", evaluate)
        self.assertNotIn("vkDeviceWaitIdle", release)
        self.assertEqual(self.source.count("vkDeviceWaitIdle"), 2)  # Recreation and shutdown only.

    def test_actual_sdk_independent_validation_header(self):
        compiler = shutil.which("c++") or shutil.which("g++")
        if not compiler:
            self.skipTest("No C++ compiler; full engine remains untested regardless")
        binary = self.directory / "native-validation"
        subprocess.run([compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-I", str(self.directory / EFFECTS), str(ROOT / "tests/nr_controls/native_validation.cpp"), "-o", str(binary)], check=True, capture_output=True, text=True)
        subprocess.run([str(binary)], check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
