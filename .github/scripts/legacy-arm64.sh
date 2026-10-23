#!/usr/bin/env bash
# One-time arm64 builds of images outside the build matrix; recipes in .github/legacy-arm64/recipes.json.
# Usage:
#   legacy-arm64.sh prepare  <image> <dir>               build context = recipe ref + <image>.patch
#   legacy-arm64.sh facts    <image> <ref> <dir>         collect what must match across arches
#   legacy-arm64.sh elf      <image> <ref>               key binaries must be linux/arm64 ELF
#   legacy-arm64.sh compare  <image> <amd64-dir> <arm64-dir>
#   legacy-arm64.sh tag-free <repo> <tag>                fails if the Docker Hub tag exists
set -euo pipefail

cmd=$1 img=$2
shift 2
dir=$(cd "$(dirname "$0")/../legacy-arm64" && pwd)
recipe() { jq -er --arg i "$img" '.[$i].'"$1" "$dir/recipes.json"; }
fail() { echo "::error::$img: $*" >&2; exit 1; }

# Host- or arch-specific server variables, excluded from the MariaDB comparison.
VAR_EXCLUDE='hostname|pid_file|general_log_file|slow_query_log_file|log_bin_basename|log_bin_index|relay_log_basename|relay_log_index|server_uid|version_compile_machine|thread_pool_size|large_page_size|wsrep_node_name'

prepare() {
	local out=$1 ref ctx nr
	ref=$(recipe ref) ctx=$(recipe context) nr=$(recipe newrelic)
	[ "$nr" = unavailable ] && fail "New Relic publishes no aarch64 agent for this PHP version, but the amd64 image has it. Set \"newrelic\": \"skip\" in recipes.json to build arm64 without it, or leave $img amd64-only."
	rm -rf "$out" && mkdir -p "$out"
	# Forks may lack the upstream tags these commits sit on.
	git cat-file -e "$ref^{commit}" 2>/dev/null || git fetch -q --depth=1 https://github.com/EasyEngine/dockerfiles.git "$ref"
	git archive "$ref" "$ctx" | tar -x -C "$out" --strip-components="$(awk -F/ '{print NF}' <<<"$ctx")"
	patch -d "$out" -p1 --forward --batch --no-backup-if-mismatch <"$dir/$img.patch"
	if [ "$nr" = skip ]; then
		# Drop the agent but keep newrelic.ini without its extension line, so the entrypoint's sed still finds it.
		sed -i -e '/^RUN latest_build=/,/rm -rf \/tmp\/newrelic-php5-/d' "$out/Dockerfile"
		sed -i -e '/^extension *= *"newrelic.so"/d' "$out/newrelic.ini"
		! grep -q newrelic-install "$out/Dockerfile" || fail "could not drop the New Relic agent"
	fi
	cat "$out/Dockerfile"
}

facts() {
	local ref=$1 out=$2
	mkdir -p "$out"
	docker image inspect -f '{{json .Config}}' "$ref" |
		jq -S '{User, Entrypoint, Cmd, WorkingDir, Env, ExposedPorts, Volumes, Labels, StopSignal, Healthcheck}' >"$out/config.json"
	case $img in
	php*)
		local run=(docker run --rm "$ref")
		"${run[@]}" php -r 'echo PHP_VERSION, "\n";' >"$out/version"
		"${run[@]}" php -m >"$out/modules" 2>&1
		"${run[@]}" php -r '$e = get_loaded_extensions(); sort($e); foreach ($e as $x) echo $x, " ", phpversion($x), "\n";' >"$out/extensions" 2>&1
		"${run[@]}" php -r '$a = ini_get_all(null, false); ksort($a); foreach ($a as $k => $v) echo $k, "=", $v, "\n";' >"$out/ini" 2>&1
		"${run[@]}" php-fpm -t >"$out/fpm.log" 2>&1 && echo ok >"$out/fpm" || echo failed >"$out/fpm"
		docker run --rm --entrypoint sh "$ref" -c 'find /usr/local/etc -type f | sort | xargs sha256sum' >"$out/etc"
		{
			"${run[@]}" sh -c 'composer --version 2>/dev/null | head -1' || echo "composer failed"
			"${run[@]}" wp --version || echo "wp failed"
		} >"$out/tools" 2>&1
		docker run --rm --entrypoint dpkg-query "$ref" -W -f '${Package} ${Version}\n' >"$out/dpkg"
		;;
	mariadb)
		cid=$(docker run -d -e MARIADB_ROOT_PASSWORD=smoke "$ref")
		trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
		for _ in $(seq 90); do docker exec "$cid" mariadb -uroot -psmoke -e 'SELECT 1' >/dev/null 2>&1 && break; sleep 2; done
		docker exec "$cid" mariadb -uroot -psmoke -N -e 'SELECT VERSION()' >"$out/version" || { docker logs "$cid" | tail -30; fail "mariadb did not start"; }
		docker exec "$cid" mariadb -uroot -psmoke -N -e 'SHOW GLOBAL VARIABLES' | grep -vE "^($VAR_EXCLUDE)\s" >"$out/variables"
		docker exec "$cid" sh -c 'find /etc/mysql -printf "%M %u:%g %p\n" | sort; find /etc/mysql -type f | sort | xargs sha256sum' >"$out/etc"
		docker exec "$cid" dpkg-query -W -f '${Package} ${Version}\n' >"$out/dpkg"
		;;
	*) fail "no facts for this image" ;;
	esac
	head -n 50 "$out"/version "$out"/modules "$out"/tools 2>/dev/null || true
}

