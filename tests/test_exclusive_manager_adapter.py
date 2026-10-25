import importlib.util
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('adapter', Path(__file__).resolve().parents[1] / 'scripts/patch-editor-authorization.py')
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class ExclusiveManagerTests(unittest.TestCase):
    def test_missing_symbol_denies_and_present_symbol_controls_manager_modes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            objects = []
            for mode in ['active', 'forbid', 'allow']:
                data, source = adapter.make_exclusive_shim(0x4000, mode)
                self.assertLessEqual(len(data), 0x200)
                self.assertIn(b'MbsHasVerifiedEditorLicense\0', data)
                self.assertNotIn(b'MbsEditorLicenseVerified\0', data)
                # Verify the generated on-disk call is the exact dlsym import.
                at = source.splitlines().index('    brk #1')
                prefix = source.splitlines()[4:at]
                instructions = [s for s in prefix if s.strip() and not s.endswith(':')]
                offset = len(instructions)*4
                self.assertEqual(data[offset:offset+4], adapter.branch(0x4000+offset, adapter.DLSYM_STUB, True))
                source = source.replace('_adapter:', '.globl _test_'+mode+'\n_test_'+mode+':').replace('brk #1', 'bl _dlsym')
                asm = root / (mode+'.s')
                obj = root / (mode+'.o')
                asm.write_text(source)
                subprocess.run(['clang', '-c', str(asm), '-o', str(obj)], check=True)
                objects.append(str(obj))
            fixture = root / 'fixture.cpp'
            fixture.write_text('''
#include <assert.h>
extern "C" bool test_active(void *,int *);
extern "C" bool test_forbid(void *,int *);
extern "C" bool test_allow(void *,int *);
static bool enabled;
#ifdef HAS_MBS_DECISION
extern "C" bool MbsHasVerifiedEditorLicense() { return enabled; }
#endif
int main() {
    int level=99;
    assert(!test_active(nullptr,&level) && level==0);
    assert(test_forbid(nullptr,nullptr) && !test_allow(nullptr,nullptr));
    enabled=true;
#ifdef HAS_MBS_DECISION
    assert(test_active(nullptr,&level) && level==2);
    assert(test_active(nullptr,nullptr));
    assert(!test_forbid(nullptr,nullptr) && test_allow(nullptr,nullptr));
#else
    assert(!test_active(nullptr,&level) && level==0);
    assert(test_forbid(nullptr,nullptr) && !test_allow(nullptr,nullptr));
#endif
}
''')
            for defined in [False, True]:
                exe = root / ('present' if defined else 'missing')
                command = ['clang++', str(fixture), *objects, '-Wl,-export_dynamic', '-o', str(exe)]
                if defined:
                    command += ['-DHAS_MBS_DECISION']
                subprocess.run(command, check=True)
                subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    unittest.main()
