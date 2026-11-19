#!/usr/bin/env bash
# Fixture test for the compat-scanner image: runs it with the flags EE uses and checks the results.
# Usage: tests/run.sh [image]   (default easyengine/compat-scanner:test)
set -euo pipefail

IMAGE=${1:-easyengine/compat-scanner:test}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/compat-scanner-test.XXXXXX")
RES="$WORK/results"
mkdir -p "$RES"
# shellcheck source=fixture.sh
. "$HERE/fixture.sh"

cleanup() { chmod -R u+rwX "$WORK" 2>/dev/null || true; rm -rf "$WORK" 2>/dev/null || sudo rm -rf "$WORK"; }
[ -n "${KEEP:-}" ] || trap cleanup EXIT

# EE's out dir is 0700 and owned by 33; without root a world-writable dir stands in for it.
new_out() {
	local d="$WORK/out-$1"
	mkdir -p "$d"
	if [ "$(id -u)" = 0 ]; then chown 33:33 "$d" && chmod 0700 "$d"; else chmod 0777 "$d"; fi
	echo "$d"
}

tree_sum() { (cd "$1" && find . -printf '%p %s %T@ %m\n' | LC_ALL=C sort | md5sum | cut -d' ' -f1); }

# Entrypoint memory override: ENTRY_MEMORY=4M scan ... runs the script with that limit.
entry() {
	if [ -n "${ENTRY_MEMORY:-}" ]; then
		echo --entrypoint php "$IMAGE" -d "memory_limit=$ENTRY_MEMORY" /opt/compat-scanner/bin/compat-scanner.php
	else
		echo "$IMAGE"
	fi
}

# scan <name> <app> <type> <path> <version> <timeout> [docker args...]
scan() {
	local name=$1 app=$2 type=$3 path=$4 ver=$5 timeout=$6
	shift 6
	local out rc=0
	out=$(new_out "$name")
	# The outer timeout keeps a hanging scan from blocking the test run.
	# shellcheck disable=SC2046
	timeout 900 docker run --rm --init --name "ee-php-compat-test-$name" \
		--network none --read-only --tmpfs /tmp:size=64m \
		--cap-drop ALL --security-opt no-new-privileges --pids-limit 64 \
		--memory 1g --memory-swap 1g --cpus 1 --cpu-shares 256 \
		--user 33:33 \
		-e COMPAT_SITE=fixture.test -e COMPAT_IMAGE="$IMAGE" "$@" \
		--mount "type=bind,src=$(realpath "$app"),dst=/var/www,readonly" \
		--mount "type=bind,src=$out,dst=/out" \
		$(entry) scan "$type" "$path" "$ver" "$timeout" > "$RES/$name.stdout" 2> "$RES/$name.stderr" || rc=$?
	docker rm -f "ee-php-compat-test-$name" > /dev/null 2>&1 || true
	echo "$rc" > "$RES/$name.rc"
	if [ -f "$out/report.json" ]; then cp "$out/report.json" "$RES/$name.report.json"; fi
	(cd "$out" && find . -mindepth 1 | LC_ALL=C sort) > "$RES/$name.outdir" 2>/dev/null || sudo sh -c "cd '$out' && find . -mindepth 1" > "$RES/$name.outdir"
	echo "scan $name: rc=$rc $(head -c 300 "$RES/$name.stdout")"
}

# estimate <name> <app> <type> <path> <version> [docker args...]
estimate() {
	local name=$1 app=$2 type=$3 path=$4 ver=$5 rc=0
	shift 5
	# shellcheck disable=SC2046
	docker run --rm --init \
		--network none --read-only --tmpfs /tmp:size=64m \
		--cap-drop ALL --security-opt no-new-privileges --pids-limit 64 \
		--memory 1g --memory-swap 1g --cpus 1 --cpu-shares 256 \
		--user 33:33 \
		-e COMPAT_SITE=fixture.test "$@" \
		--mount "type=bind,src=$(realpath "$app"),dst=/var/www,readonly" \
		$(entry) estimate "$type" "$path" "$ver" 120 > "$RES/$name.stdout" 2> "$RES/$name.stderr" || rc=$?
	echo "$rc" > "$RES/$name.rc"
	echo "estimate $name: rc=$rc $(head -c 300 "$RES/$name.stdout")"
}

wp_fixture "$WORK/wp" 1 1
wp_fixture "$WORK/wp-clean" 0 0
wp_fixture "$WORK/wp-null" 0 1
php_fixture "$WORK/php"
oom_fixture "$WORK/oom"
flood_fixture "$WORK/flood"
wide_fixture "$WORK/wide"
wpcfg_fixture "$WORK/wpcfg-dir" dir
wpcfg_fixture "$WORK/wpcfg-parent" parent
php_release_fixture "$WORK/php-rel" real
php_release_fixture "$WORK/php-rel-link" link
mkdir -p "$WORK/empty/htdocs" && chmod -R a+rX "$WORK/empty"

