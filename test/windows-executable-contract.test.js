import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const mainExecutableName = 'where_to_study.exe'

// Microsoft PE/COFF contract: e_lfanew at DOS offset 0x3c; the optional header
// follows the 4-byte PE signature and 20-byte COFF header. Subsystem occupies
// two bytes at optional-header offset 68 for both PE32 and PE32+.
// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
function windowsSubsystem(bytes) {
  assert.ok(bytes.length >= 64, 'Truncated DOS header')
  assert.equal(bytes.toString('ascii', 0, 2), 'MZ', 'Missing DOS MZ signature')
  const peOffset = bytes.readUInt32LE(0x3c)
  assert.ok(peOffset >= 64 && peOffset + 24 <= bytes.length, 'Invalid PE header offset')
  assert.equal(bytes.readUInt32LE(peOffset), 0x00004550, 'Missing PE signature')
  const optionalHeader = peOffset + 24
  const optionalSize = bytes.readUInt16LE(peOffset + 20)
  assert.ok(optionalSize >= 70 && optionalHeader + optionalSize <= bytes.length,
    'Missing or truncated PE optional header')
  assert.ok([0x10b, 0x20b].includes(bytes.readUInt16LE(optionalHeader)),
    'Unsupported PE optional-header magic')
  return bytes.readUInt16LE(optionalHeader + 68)
}

function assertGuiExecutable(bytes) {
  assert.equal(windowsSubsystem(bytes), 2,
    'Installed app must use IMAGE_SUBSYSTEM_WINDOWS_GUI (2), not console/CUI (3)')
}

function peFixture(magic = 0x20b, subsystem = 2) {
  const bytes = Buffer.alloc(512)
  bytes.write('MZ', 0, 'ascii')
  bytes.writeUInt32LE(128, 0x3c)
  bytes.writeUInt32LE(0x00004550, 128)
  bytes.writeUInt16LE(magic === 0x20b ? 240 : 224, 128 + 20)
  bytes.writeUInt16LE(magic, 128 + 24)
  bytes.writeUInt16LE(subsystem, 128 + 24 + 68)
  return bytes
}

test('Windows release selects GUI subsystem while debug retains the default console', () => {
  const source = readFileSync(path.join(root, 'src-tauri/src/main.rs'), 'utf8')
  assert.ok(source.replace(/\s/g, '').includes(
    '#![cfg_attr(all(target_os="windows",not(debug_assertions)),windows_subsystem="windows")]'))
  assert.equal(source.match(/windows_subsystem/g)?.length, 1)
})

test('installed-app contract names the Cargo main binary, not the installer', () => {
  const config = JSON.parse(readFileSync(path.join(root, 'src-tauri/tauri.conf.json'), 'utf8'))
  const cargo = readFileSync(path.join(root, 'src-tauri/Cargo.toml'), 'utf8')
  const packageName = cargo.match(/\[package\][\s\S]*?^name\s*=\s*"([^"]+)"/m)?.[1]
  assert.equal(`${config.mainBinaryName || packageName}.exe`, mainExecutableName)
  const workflow = readFileSync(path.join(root, '.github/workflows/build-windows.yml'), 'utf8')
    .replaceAll('\r\n', '\n')
  assert.match(workflow, /\$appExecutables = @\(Get-ChildItem \$installDirectory -Recurse -File -Filter "where_to_study\.exe"\)/)
  assert.match(workflow, /\$appExecutables\.Count -ne 1/)
  assert.match(workflow, /\$env:WTS_WINDOWS_APP_EXECUTABLE = \$appExecutable\.FullName/)
  assert.match(workflow, /node --test test\/windows-executable-contract\.test\.js\s+if \(\$LASTEXITCODE -ne 0\)/)
  assert.ok(workflow.indexOf('$env:WTS_WINDOWS_APP_EXECUTABLE =') > workflow.indexOf('$installer = Start-Process'))
})

for (const magic of [0x10b, 0x20b]) {
  test(`PE ${magic.toString(16)} GUI header is accepted`, () => {
    assertGuiExecutable(peFixture(magic, 2))
  })
  test(`PE ${magic.toString(16)} console header is rejected`, () => {
    assert.throws(() => assertGuiExecutable(peFixture(magic, 3)), /IMAGE_SUBSYSTEM_WINDOWS_GUI/)
  })
}

test('PE validation rejects malformed or truncated headers', () => {
  assert.throws(() => windowsSubsystem(Buffer.alloc(63)), /Truncated DOS/)
  const invalidDOS = peFixture()
  invalidDOS.write('NO', 0, 'ascii')
  assert.throws(() => windowsSubsystem(invalidDOS), /DOS MZ/)
  const invalidOffset = peFixture()
  invalidOffset.writeUInt32LE(0xffffffff, 0x3c)
  assert.throws(() => windowsSubsystem(invalidOffset), /PE header offset/)
  const invalidSignature = peFixture()
  invalidSignature.writeUInt32LE(0, 128)
  assert.throws(() => windowsSubsystem(invalidSignature), /PE signature/)
  assert.throws(() => windowsSubsystem(peFixture(0x107)), /optional-header magic/)
  const missingOptional = peFixture()
  missingOptional.writeUInt16LE(0, 128 + 20)
  assert.throws(() => windowsSubsystem(missingOptional), /optional header/)
  assert.throws(() => windowsSubsystem(peFixture().subarray(0, 220)), /optional header/)
})

// CI sets this only after silently installing the final NSIS artifact. Ordinary
// cross-platform npm tests exercise fixtures without claiming a Windows build.
test('installed Windows main executable has PE Subsystem 2 (GUI)', {
  skip: !process.env.WTS_WINDOWS_APP_EXECUTABLE,
}, () => {
  const executable = process.env.WTS_WINDOWS_APP_EXECUTABLE
  assert.equal(path.basename(executable).toLowerCase(), mainExecutableName)
  assertGuiExecutable(readFileSync(executable))
})
