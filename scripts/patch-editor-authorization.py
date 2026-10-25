#!/usr/bin/env python3
"""Build a version-bound, fail-closed Mbs authorization adapter on a new copy.

No license is issued here. The existing kcmc import must return true for the
MbsEditorLicenseVerified key only after the separate Mbs verifier validates a
signed, bound, unexpired authorization. False preserves the original code path.
"""
import argparse
import hashlib
import json
import pathlib
import struct
import subprocess
import tempfile

EXPECTED_SHA = "4aa19543b98b85c59bb5a836739afd66e976625a873de548a9c2d5d0e1a9fe1c"
SUPPORT_STUB = 0xA42C8
DLSYM_STUB = 0xA6458
KEY = "MbsEditorLicenseVerified"
TARGETS = [
    ("cn_common_or_domestic_active", 0x24210, 0x4000, "active", True),
    ("cn_enterprise_active", 0x4BFC0, 0x4200, "active", False),
    ("cn_enterprise_forbid_edit", 0x4B8D0, 0x4400, "forbid", False),
    ("cn_enterprise_account_edit", 0x4BB10, 0x4600, "allow", False),
]
EXCLUSIVE_TARGETS = TARGETS + [
    ('license_manager_active', 0x7F4BC, 0x4800, 'allow', False),
    ('global_account_edit', 0x106A4, 0x4A00, 'allow', False),
    ('user_register_forbid_edit', 0x5DF08, 0x4C00, 'forbid', False),
]
# Preserve native object construction; replace the decisions and state callbacks
# inside the exact inspected overseas manager. Return ABI is part of each row.
STATE_TARGETS = [
    ('xa_load_trial_cache',0x3268C,1,0),
    ('xa_login_changed',0x33240,1,0),
    ('xa_check_auth',0x33268,2,0),
    ('xa_old_broadcast',0x3363C,1,0),
    ('xa_feature_allowed',0x3379C,2,0),
    ('xa_authorize',0x33AEC,1,0),
    ('xa_license_active',0x33E70,2,0),
    ('xa_is_trial',0x340D4,3,0),
    ('xa_free_user',0x345E8,4,1),
    ('xa_licensed_user',0x346DC,5,0),
    ('xa_invalid_code',0x348AC,6,1),
    ('xa_activation_check',0x34A34,1,0),
    ('xa_end_trial',0x34E68,1,0),
    ('xa_trial_reminder',0x34F5C,1,0),
    ('xa_expiration_check',0x357F4,1,0),
    ('xa_launch_check',0x35960,1,0),
    ('xa_expiration_reminder',0x3599C,1,0),
    ('xa_total_trial_days',0x35FDC,10,0),
    ('xa_remaining_trial_days',0x3611C,10,0),
    ('xa_remaining_usable_days',0x36124,9,0),
    ('xa_sn_changed',0x361D4,1,0),
    ('xa_load_license',0x3667C,1,0),
    ('xa_offline_limit',0x37638,6,1),
    ('xa_remaining_seconds',0x37E50,8,0),
    ('xa_remaining_days',0x37ED8,9,0),
    ('xa_min_reminder_days',0x37F7C,10,0),
    ('xa_update_old_code',0x37FF0,1,0),
    ('xa_old_vip_changed',0x37FF8,1,0),
    ('xa_is_visitor',0x38020,7,1),
    ('xa_auth_status',0x32B18,11,2),
    ('xa_authority',0x32C70,12,2),
    ('xa_set_old_status',0x32CC8,1,0),
    ('xa_auth_type',0x38514,13,2),
    ('xa_load_cached_sn',0x38668,1,0),
]
STATE_DISPATCH_ADDRESS = 0x4E00
STATE_ENTRY_ADDRESS = 0x5000


def sha(data):
    return hashlib.sha256(data).hexdigest()