before=$(tree_sum "$WORK/wp")
scan full "$WORK/wp" wp /var/www/htdocs/current 8.4 600
scan clean "$WORK/wp-clean" wp /var/www/htdocs/current 8.4 600
scan null "$WORK/wp-null" wp /var/www/htdocs/current 8.4 600
scan batchmem "$WORK/wp" wp /var/www/htdocs/current 8.4 600 -e COMPAT_BATCH_MEMORY=8M -e COMPAT_FILE_MEMORY=448M
scan filemem "$WORK/wp" wp /var/www/htdocs/current 8.4 600 -e COMPAT_BATCH_MEMORY=8M -e COMPAT_FILE_MEMORY=8M -e COMPAT_RETRY_MEMORY=448M
scan allmem "$WORK/wp" wp /var/www/htdocs/current 8.4 600 -e COMPAT_BATCH_MEMORY=8M -e COMPAT_FILE_MEMORY=8M -e COMPAT_RETRY_MEMORY=8M
scan timeout "$WORK/wp" wp /var/www/htdocs/current 8.4 1 -e COMPAT_BATCH_SIZE=1
scan php "$WORK/php" php /var/www/htdocs/public 8.4 600
scan nocode "$WORK/empty" wp /var/www/htdocs 8.4 600
scan badargs "$WORK/wp" wp /etc 8.4 600
estimate est "$WORK/wp" wp /var/www/htdocs/current 8.4
estimate est-php "$WORK/php" php /var/www/htdocs/public 8.4
estimate est-nocode "$WORK/empty" wp /var/www/htdocs 8.4

# wp-config.php: the one WordPress loads, as component other/wp-config.php.
scan wpcfg-dir "$WORK/wpcfg-dir" wp /var/www/htdocs 8.4 600
scan wpcfg-parent "$WORK/wpcfg-parent" wp /var/www/htdocs 8.4 600
# php CI/CD layout: only the live release; a symlinked releases/ isn't the layout.
scan php-rel "$WORK/php-rel" php /var/www/htdocs/current/public 8.4 600
estimate est-php-rel "$WORK/php-rel" php /var/www/htdocs/current/public 8.4
scan php-rel-link "$WORK/php-rel-link" php /var/www/htdocs/current/public 8.4 600

# A kernel OOM kill of PHPCS (container limit below PHP's) is reason memory.
scan oom "$WORK/oom" wp /var/www/htdocs 8.4 600 --memory 300m --memory-swap 300m \
	-e COMPAT_BATCH_MEMORY=8M -e COMPAT_FILE_MEMORY=8M -e COMPAT_RETRY_MEMORY=4G -e COMPAT_DEBUG=1
# The entrypoint streams findings and the file list: small memory, many findings or files.
ENTRY_MEMORY=12M scan flood "$WORK/flood" wp /var/www/htdocs 8.4 600
ENTRY_MEMORY=8M estimate wide-est "$WORK/wide" wp /var/www/htdocs 8.4
# A fatal error still prints one tool_error document.
ENTRY_MEMORY=4M scan fatal "$WORK/wide" wp /var/www/htdocs 8.4 600
# Report size cap: PHPCS's own output (SIGXFSZ) and the spool.
scan flood-cap "$WORK/flood" wp /var/www/htdocs 8.4 600 -e COMPAT_REPORT_MAX=1024 -e COMPAT_DEBUG=1
scan full-cap "$WORK/wp" wp /var/www/htdocs/current 8.4 600 -e COMPAT_REPORT_MAX=100000
scan wide-cap "$WORK/wide" wp /var/www/htdocs 8.4 600 -e COMPAT_REPORT_MAX=100000
# Estimate deadline hit while calibrating; a version with a trailing newline.
estimate est-timeout "$WORK/wp" wp /var/www/htdocs/current 8.4 -e COMPAT_ESTIMATE_TIMEOUT=1
estimate badver "$WORK/wp" wp /var/www/htdocs/current $'8.4\n'

# A full /out: a tool_error, not a quietly incomplete result.
rc=0
docker run --rm --init --network none --read-only --tmpfs /tmp:size=64m \
	--cap-drop ALL --security-opt no-new-privileges --pids-limit 64 \
	--memory 1g --memory-swap 1g --cpus 1 --user 33:33 \
	--mount "type=bind,src=$(realpath "$WORK/flood"),dst=/var/www,readonly" \
	--mount type=tmpfs,dst=/out,tmpfs-size=262144,tmpfs-mode=1777 \
	"$IMAGE" scan wp /var/www/htdocs 8.4 600 > "$RES/fullout.stdout" 2> "$RES/fullout.stderr" || rc=$?
echo "$rc" > "$RES/fullout.rc"
echo "scan fullout: rc=$rc $(head -c 300 "$RES/fullout.stdout")"
after=$(tree_sum "$WORK/wp")
[ "$before" = "$after" ] && echo unchanged > "$RES/tree" || echo changed > "$RES/tree"

# The code mount is read-only for the scanner.
docker run --rm --network none --read-only --cap-drop ALL --user 33:33 \
	--mount "type=bind,src=$(realpath "$WORK/wp"),dst=/var/www,readonly" \
	--entrypoint sh "$IMAGE" -c 'touch /var/www/htdocs/x 2>/dev/null && echo writable || echo readonly' > "$RES/mount"

chmod -R a+rX "$RES"
docker run --rm --network none --read-only --user 33:33 \
	--mount "type=bind,src=$RES,dst=/r,readonly" \
	--mount "type=bind,src=$HERE/assert.php,dst=/t/assert.php,readonly" \
	--entrypoint php "$IMAGE" /t/assert.php /r
