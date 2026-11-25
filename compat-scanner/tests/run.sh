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
	# OUT_DIR_AT=report.json: a directory already there, so publishing the report fails.
	if [ -n "${OUT_DIR_AT:-}" ]; then mkdir "$out/$OUT_DIR_AT" && chmod 0777 "$out/$OUT_DIR_AT"; fi
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

# PID of the container's PHPCS process (not busybox timeout's watcher), if one is running.
phpcs_pid() { docker top "$1" -o pid,args 2>/dev/null | awk '$2 ~ /\/php$/ && /php_codesniffer\/bin\/phpcs/ { print $1; exit }'; }

# during <name> <command...>: runs the command while scan <name> (COMPAT_DEBUG=1) is in its first PHPCS run, so
# after the listing, with the container paused; writes ok or why not to $RES/<name>.sync.
during() {
	local name=$1
	shift
	(
		set +e
		c="ee-php-compat-test-$name" res="no PHPCS run seen"
		for _ in $(seq 1 1200); do
			[ -e "$RES/$name.rc" ] && break
			pid=$(phpcs_pid "$c")
			if [ -n "$pid" ]; then
				res="PHPCS run $pid ended before the pause"
				if docker pause "$c" > /dev/null 2>&1; then
					# Still the same run and no batch finished yet: the next file isn't checked before the change.
					if [ "$(phpcs_pid "$c")" = "$pid" ] && ! grep -q '] batch ' "$RES/$name.stderr"; then
						if "$@"; then res=ok; else res="command failed"; fi
					fi
					docker unpause "$c" > /dev/null 2>&1
				fi
				break
			fi
			sleep 0.05
		done
		echo "$res" > "$RES/$name.sync"
	) &
}

switch_release() { ln -sfn releases/B "$1/htdocs/current.new" && mv -T "$1/htdocs/current.new" "$1/htdocs/current"; }
grow_file() { echo 'each( $a );' >> "$1"; }

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
switch_fixture "$WORK/switch"
changed_fixture "$WORK/changed"
locked_root_fixture "$WORK/rootlock"
bigmsg_fixture "$WORK/bigmsg"
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

# A deploy re-points current mid-scan: no verdict. A file that grows before its batch: checked as it is now.
during switch switch_release "$WORK/switch"
scan switch "$WORK/switch" php /var/www/htdocs/current/public 8.4 600 -e COMPAT_BATCH_SIZE=1 -e COMPAT_DEBUG=1
wait || true
during changed grow_file "$WORK/changed/htdocs/wp-content/plugins/p/z.php"
scan changed "$WORK/changed" wp /var/www/htdocs 8.4 600 -e COMPAT_BATCH_SIZE=1 -e COMPAT_DEBUG=1
wait || true
stat -c %s "$WORK/changed/htdocs/wp-content/plugins/p/"*.php | awk '{ s += $1 } END { print s }' > "$RES/changed.bytes"
# A root uid 33 can't reach isn't no_code_found; a report that can't be published is a tool_error.
scan rootlock "$WORK/rootlock" wp /var/www/htdocs 8.4 600
estimate est-rootlock "$WORK/rootlock" wp /var/www/htdocs 8.4
OUT_DIR_AT=report.json scan reportdir "$WORK/empty" wp /var/www/htdocs 8.4 600
# A message longer than the reader's line limit is cut, not a failed scan.
scan bigmsg "$WORK/bigmsg" wp /var/www/htdocs 8.4 600
# Estimate settings: non-finite, and a range that doesn't contain the estimate.
estimate est-inf "$WORK/wp" wp /var/www/htdocs/current 8.4 -e COMPAT_SECONDS_PER_BATCH=1e309
estimate est-factors "$WORK/wp" wp /var/www/htdocs/current 8.4 -e COMPAT_LOW_FACTOR=2 -e COMPAT_HIGH_FACTOR=0.5

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

# Scope: everything in the WordPress directory but core; php code beside htdocs; roots behind bad links.
wpscope_fixture "$WORK/wpscope"
wpmoved_fixture "$WORK/wpmoved"
badlink_fixture "$WORK/wplink-dangling" wp /var/www/nowhere
badlink_fixture "$WORK/wplink-out" wp /etc
badlink_fixture "$WORK/phplink-dangling" php /var/www/nowhere
phpbeside_fixture "$WORK/phpbeside"
bedrock_fixture "$WORK/bedrock"
scan wpscope "$WORK/wpscope" wp /var/www/htdocs 8.4 600
estimate est-wpscope "$WORK/wpscope" wp /var/www/htdocs 8.4
scan wpmoved "$WORK/wpmoved" wp /var/www/htdocs 8.4 600
scan wplink-dangling "$WORK/wplink-dangling" wp /var/www/htdocs 8.4 600
scan wplink-out "$WORK/wplink-out" wp /var/www/htdocs 8.4 600
scan phplink-dangling "$WORK/phplink-dangling" php /var/www/htdocs 8.4 600
scan phpbeside "$WORK/phpbeside" php /var/www/htdocs 8.4 600
phpdeep_fixture "$WORK/phpdeep"
scan phpdeep "$WORK/phpdeep" php /var/www/htdocs 8.4 600
estimate est-phpbeside "$WORK/phpbeside" php /var/www/htdocs 8.4
# Bedrock scanned from its project root: config/, vendor/ and web/ but not core.
scan bedrock "$WORK/bedrock" wp /var/www/htdocs 8.4 600

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

