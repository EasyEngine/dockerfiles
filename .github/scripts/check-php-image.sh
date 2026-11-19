#!/usr/bin/env bash
# Fail when a built PHP image lacks an expected module, warns on startup,
# or has a conf.d ini that loads a missing .so (a failed `pecl install` is
# otherwise swallowed by the Dockerfile's `;`-chained RUN).
# Usage: check-php-image.sh <image> <expected-modules-file>
set -uo pipefail

image=${1:?image}
expected=${2:?expected modules file}
errors=()

run() { docker run --rm --pull=never --entrypoint sh "$image" -c "$1" 2>&1; }

# 1. Expected modules (extra modules are fine).
if ! modules=$(docker run --rm --pull=never --entrypoint php "$image" -m 2>&1); then
	errors+=("php -m failed: $modules")
fi
missing=()
while IFS= read -r m; do
	[ -z "$m" ] && continue
	grep -Fxq -- "$m" <<<"$modules" || missing+=("$m")
done < <(sed -e 's/[[:space:]]*$//' -e '/^#/d' "$expected")
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
	ext_dir=$(php -r "echo ini_get(\"extension_dir\");")
	ini_dir=$(php -r "echo PHP_CONFIG_FILE_SCAN_DIR;")
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

if [ ${#errors[@]} -gt 0 ]; then
	for e in "${errors[@]}"; do
		# Keep multi-line details inside one annotation.
		e=${e//'%'/'%25'}; e=${e//$'\n'/'%0A'}
		echo "::error title=PHP image check failed ($image)::$e"
	done
	exit 1
fi
echo "$image: all $(grep -cv -e '^#' -e '^[[:space:]]*$' "$expected") expected modules present, clean startup, no dangling extension ini."