elf() {
	local ref=$1 got
	got=$(docker image inspect -f '{{.Os}}/{{.Architecture}}' "$ref")
	[ "$got" = linux/arm64 ] || fail "image platform is $got"
	local list
	case $img in
	php*) list='ext=$(php -r "echo ini_get(\"extension_dir\");"); set -- "$(command -v php)" "$(command -v php-fpm)" "$ext"/*.so; [ -e /usr/bin/newrelic-daemon ] && set -- "$@" /usr/bin/newrelic-daemon' ;;
	mariadb) list='set -- "$(command -v mariadbd)" "$(command -v mariadb)" "$(command -v gosu)" "$(command -v my_print_defaults)"' ;;
	esac
	docker run --rm --entrypoint sh "$ref" -c "$list"'; for f; do echo "$f $(od -An -t x1 -j 18 -N 1 "$f" | tr -d " ")"; done' |
		while read -r f m; do
			[ "$m" = b7 ] || fail "$f is not an arm64 ELF (e_machine=${m:-none})"
			echo "elf ok: $f"
		done
}

compare() {
	local a=$1 b=$2 nr absent bad=0 f
	nr=$(recipe newrelic)
	# ini settings that don't exist on arm64 for this PHP version (documented in the recipe).
	absent=$(recipe arm64_ini_absent 2>/dev/null || true)
	if [ -n "$absent" ]; then
		grep -E "$absent" "$b/ini" && { echo "arm64 has settings expected to be absent"; bad=1; }
		grep -E "$absent" "$a/ini" | sed 's/^/absent on arm64: /'
		grep -vE "$absent" "$a/ini" >"$a/ini.tmp" && mv "$a/ini.tmp" "$a/ini"
	fi
	for f in config.json version modules extensions ini fpm etc variables; do
		[ -e "$a/$f" ] || continue
		if [ "$nr" = skip ] && [ "$f" != config.json ]; then
			grep -q newrelic.so "$b/$f" && { echo "arm64 $f mentions newrelic.so"; bad=1; }
			if diff -u <(grep -v newrelic "$a/$f") <(grep -v newrelic "$b/$f"); then echo "same: $f (New Relic left out)"; else bad=1; fi
		elif diff -u "$a/$f" "$b/$f"; then
			echo "same: $f"
		else
			bad=1
		fi
	done
	if [ -e "$a/tools" ]; then
		echo "--- informational: tools"
		diff "$a/tools" "$b/tools" || true
	fi
	if [ -e "$a/dpkg" ]; then
		echo "--- informational: packages (amd64 $(wc -l <"$a/dpkg"), arm64 $(wc -l <"$b/dpkg"))"
		diff "$a/dpkg" "$b/dpkg" || true
	fi
	[ "$bad" = 0 ] || fail "arm64 differs from the published amd64 image (see the diff above)"
}

tag_free() {
	local tag=$1 tok code
	tok=$(curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$img:pull" | jq -r .token)
	code=$(curl -sS -o /dev/null -w '%{http_code}' -I -H "Authorization: Bearer $tok" \
		-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' \
		"https://registry-1.docker.io/v2/$img/manifests/$tag")
	case $code in
	404) echo "$img:$tag does not exist yet" ;;
	200) fail "$img:$tag already exists; tags are never overwritten" ;;
	*) fail "could not check $img:$tag (HTTP $code)" ;;
	esac
}

case $cmd in
prepare | facts | elf | compare) "$cmd" "$@" ;;
tag-free) tag_free "$@" ;;
*) echo "unknown command $cmd" >&2; exit 2 ;;
esac
