#!/usr/bin/env bash
# Fail when a built PHP image lacks an expected module, warns on startup,
# or has a conf.d ini that loads a missing .so (a failed `pecl install` is
# otherwise swallowed by the Dockerfile's `;`-chained RUN).
# Usage: check-php-image.sh <image> <expected-modules-file>
set -uo pipefail

image=${1:?image}
expected=${2:?expected modules file}
errors=()

# A missing list would otherwise check nothing and pass (e.g. a new PHP version).
if ! grep -qv -e '^#' -e '^[[:space:]]*$' "$expected" 2>/dev/null; then
	echo "::error title=PHP image check failed ($image)::expected modules file $expected is missing or empty"
	exit 1
fi

run() { docker run --rm --pull=never --entrypoint sh "$image" -c "$1" 2>&1; }

# 1. Expected modules (extra modules are fine).
if ! modules=$(docker run --rm --pull=never --entrypoint php "$image" -m 2>&1); then
	errors+=("php -m failed: $modules")
fi
# Command substitution (not process substitution) so a read failure stops the
# check, and the here-string also covers a last line without a newline.
if ! wanted=$(sed -e 's/[[:space:]]*$//' -e '/^#/d' "$expected"); then
	echo "::error title=PHP image check failed ($image)::cannot read $expected"
	exit 1
fi
missing=()
while IFS= read -r m; do
	[ -z "$m" ] && continue
	grep -Fxq -- "$m" <<<"$modules" || missing+=("$m")
