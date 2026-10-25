import importlib.util
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('adapter', Path(__file__).resolve().parents[1] / 'scripts/patch-editor-authorization.py')
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class NativeStateAdapterTests(unittest.TestCase):
    def test_dispatch_preserves_arguments_hidden_string_result_and_missing_module(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data, source = adapter.make_state_dispatch()
            self.assertLessEqual(len(data), adapter.STATE_ENTRY_ADDRESS-adapter.STATE_DISPATCH_ADDRESS)
            self.assertIn(b'MbsNativeAuthorizationDispatch\0', data)
            for name, op, kind in [('check', 2, 0), ('visitor', 7, 1), ('seconds', 8, 0), ('string', 11, 2)]:
                source += f'\n.globl _test_{name}\n_test_{name}:\n    mov w16, #{op|(kind<<8)}\n    b _state_dispatch\n'
            asm = root/'dispatch.s'
            asm.write_text(source.replace('brk #1', 'bl _dlsym'))
            fixture = root/'fixture.cpp'
            fixture.write_text('''
#include <assert.h>
#include <stdint.h>
struct Result { const void *data; ~Result() {} };
extern "C" uint64_t test_check(void *,const void *);
extern "C" uint64_t test_visitor(void *,const void *);
extern "C" uint64_t test_seconds(void *,const void *);
extern "C" Result test_string(void *,const void *);
static bool active;
static const char marker[]="owned-string-result";
#ifdef HAS_MBS_DISPATCH
extern "C" uint64_t MbsNativeAuthorizationDispatch(void *manager,unsigned op,const void *arg,const void *,void *out) {
    assert(manager==(void *)0x1122 && arg==(void *)0x3344);
    if(op==11) { assert(out); *(const void **)out=marker; return 0; }
    if(op==7) return !active;
    if(op==8) return active?1234567:0;
    return active;
}
#endif
int main() {
    void *m=(void *)0x1122; const void *a=(void *)0x3344;
    assert(!test_check(m,a) && test_visitor(m,a)==1 && !test_seconds(m,a));
    active=true;
#ifdef HAS_MBS_DISPATCH
    assert(test_check(m,a)==1 && !test_visitor(m,a) && test_seconds(m,a)==1234567);
    Result value=test_string(m,a); assert(value.data==marker);
#else
    assert(!test_check(m,a) && test_visitor(m,a)==1 && !test_seconds(m,a));
    Result value=test_string(m,a);
    const int *header=(const int *)value.data;
    assert(header && header[0]==-1 && header[1]==0);
    assert(*(const int64_t *)((const char *)header+16)==24);
#endif
}
''')
            for present in [False, True]:
                binary=root/('present' if present else 'missing')
                command=['clang++',str(asm),str(fixture),'-Wl,-export_dynamic','-o',str(binary)]
                if present: command.append('-DHAS_MBS_DISPATCH')
                subprocess.run(command,check=True)
                subprocess.run([str(binary)],check=True)

    def test_version_bound_entries_encode_operation_and_share_dispatcher(self):
        seen=set()
        for index,(_,entry,op,kind) in enumerate(adapter.STATE_TARGETS):
            self.assertNotIn(entry,seen)
            seen.add(entry)
            at=adapter.STATE_ENTRY_ADDRESS+8*index
            code=adapter.state_entry(at,op,kind)
            mov=struct.unpack_from('<I',code)[0]
            self.assertEqual((mov>>5)&0xffff,op|(kind<<8))
            self.assertEqual(code[4:],adapter.branch(at+4,adapter.STATE_DISPATCH_ADDRESS))


if __name__ == '__main__':
    unittest.main()
