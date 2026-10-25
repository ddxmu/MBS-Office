#!/usr/bin/env python3
"""Build an exact-version account behavior adapter on a new ksolite copy."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import tempfile

spec=importlib.util.spec_from_file_location('mbs_editor_adapter',Path(__file__).with_name('patch-editor-authorization.py'))
common=importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)

EXPECTED_SHA='249c3efc500cd1ce7d96a79603c09fd71ff3a7dd1ca78d3d3126009e723b590f'
DLSYM_STUB=0xA3C380
VARIANT_BOOL_STUB=0xA3812C
TARGETS=[
    ('account_login',0x6857C,0x4000,'login'),
    ('account_logout',0x68D60,0x4400,'logout'),
    ('old_auto_login',0x68564,0x4800,'auto'),
    ('force_login_edit_query',0x69574,0x4C00,'query'),
    ('old_sn_login_enable',0x68534,0x5000,'enable'),
]
PROLOGUES={'login':'ff0302d1','logout':'ff8301d1','auto':'000c40f9',
           'query':'000c40f9','enable':'000c40f9'}


def make_shim(address,entry,original,mode):
    if original.hex()!=PROLOGUES[mode]:
        raise ValueError('unsupported native entry instruction')
    key='forbidEditInForceLogin' if mode=='query' else 'LoginSNAuth'
    matcher=f'''
    ldr x9, [x1]
    cbz x9, fallback
    ldr w10, [x9, #4]
    cmp w10, #{len(key)}
    b.ne fallback
    ldr x10, [x9, #16]
    add x9, x9, x10
    adr x10, key
    mov w11, #{len(key)}
match:
    ldrh w12, [x9], #2
    ldrh w13, [x10], #2
    cmp w12, w13
    b.ne fallback
    subs w11, w11, #1
    b.ne match
''' if mode in ('query','enable') else ''
    helper='MbsNativeAccountQuery' if mode=='query' else 'MbsNativeAccountRoute'
    action={'login':1,'logout':2,'auto':3,'enable':4}.get(mode,0)
    invoke='''
    ldp x0, x1, [sp, #16]
    ldr x2, [sp, #80]
    blr x14
    cbz w0, unavailable
    b restore
''' if mode=='query' else f'''
    ldr x0, [sp, #16]
    mov w1, #{action}
    blr x14
    mov w14, w0
    b restore
'''
    missing='''
    ldr x0, [sp, #80]
    mov w1, #1
    brk #2
''' if mode=='query' else '    mov w14, #0\n'
    result='    mov x0, x14\n' if mode=='query' else '    mov w0, w14\n'
    query_result='    ldr x14, [sp, #80]\n' if mode=='query' else ''
    fallback='''
fallback:
    brk #3
    brk #4
''' if mode in ('query','enable') else ''
    literal='key:\n    .hword '+', '.join(str(ord(c)) for c in key)+'\n' if matcher else ''
    source=f'''
.text
.p2align 2
_adapter:
{matcher}
    stp x29, x30, [sp, #-112]!
    mov x29, sp
    stp x0, x1, [sp, #16]
    stp x2, x3, [sp, #32]
    stp x4, x5, [sp, #48]
    stp x6, x7, [sp, #64]
    str x8, [sp, #80]
    mov x0, #-2
    adr x1, helper
    brk #1
    cbz x0, unavailable
    mov x14, x0
    ldp x0, x1, [sp, #16]
    ldp x2, x3, [sp, #32]
    ldp x4, x5, [sp, #48]
    ldp x6, x7, [sp, #64]
    ldr x8, [sp, #80]
{invoke}
unavailable:
{missing}
restore:
{query_result}
    ldp x0, x1, [sp, #16]
    ldp x2, x3, [sp, #32]
    ldp x4, x5, [sp, #48]
    ldp x6, x7, [sp, #64]
    ldr x8, [sp, #80]
    ldp x29, x30, [sp], #112
{result}
    ret
{fallback}
helper:
    .asciz "{helper}"
{literal}
    .p2align 2
'''
    with tempfile.TemporaryDirectory(prefix='mbs-account-adapter-') as directory:
        root=Path(directory); asm=root/'adapter.s'; obj=root/'adapter.o'
        asm.write_text(source)
        subprocess.run(['xcrun','clang','-target','arm64-apple-macos11','-c',str(asm),'-o',str(obj)],check=True)
        data=bytearray(common.text_section(obj.read_bytes()))
    fixes={1:lambda off:common.branch(address+off,DLSYM_STUB,True),
           2:lambda off:common.branch(address+off,VARIANT_BOOL_STUB,True),
           3:lambda off:original,4:lambda off:common.branch(address+off,entry+4)}
    markers=[1]+([2] if mode=='query' else [])+([3,4] if mode in ('query','enable') else [])
    for number in markers:
        marker=struct.pack('<I',0xD4200000|(number<<5))
        positions=[i for i in range(0,len(data)-3,4) if data[i:i+4]==marker]
        if len(positions)!=1:raise ValueError('missing or ambiguous account adapter marker')
        off=positions[0];data[off:off+4]=fixes[number](off)
    return bytes(data),source


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    if args.input.resolve()==args.output.resolve() or args.output.exists():p.error('output must be a new copy')
    original=args.input.read_bytes()
    digest=lambda b:hashlib.sha256(b).hexdigest()
    if digest(original)!=EXPECTED_SHA:p.error('unsupported ksolite source digest; no bytes changed')
    if set(original[0x4000:0x5400])!={0}:p.error('audited header padding is no longer empty')
    output=bytearray(original)
    manifest={'source_sha256':EXPECTED_SHA,'scope':'native account login/logout and exact authorization queries only',
              'fallback':'unrelated query and isEnable calls execute the original prologue and remainder',
              'missing_helper':'deny targeted editing query using native QVariant(bool); no legacy login fallback',
              'patches':[]}
    for name,entry,address,mode in TARGETS:
        shim,source=make_shim(address,entry,original[entry:entry+4],mode)
        if len(shim)>0x400:raise ValueError('account shim exceeds its reserved interval')
        output[address:address+len(shim)]=shim
        output[entry:entry+4]=common.branch(entry,address)
        manifest['patches'].append({'name':name,'entry':entry,'shim':address,'shim_length':len(shim),
            'original_entry_hex':original[entry:entry+4].hex(),'new_entry_hex':output[entry:entry+4].hex(),
            'shim_sha256':digest(shim),'assembly_template':source})
    manifest['output_sha256_before_signing']=digest(output)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes(output);args.output.chmod(args.input.stat().st_mode&0o777)
    args.output.with_suffix(args.output.suffix+'.adapter.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({k:v for k,v in manifest.items() if k!='patches'},indent=2))


if __name__=='__main__':main()