done <<<"$wanted"
[ ${#missing[@]} -gt 0 ] && errors+=("missing modules: ${missing[*]}")

# 2. Startup must be silent, and the FPM config must load cleanly.
startup=$(run 'php -r "exit(0);"') || errors+=("php exited non-zero on startup")
[ -n "$startup" ] && errors+=("php startup output (warnings): $startup")

if ! fpm=$(run 'php-fpm -t'); then
	errors+=("php-fpm -t failed: $fpm")
elif grep -Eiq 'warning|unable to load' <<<"$fpm"; then
	errors+=("php-fpm -t warnings: $fpm")
fi

# 3. Every extension= / zend_extension= line in the scanned ini dir must resolve to a file.
dangling=$(run '
	ext_dir=$(php -r "echo ini_get(\"extension_dir\");" 2>/dev/null)
	ini_dir=$(php -r "echo PHP_CONFIG_FILE_SCAN_DIR;" 2>/dev/null)
	for f in "$ini_dir"/*.ini; do
		[ -f "$f" ] || continue
		sed -n "s/^[[:space:]]*\(zend_\)\{0,1\}extension[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\";[:space:]]*\).*/\2/p" "$f" |
		while IFS= read -r so; do
			[ -z "$so" ] && continue
			case "$so" in
				/*) path=$so ;;
				*.so) path=$ext_dir/$so ;;
				*) path=$ext_dir/$so.so ;;
			esac
			[ -f "$path" ] || echo "$(basename "$f") -> $path"
		done
	done
')
[ -n "$dangling" ] && errors+=("ini files load a missing .so: $dangling")

# 4. Every loaded extension must report a real version: a source built from git can report a
# placeholder such as @PACKAGE_VERSION@, which version gates (WordPress's Imagick check) reject.
versions_php='foreach (get_loaded_extensions() as $e) { $v = phpversion($e); echo (is_string($v) && $v !== "" && strpos($v, "@") === false) ? "ok" : "bad", " ", $e, "=", var_export($v, true), "\n"; }'
if ! versions=$(docker run --rm --pull=never --entrypoint php "$image" -r "$versions_php" 2>&1); then
	errors+=("extension version check failed: $versions")
elif bad=$(grep -v '^ok ' <<<"$versions"); then
	errors+=("extensions without a real version: ${bad//$'\n'/, }")
fi

# 5. Imagick must encode AVIF (WordPress's AVIF uploads need libheif's encoder plugin) and read it back.
avif_php='try {
	$i = new Imagick(); $i->newImage(64, 64, new ImagickPixel("red")); $i->setImageFormat("avif");
	$b = $i->getImageBlob();
	if (substr($b, 4, 8) !== "ftypavif") { echo "not an AVIF file: ", bin2hex(substr($b, 0, 16)); exit(1); }
	$r = new Imagick(); $r->readImageBlob($b);
	if ($r->getImageWidth() !== 64) { echo "read back ", $r->getImageFormat(), " ", $r->getImageWidth(), "px"; exit(1); }
} catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(); exit(1); }'
avif=$(docker run --rm --pull=never --entrypoint php "$image" -r "$avif_php" 2>&1) || errors+=("AVIF encode failed: $avif")

# 6. The entrypoint's New Relic setup, run as www-data on a www-data owned conf.d (as `ee site enable` leaves it):
# values with sed metacharacters, a restart with the same values, a changed key, an app name already set (kept), a refused value, a missing ini.
nr_check='
ini=/usr/local/etc/php/conf.d/newrelic.ini
start() { setpriv --reuid=www-data --regid=www-data --init-groups docker-entrypoint.sh "$@"; }
[ -f /data/newrelic.ini ] || echo "/data/newrelic.ini is missing"
chown -R www-data: /usr/local/etc/php/conf.d
check() { # check <label> <expected app name>
	out=$(NR_APP=$2 start php -r "echo ini_get(\"newrelic.license\") === getenv(\"NEWRELIC_LICENSE_KEY\") && ini_get(\"newrelic.appname\") === getenv(\"NR_APP\") ? \"ok\" : \"PHP reads \" . var_export(ini_get(\"newrelic.license\"), true) . \" / \" . var_export(ini_get(\"newrelic.appname\"), true);" 2>&1)
	[ "$out" = ok ] || echo "$1: $out"
}
app1="ci & co/app|1" app2="ci & co/app|2"
# 40 characters: the agent ignores a license of any other length.
export NEWRELIC_LICENSE_KEY="ci/key&1|0123456789abcdef0123456789abcde" NEWRELIC_APPNAME=$app1
check "first start" "$app1"
before="$(stat -c %i "$ini") $(cksum < "$ini")"; check "restart" "$app1"
[ "$(stat -c %i "$ini") $(cksum < "$ini")" = "$before" ] || echo "a restart with the same values changed $ini"
NEWRELIC_LICENSE_KEY="ci/key&2|0123456789abcdef0123456789abcde"; check "key change" "$app1"
NEWRELIC_APPNAME=$app2; check "app name already set" "$app1"
cp "$ini" /tmp/nr.ini
out=$(NEWRELIC_APPNAME="ci\"app" start true 2>&1) || echo "a value with a quote stopped the entrypoint: $out"
cmp -s /tmp/nr.ini "$ini" || echo "a value with a quote changed $ini"
[ -n "$out" ] || echo "a value with a quote was refused silently"
rm "$ini"; check "missing newrelic.ini" "$app2"
# 8.1 turns off six agent features (newrelic-php-agent#577), also in a site ini without them (from a php-fpm zip), keeping a value set by hand; 8.2+ add none.
export NR577="cross_application_tracer.enabled distributed_tracing_enabled span_events_enabled application_logging.enabled application_logging.forwarding.enabled application_logging.metrics.enabled"
cat > /tmp/nr577.php <<"PHP"
<?php
foreach (explode(" ", getenv("NR577")) as $k) {
	$v = ini_get("newrelic.$k");
	if (getenv("NR_ON") === $k ? $v !== "1" : !in_array($v, ["", "0"], true)) echo "newrelic.$k reads ", var_export($v, true), "; ";
}
PHP
ver=$(php -r "echo PHP_MAJOR_VERSION, \".\", PHP_MINOR_VERSION;")
[ "$ver" = 8.1 ] && want="1 1 1 1 1 1" || want="0 0 0 0 0 0"
lines577() { for k in $NR577; do grep -ac "^[[:space:]]*newrelic\.${k//./\\.}[[:space:]]*=" "$ini"; done | xargs; }
strip577() { grep -av -E "^[[:space:]]*newrelic\.(cross_application_tracer\.enabled|distributed_tracing_enabled|span_events_enabled|application_logging\.(enabled|forwarding\.enabled|metrics\.enabled))[[:space:]]*=" "$ini" > /tmp/nr-strip.ini; cat /tmp/nr-strip.ini > "$ini"; }
nr577() { # nr577 <label> [key set to true by hand]
	out=$(NR_ON=${2:-} start php /tmp/nr577.php 2>&1)
	[ "$ver" != 8.1 ] || [ -z "$out" ] || echo "$1: $out"
	[ "$(lines577)" = "$want" ] || echo "$1: newrelic.ini sets the #577 keys $(lines577) times, want $want"
}
strip577; nr577 "ini without the #577 block"
before="$(stat -c %i "$ini") $(cksum < "$ini")"; nr577 "restart without the #577 block"
[ "$(stat -c %i "$ini") $(cksum < "$ini")" = "$before" ] || echo "a restart changed $ini after the #577 keys were added"
if [ "$ver" = 8.1 ]; then
	strip577; echo "newrelic.span_events_enabled = true" >> "$ini"; nr577 "span events set by hand" span_events_enabled
fi
fpm=$(start php-fpm -t 2>&1) || echo "php-fpm -t failed: $fpm"
grep -Ei "warning|unable to load" <<<"$fpm" || true
'
# Images without the extension (8.6) skip it; a missing extension on the others is already a missing module.
if ! grep -qx newrelic <<<"$modules"; then
	:
elif ! nr=$(docker run --rm --pull=never --user root --entrypoint bash "$image" -c "$nr_check" 2>&1); then
	errors+=("New Relic entrypoint check failed to run: $nr")
elif [ -n "$nr" ]; then
	errors+=("New Relic entrypoint check: $nr")
fi

if [ ${#errors[@]} -gt 0 ]; then
	for e in "${errors[@]}"; do
		# Keep multi-line details inside one annotation.
		e=${e//'%'/'%25'}; e=${e//$'\n'/'%0A'}
		echo "::error title=PHP image check failed ($image)::$e"
	done
	exit 1
fi
echo "$image: all $(grep -cv -e '^#' -e '^[[:space:]]*$' "$expected") expected modules present, clean startup, no dangling extension ini, every extension reports a version, Imagick encodes AVIF, New Relic entrypoint ok (when loaded)."
# Third-party versions (those that differ from PHP's own) for the build log.
php_version=$(docker run --rm --pull=never --entrypoint php "$image" -r 'echo PHP_VERSION;' 2>/dev/null)
echo "$image: PHP $php_version; $(sed -n "s/^ok \([^=]*\)='\(.*\)'$/\1 \2/p" <<<"$versions" | grep -v " $php_version\$" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