def branch(source, target, link=False):
    delta = target - source
    if delta % 4 or not -(1 << 27) <= delta < 1 << 27:
        raise ValueError("ARM64 branch out of range")
    return struct.pack("<I", (0x94000000 if link else 0x14000000) | ((delta // 4) & 0x3FFFFFF))


def adr(source, target, register):
    delta = target - source
    if not -(1 << 20) <= delta < 1 << 20:
        raise ValueError("ARM64 ADR out of range")
    return struct.pack("<I", 0x10000000 | ((delta & 3) << 29) | (((delta >> 2) & 0x7FFFF) << 5) | register)


def text_section(obj):
    _, cpu, _, _, count, _, _, _ = struct.unpack_from("<8I", obj)
    if cpu != 0x100000C:
        raise ValueError("assembler did not produce ARM64")
    pos = 32
    for _ in range(count):
        cmd, size = struct.unpack_from("<II", obj, pos)
        if cmd == 0x19:
            sections = struct.unpack_from("<I", obj, pos + 64)[0]
            for index in range(sections):
                sec = pos + 72 + index * 80
                name = obj[sec:sec + 16].split(b"\0")[0]
                if name == b"__text":
                    length = struct.unpack_from("<Q", obj, sec + 40)[0]
                    offset, _, _, relocations = struct.unpack_from("<IIII", obj, sec + 48)
                    if relocations:
                        raise ValueError("unresolved assembler relocation")
                    return obj[offset:offset + length]
        pos += size
    raise ValueError("missing assembler text")


def make_shim(entry, address, original, mode, restrict_cn):
    guard = """
    cbz x0, fallback
    ldr x8, [x0]
    brk #4
    cmp x8, x9
    b.eq query
    brk #5
    cmp x8, x9
    b.ne fallback
""" if restrict_cn else ""
    result = """
    cbz x1, result
    mov w8, #2
    str w8, [x1]
result:
    mov w0, #1
""" if mode == "active" else ("    mov w0, #0\n" if mode == "forbid" else "    mov w0, #1\n")
    source = f"""
.text
.p2align 2
_adapter:
{guard}
query:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x0, x1, [sp, #16]
    stp x2, x3, [sp, #32]
    adr x0, key
    brk #1
    cbz w0, restore_original
    ldp x0, x1, [sp, #16]
    ldp x2, x3, [sp, #32]
    ldp x29, x30, [sp], #48
{result}
    ret
restore_original:
    ldp x0, x1, [sp, #16]
    ldp x2, x3, [sp, #32]
    ldp x29, x30, [sp], #48
fallback:
    brk #2
    brk #3
key:
    .asciz "{KEY}"
    .p2align 2
"""
    with tempfile.TemporaryDirectory(prefix="mbs-native-adapter-") as temp:
        src = pathlib.Path(temp) / "adapter.s"
        obj = pathlib.Path(temp) / "adapter.o"
        src.write_text(source)
        subprocess.run(["xcrun", "clang", "-target", "arm64-apple-macos11", "-c", str(src), "-o", str(obj)], check=True)
        data = bytearray(text_section(obj.read_bytes()))
    fixups = {1: lambda off: branch(address + off, SUPPORT_STUB, True),
              2: lambda off: original,
              3: lambda off: branch(address + off, entry + 4),
              4: lambda off: adr(address + off, 0xF32B0, 9),
              5: lambda off: adr(address + off, 0xF33D0, 9)}
    for number in ([1, 2, 3, 4, 5] if restrict_cn else [1, 2, 3]):
        marker = struct.pack("<I", 0xD4200000 | (number << 5))
        offsets = [i for i in range(0, len(data) - 3, 4) if data[i:i + 4] == marker]
        if len(offsets) != 1:
            raise ValueError("missing or ambiguous assembler marker")
        offset = offsets[0]
        data[offset:offset + 4] = fixups[number](offset)
    return bytes(data), source


def make_exclusive_shim(address, mode):
    # Audited manager methods only. Never interpret an unknown native
    # configuration key as authorization; it can default to true.
    result = """
    cbz w8, inactive
    mov w9, #2
    b level
inactive:
    mov w9, #0
level:
    cbz x1, result
    str w9, [x1]
result:
    mov w0, w8
""" if mode == 'active' else ('    eor w0, w8, #1\n' if mode == 'forbid' else '    mov w0, w8\n')
    source = f"""
.text
.p2align 2
_adapter:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x0, x1, [sp, #16]
    stp x2, x3, [sp, #32]
    mov x0, #-2
    adr x1, decision
    brk #1
    cbz x0, unavailable
    blr x0
    mov w8, w0
    b restore
unavailable:
    mov w8, #0
restore:
    ldp x0, x1, [sp, #16]
    ldp x2, x3, [sp, #32]
    ldp x29, x30, [sp], #48
{result}
    ret
decision:
    .asciz "MbsHasVerifiedEditorLicense"
    .p2align 2
"""
    with tempfile.TemporaryDirectory(prefix='mbs-exclusive-manager-') as temp:
        src = pathlib.Path(temp) / 'adapter.s'
        obj = pathlib.Path(temp) / 'adapter.o'
        src.write_text(source)
        subprocess.run(['xcrun', 'clang', '-target', 'arm64-apple-macos11', '-c', str(src), '-o', str(obj)], check=True)
        data = bytearray(text_section(obj.read_bytes()))
    marker = struct.pack('<I', 0xD4200020)
    offsets = [i for i in range(0, len(data)-3, 4) if data[i:i+4] == marker]
    if len(offsets) != 1:
        raise ValueError('missing or ambiguous dlsym marker')
    offset = offsets[0]
    data[offset:offset+4] = branch(address+offset, DLSYM_STUB, True)
    return bytes(data), source


def make_state_dispatch(address=STATE_DISPATCH_ADDRESS):
    # x8 is the hidden return storage for Qt strings. x16 holds the per-entry
    # operation plus its missing-module return kind; neither may be lost in dlsym.
    source = '''
.text
.p2align 2
_state_dispatch:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x0, x1, [sp, #16]
    stp x2, x3, [sp, #32]
    stp x4, x5, [sp, #48]
    stp x6, x7, [sp, #64]
    stp x8, x16, [sp, #80]
    mov x0, #-2
    adr x1, decision
    brk #1
    cbz x0, unavailable
    mov x9, x0
    ldr x0, [sp, #16]
    ldr w1, [sp, #88]
    and w1, w1, #255
    ldr x2, [sp, #24]
    ldr x3, [sp, #32]
    ldr x4, [sp, #80]
    blr x9
    b done
unavailable:
    ldr w9, [sp, #88]
    lsr w9, w9, #8
    mov w0, #0
    cmp w9, #1
    b.ne string_result
    mov w0, #1
string_result:
    cmp w9, #2
    b.ne done
    ldr x8, [sp, #80]
    cbz x8, done
    adr x9, empty_string
    str x9, [x8]
done:
    ldp x29, x30, [sp], #96
    ret
decision:
    .asciz "MbsNativeAuthorizationDispatch"
    .p2align 3
empty_string:
    .long -1,0,0,0
    .quad 24
    .short 0
    .p2align 2
'''
    with tempfile.TemporaryDirectory(prefix='mbs-state-dispatch-') as temp:
        src=pathlib.Path(temp)/'state.s'; obj=pathlib.Path(temp)/'state.o'
        src.write_text(source)
        subprocess.run(['xcrun','clang','-target','arm64-apple-macos11','-c',str(src),'-o',str(obj)],check=True)
        data=bytearray(text_section(obj.read_bytes()))
    marker=struct.pack('<I',0xD4200020)
    offsets=[i for i in range(0,len(data)-3,4) if data[i:i+4]==marker]
    if len(offsets)!=1: raise ValueError('missing state dlsym marker')
    offset=offsets[0]; data[offset:offset+4]=branch(address+offset,DLSYM_STUB,True)
    return bytes(data),source


def state_entry(address,operation,kind):
    encoded=operation|(kind<<8)
    return struct.pack('<I',0x52800010|(encoded<<5))+branch(address+4,STATE_DISPATCH_ADDRESS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument('--exclusive-manager-checks', action='store_true',
                        help='Seven audited manager methods use the signed Mbs decision only, with no native fallback')
    parser.add_argument('--native-state-routing',action='store_true',
                        help='Also route the inspected login/trial/license state methods to the Mbs module')
    args = parser.parse_args()
    if args.native_state_routing and not args.exclusive_manager_checks:
        parser.error('state routing requires exclusive manager checks')
    if args.input.resolve() == args.output.resolve() or args.output.exists():
        parser.error("output must be a new copy")
    original = args.input.read_bytes()
    if sha(original) != EXPECTED_SHA:
        parser.error("unsupported source digest; no bytes were changed")
    # All addresses below are file-backed RVAs with fileoff=vmaddr, established
    # for this exact binary. Reserve only observed zero header padding.
    targets = EXCLUSIVE_TARGETS if args.exclusive_manager_checks else TARGETS
    padding_end = 0x5200 if args.native_state_routing else (0x4E00 if args.exclusive_manager_checks else 0x4800)
    if set(original[0x4000:padding_end]) != {0}:
        parser.error("reserved header padding is not empty")
    patched = bytearray(original)
    manifest = {"source_sha256": EXPECTED_SHA, "license_key": KEY,
                "success_semantics": "Mbs custom authorization, not vendor-issued activation",
                "fallback": "original first instruction and remainder on unverified lease",
                "patches": []}
    if args.exclusive_manager_checks:
        manifest.pop('license_key')
        manifest.update({'fallback':'none at the seven audited manager entrypoints',
                         'decision_symbol':'MbsHasVerifiedEditorLicense',
                         'scope':'seven audited manager methods; not a whole-editor independence claim'})
    for name, entry, shim_at, mode, cn_only in targets:
        if args.exclusive_manager_checks:
            shim, source = make_exclusive_shim(shim_at, mode)
        else:
            shim, source = make_shim(entry, shim_at, original[entry:entry + 4], mode, cn_only)
        if len(shim) > 0x200:
            raise ValueError("shim exceeds reserved interval")
        patched[shim_at:shim_at + len(shim)] = shim
        patched[entry:entry + 4] = branch(entry, shim_at)
        manifest["patches"].append({"name": name, "entry": entry, "shim": shim_at,
                                    "shim_length": len(shim), "original_entry_hex": original[entry:entry + 4].hex(),
                                    "new_entry_hex": bytes(patched[entry:entry + 4]).hex(),
                                    "shim_sha256": sha(shim), "assembly_template": source})
    if args.native_state_routing:
        dispatch,source=make_state_dispatch()
        if len(dispatch)>STATE_ENTRY_ADDRESS-STATE_DISPATCH_ADDRESS:
            raise ValueError('state dispatcher exceeds reserved interval')
        patched[STATE_DISPATCH_ADDRESS:STATE_DISPATCH_ADDRESS+len(dispatch)]=dispatch
        manifest['state_dispatch']={'address':STATE_DISPATCH_ADDRESS,'length':len(dispatch),
                                   'sha256':sha(dispatch),'assembly_template':source}
        for index,(name,entry,operation,kind) in enumerate(STATE_TARGETS):
            at=STATE_ENTRY_ADDRESS+index*8
            shim=state_entry(at,operation,kind)
            if at+len(shim)>padding_end: raise ValueError('state entries exceed reserved interval')
            patched[at:at+len(shim)]=shim
            patched[entry:entry+4]=branch(entry,at)
            manifest['patches'].append({'name':name,'entry':entry,'shim':at,'shim_length':len(shim),
                'operation':operation,'return_kind':kind,'original_entry_hex':original[entry:entry+4].hex(),
                'new_entry_hex':bytes(patched[entry:entry+4]).hex(),'shim_sha256':sha(shim)})
        manifest['scope']='seven manager decisions and inspected overseas login/trial/license state methods; original objects retained'
    manifest["output_sha256_before_signing"] = sha(patched)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(patched)
    args.output.chmod(args.input.stat().st_mode & 0o777)
    args.output.with_suffix(args.output.suffix + ".adapter.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({key: value for key, value in manifest.items() if key != "patches"}, indent=2))


if __name__ == "__main__":
    main()
