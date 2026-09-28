#!/usr/bin/env python3
"""Exercise the guest journal with failure injection, without an emulator."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PACKAGE = "com.riotgames.league.teamfighttactics"
PROPERTY = "debug.mactician.vk_view_cache"
SOURCE = Path(__file__).resolve().parent / "guest-vulkan-view-cache.sh"
MOCK = r'''#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
command = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
state_file = pathlib.Path(os.environ['FAKE_ANDROID_STATE'])
state = json.loads(state_file.read_text())
mutation = command in ('setprop', 'chown', 'chmod', 'chcon', 'mv', 'rm', 'sync') or (command == 'settings' and args[0] != 'get')
if mutation:
    state['mutations'] += 1
    state_file.write_text(json.dumps(state))
    if state['mutations'] == int(os.environ.get('FAIL_MUTATION', '0')):
        sys.exit(77)
if command == 'id': print(0)
elif command == 'pidof': sys.exit(1)
elif command == 'pm': print('package:' + state['base'])
elif command == 'stat':
    p = pathlib.Path(args[-1]); print('0:' + oct(p.stat().st_mode & 0o777)[2:])
elif command == 'sha256sum':
    print(hashlib.sha256(pathlib.Path(args[0]).read_bytes()).hexdigest() + '  ' + args[0])
elif command == 'settings':
    key = args[2]
    if args[0] == 'get': print(state['settings'].get(key, 'null'))
    elif args[0] == 'delete': state['settings'].pop(key, None)
    elif args[0] == 'put': state['settings'][key] = args[3]
elif command == 'getprop': print(state['properties'].get(args[0], ''))
elif command == 'setprop': state['properties'][args[0]] = args[1]
elif command in ('chown', 'chcon', 'sync'): pass
elif command in ('chmod', 'mv', 'rm'):
    os.execv('/bin/' + command, [command] + args)
else: raise RuntimeError(command)
state_file.write_text(json.dumps(state))
'''


class TransactionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mactician-cache-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for command in ("id", "pidof", "pm", "stat", "sha256sum", "settings", "getprop",
                        "setprop", "chown", "chmod", "chcon", "mv", "rm", "sync"):
            p = self.bin / command
            p.write_text(MOCK)
            p.chmod(0o755)
        self.data = self.root / "data"
        native = self.data / "app/~~test" / (PACKAGE + "-test==") / "lib/arm64"
        native.mkdir(parents=True)
        self.base = native.parent.parent / "base.apk"
        self.base.touch()
        self.remote = native / "libVkLayer_Mactician_buffer_view_cache.so"
        self.journal = self.data / "local/tmp" / ("mactician-vulkan-cache-" + PACKAGE) / "state"
        self.state = self.root / "state.json"
        self.original = {"enable_gpu_debug_layers": "0", "gpu_debug_app": "old.app",
                         "gpu_debug_layers": "VK_LAYER_OLD_example"}
        self.reset_state()
        self.script = self.root / "transaction.sh"
        # Only relocate Android's filesystem prefix in the fixture copy. The
        # shipped script has no test mode or alternate journal location.
        self.script.write_text(SOURCE.read_text().replace("/data/", str(self.data) + "/"))
        self.env = {**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                    "FAKE_ANDROID_STATE": str(self.state)}
        self.payload = b"test layer bytes"
        self.sha = hashlib.sha256(self.payload).hexdigest()

    def reset_state(self):
        self.state.write_text(json.dumps({"base": str(self.base), "settings": self.original,
                                         "properties": {PROPERTY: "0"}, "mutations": 0}))

    def run_action(self, action, fail=0, ok=True):
        value = json.loads(self.state.read_text())
        value["mutations"] = 0
        self.state.write_text(json.dumps(value))
        result = subprocess.run(["/bin/sh", str(self.script), action, PACKAGE, self.sha],
                                env={**self.env, "FAIL_MUTATION": str(fail)},
                                text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def prepare(self):
        self.assertEqual(self.run_action("prepare").stdout.strip(), str(self.remote))
        self.remote.write_bytes(self.payload)

    def assert_restored(self):
        state = json.loads(self.state.read_text())
        self.assertEqual(state["settings"], self.original)
        self.assertEqual(state["properties"][PROPERTY], "0")
        self.assertFalse(self.journal.exists())
        self.assertFalse(self.remote.exists())

    def test_normal_round_trip_and_noop_recovery(self):
        self.run_action("recover")
        self.prepare()
        self.run_action("activate")
        self.run_action("recover")
        self.run_action("recover")
        self.assert_restored()

    def test_recovery_after_every_activation_mutation(self):
        for failure in range(1, 10):
            with self.subTest(failure=failure):
                self.prepare()
                self.assertNotEqual(self.run_action("activate", failure, ok=False).returncode, 0)
                self.run_action("recover")
                self.assert_restored()

    def test_recovery_can_be_interrupted_and_retried(self):
        for failure in range(1, 10):
            with self.subTest(failure=failure):
                self.prepare()
                self.run_action("activate")
                self.assertNotEqual(self.run_action("recover", failure, ok=False).returncode, 0)
                self.run_action("recover")
                self.assert_restored()

    def test_crash_after_journal_before_push(self):
        self.run_action("prepare")
        self.run_action("recover")
        self.assert_restored()

    def test_wrong_binary_hash_does_not_activate(self):
        self.prepare()
        self.remote.write_bytes(b"wrong")
        self.assertNotEqual(self.run_action("activate", ok=False).returncode, 0)
        self.assertEqual(json.loads(self.state.read_text())["settings"], self.original)
        self.run_action("recover")
        self.assert_restored()

    def test_preserves_foreign_settings_and_journal(self):
        self.prepare()
        self.run_action("activate")
        state = json.loads(self.state.read_text())
        state["settings"]["gpu_debug_app"] = "foreign.app"
        self.state.write_text(json.dumps(state))
        self.assertNotEqual(self.run_action("recover", ok=False).returncode, 0)
        self.assertEqual(json.loads(self.state.read_text())["settings"]["gpu_debug_app"], "foreign.app")
        self.assertTrue(self.journal.exists())
        self.assertTrue(self.remote.exists())

    def test_rejects_journal_path_injection(self):
        self.prepare()
        fields = self.journal.read_text().splitlines()
        fields[2] = str(self.root / "unrelated")
        self.journal.write_text("\n".join(fields) + "\n")
        self.assertNotEqual(self.run_action("recover", ok=False).returncode, 0)
        self.assertTrue(self.remote.exists())

    def test_missing_original_settings_are_deleted_on_restore(self):
        self.original = {}
        self.reset_state()
        self.prepare()
        self.run_action("activate")
        self.run_action("recover")
        self.assert_restored()


if __name__ == "__main__":
    unittest.main()
