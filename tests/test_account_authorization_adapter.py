import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('account_adapter',Path(__file__).resolve().parents[1]/'scripts/patch-account-authorization.py')
adapter=importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class AccountAdapterTests(unittest.TestCase):
    def test_wrong_prologue_and_wrong_input_are_rejected(self):
        with self.assertRaises(ValueError):
            adapter.make_shim(0x4000,0x69574,b'\0'*4,'query')
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); original=root/'wrong-native'; output=root/'new-native'
            original.write_bytes(b'not the audited ksolite binary')
            result=subprocess.run(['python3',str(Path(adapter.__file__)),'--input',str(original),'--output',str(output)],
                                  capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(output.exists())

    def test_arm64_helpers_missing_or_present_and_unrelated_queries_keep_original(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); objects=[]
            for _,entry,address,mode in adapter.TARGETS:
                data,source=adapter.make_shim(address,entry,bytes.fromhex(adapter.PROLOGUES[mode]),mode)
                self.assertLessEqual(len(data),0x400)
                # Execute the same assembly with fixture import stubs and the
                # exact displaced prologue before the fixture original remainder.
                source=source.replace('_adapter:',f'.globl _test_{mode}\n_test_{mode}:')
                source=source.replace('brk #1','bl _dlsym').replace('brk #2','bl _fixture_variant_bool')
                source=source.replace('brk #3','.long 0x'+bytes.fromhex(adapter.PROLOGUES[mode])[::-1].hex())
                source=source.replace('brk #4','b _fallback_'+mode)
                asm=root/(mode+'.s');obj=root/(mode+'.o');asm.write_text(source)
                subprocess.run(['clang','-c',str(asm),'-o',str(obj)],check=True)
                objects.append(str(obj))
            cpp=root/'fixture.cpp'
            cpp.write_text(r'''
#include <cassert>
#include <cstdint>
#include <cstring>
#include <new>
struct Data {
    int reference=-1,length; unsigned allocation=0,padding=0;
    intptr_t offset=24; uint16_t text[64]={};
    Data(const char *s):length((int)strlen(s)) {
        assert(length<64); for(int i=0;i<length;++i)text[i]=(unsigned char)s[i];
    }
};
struct String {Data *data;};
struct Result {
    int64_t value,marker;
    Result(int64_t v,int64_t m):value(v),marker(m){}
    ~Result(){}
};
static int sdkObject;
static struct {char prefix[24];void *sdk;} proxy={{},&sdkObject};
static bool editing;
extern "C" int test_login(void *,const void *);
extern "C" int test_logout(void *,const void *);
extern "C" int test_auto(void *);
extern "C" bool test_enable(void *,const String &);
extern "C" Result test_query(void *,const String &,const Result &);
extern "C" void fixture_variant_bool(void *out,bool value) {new(out) Result(value,77);}
extern "C" bool fallback_enable(void *sdk,const String &) {assert(sdk==&sdkObject);return true;}
extern "C" Result fallback_query(void *sdk,const String &,const Result &value) {
    assert(sdk==&sdkObject);return Result(value.value,88);
}
#ifdef HAS_MBS_HELPERS
extern "C" int MbsNativeAccountRoute(void *object,int action) {
    assert(object==&proxy);return action==1||action==2;
}
extern "C" bool MbsNativeAccountQuery(void *object,const void *key,void *out) {
    assert(object==&proxy && key && out);new(out) Result(!editing,77);return true;
}
#endif
int main() {
    Data forceData("forbidEditInForceLogin"),otherData("forbidEditInForceLoginExtra");
    Data snData("LoginSNAuth"),otherSnData("LoginSNAuthExtra");
    String force{&forceData},other{&otherData},sn{&snData},otherSn{&otherSnData};
    Result fallback(9,9);
    auto denied=test_query(&proxy,force,fallback);
    assert(denied.value==1 && denied.marker==77);
    editing=true;
    auto active=test_query(&proxy,force,fallback);
#ifdef HAS_MBS_HELPERS
    assert(active.value==0 && active.marker==77);
    assert(test_login(&proxy,nullptr)==1 && test_logout(&proxy,nullptr)==1);
#else
    assert(active.value==1 && active.marker==77);
    assert(test_login(&proxy,nullptr)==0 && test_logout(&proxy,nullptr)==0);
#endif
    auto unrelated=test_query(&proxy,other,fallback);
    assert(unrelated.value==9 && unrelated.marker==88);
    assert(!test_auto(&proxy) && !test_enable(&proxy,sn));
    assert(test_enable(&proxy,otherSn));
}
''')
            for helpers in [False,True]:
                exe=root/('present' if helpers else 'missing')
                sdk=subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip()
                command=['clang++','-std=c++17','-isystem',sdk+'/usr/include/c++/v1',
                         '-Wno-return-type-c-linkage',str(cpp),*objects,
                         '-Wl,-export_dynamic','-o',str(exe)]
                if helpers:command.append('-DHAS_MBS_HELPERS')
                subprocess.run(command,check=True)
                subprocess.run([str(exe)],check=True)


if __name__=='__main__':unittest.main()