# The code mount is read-only for the scanner: a directory uid 33 can write to takes the write without readonly, not with it.
mkdir -p "$WORK/mountprobe/htdocs" && chmod 0755 "$WORK/mountprobe" && chmod 0777 "$WORK/mountprobe/htdocs"
for m in rw ro; do
	opt=""; [ "$m" = ro ] && opt=",readonly"
	docker run --rm --network none --read-only --cap-drop ALL --user 33:33 \
		--mount "type=bind,src=$(realpath "$WORK/mountprobe"),dst=/var/www$opt" \
		--entrypoint sh "$IMAGE" -c "touch /var/www/htdocs/x-$m 2>/dev/null && echo writable || echo readonly" > "$RES/mount-$m"
done

# PHP code in other extensions and upper/mixed-case names; COMPAT_DEBUG=1 shows the batch/STDIN routing.
ext_fixture "$WORK/ext"
ext_php_fixture "$WORK/ext-php"
scan ext "$WORK/ext" wp /var/www/htdocs 8.4 600 -e COMPAT_DEBUG=1
estimate est-ext "$WORK/ext" wp /var/www/htdocs 8.4
scan ext-php "$WORK/ext-php" php /var/www/htdocs 8.4 600
estimate est-ext-php "$WORK/ext-php" php /var/www/htdocs 8.4

# A file deleted before its batch: unreadable.
changed_fixture "$WORK/changed-gone"
during changed-gone rm -f "$WORK/changed-gone/htdocs/wp-content/plugins/p/z.php"
scan changed-gone "$WORK/changed-gone" wp /var/www/htdocs 8.4 600 -e COMPAT_BATCH_SIZE=1 -e COMPAT_DEBUG=1
wait || true

# Repeated slashes in the path (site-command keeps --public-dir=a//b as typed); `..` is still refused.
scan slashes "$WORK/wp" wp /var/www//htdocs//current/ 8.4 600
scan php-rel-slashes "$WORK/php-rel" php /var/www/htdocs//current//public 8.4 600
estimate est-slashes "$WORK/wp" wp //var/www/htdocs//current 8.4
scan badargs-dotdot "$WORK/wp" wp /var/www/../etc 8.4 600
scan badargs-slashdot "$WORK/wp" wp /var/www//..//etc 8.4 600

# WordPress' rollback copies in wp-content/upgrade-temp-backup/: skipped as a dir, but their code files are checked.
tempbackup_fixture "$WORK/tempbackup"
scan tempbackup "$WORK/tempbackup" wp /var/www/htdocs 8.4 600

# Nothing in scope is skipped silently: skipped dirs that hold code, content roots other than wp-content, plugin and theme
# dirs named node_modules or .git, languages/, PHP under other names, phars, and other WordPress installs.
skipdirs_fixture "$WORK/skipdirs"
contentlike_fixture "$WORK/contentlike"
pluginnm_fixture "$WORK/pluginnm"
l10n_fixture "$WORK/l10n"
sniff_fixture "$WORK/sniff"
nested_fixture "$WORK/nested"
wordfence_fixture "$WORK/wordfence"
scan skipdirs "$WORK/skipdirs" wp /var/www/htdocs 8.4 600
scan skipdirs-files "$WORK/skipdirs" wp /var/www/htdocs 8.4 600 -e COMPAT_SKIPPED_FILES=7
scan skipdirs-bytes "$WORK/skipdirs" wp /var/www/htdocs 8.4 600 -e COMPAT_SKIPPED_BYTES=40000
scan wordfence "$WORK/wordfence" wp /var/www/htdocs 8.4 600
estimate est-skipdirs "$WORK/skipdirs" wp /var/www/htdocs 8.4
scan skipdirs-php "$WORK/skipdirs" php /var/www/htdocs 8.4 600
scan contentlike "$WORK/contentlike" wp /var/www/htdocs 8.4 600
scan pluginnm "$WORK/pluginnm" wp /var/www/htdocs 8.4 600
scan l10n "$WORK/l10n" wp /var/www/htdocs 8.4 600
scan sniff "$WORK/sniff" wp /var/www/htdocs 8.4 600
estimate est-sniff "$WORK/sniff" wp /var/www/htdocs 8.4
scan sniff-php "$WORK/sniff" php /var/www/htdocs 8.4 600
scan nested "$WORK/nested" wp /var/www/htdocs 8.4 600
estimate est-nested "$WORK/nested" wp /var/www/htdocs 8.4

# An estimate keeps time for calibration: throttled, the listing of 20,000 files can't finish in its share of 1 s.
estimate est-listing "$WORK/wide" wp /var/www/htdocs 8.4 -e COMPAT_ESTIMATE_TIMEOUT=1 --cpus 0.05

chmod -R a+rX "$RES"
docker run --rm --network none --read-only --user 33:33 \
	--mount "type=bind,src=$RES,dst=/r,readonly" \
	--mount "type=bind,src=$HERE/assert.php,dst=/t/assert.php,readonly" \
	--entrypoint php "$IMAGE" /t/assert.php /r
