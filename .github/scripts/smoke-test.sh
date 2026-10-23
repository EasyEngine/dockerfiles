#!/usr/bin/env bash
# Smoke-test one built image on one arch.
# Usage: smoke-test.sh <image-name> <image-ref> <arch>
#   image-name: php8.1..php8.5, nginx, nginx-proxy, postfix, redis, cron, mailhog, mariadb, newrelic-daemon
#   arch:       amd64 | arm64
set -euo pipefail

name=$1 ref=$2 arch=$3
cid=""
cleanup() { [ -n "$cid" ] && docker rm -f "$cid" >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail() { echo "FAIL [$name/$arch]: $*" >&2; exit 1; }
run() { docker run --rm --platform "linux/$arch" "$@"; }
start() { cid=$(docker run -d --platform "linux/$arch" "$@"); }
# Retry a command inside the started container; emulated arm64 can be slow to boot.
wait_exec() {
	local tries=$1; shift
	for _ in $(seq "$tries"); do
		if docker exec "$cid" "$@" >/dev/null 2>&1; then return 0; fi
		sleep 2
	done
	docker logs "$cid" 2>&1 | tail -20 >&2
	return 1
}

# A wrong-arch binary can still run (QEMU/binfmt), so check the ELF e_machine of the key binaries too.
elf_check() {
	local want=3e
	[ "$arch" = arm64 ] && want=b7
	run --entrypoint sh "$ref" -c '
		for f; do
			case $f in /*) p=$f ;; *) p=$(command -v "$f") ;; esac
			echo "$f $(od -An -t x1 -j 18 -N 1 "$p" 2>/dev/null | tr -d " ")"
		done' sh "$@" | while read -r f m; do
		[ "$m" = "$want" ] || fail "$f is not a linux/$arch ELF (e_machine=${m:-none})"
		echo "elf ok: $f"
	done
}

got=$(docker image inspect -f '{{.Os}}/{{.Architecture}}' "$ref")
[ "$got" = "linux/$arch" ] || fail "image platform is $got, want linux/$arch"

case $name in
php*)
	ver=${name#php}
	run "$ref" php -v
	ext=$(run "$ref" php -r 'echo ini_get("extension_dir");')
	bins="php php-fpm $ext/imagick.so $ext/redis.so $ext/memcached.so"
	[ "$ver" != "8.5" ] && bins="$bins $ext/newrelic.so /usr/bin/newrelic-daemon"
	# shellcheck disable=SC2086
	elf_check $bins
	mods=$(run "$ref" php -m | tr '[:upper:]' '[:lower:]')
	want="apcu bcmath calendar exif gd gmp imagick imap intl mcrypt memcached mysqli pcntl pdo_mysql redis shmop soap sockets sysvsem sysvshm timezonedb zend.opcache zip"
	# gmagick and New Relic are not built for 8.5 (see php/8.5/Dockerfile).
	[ "$ver" != "8.5" ] && want="$want gmagick newrelic"
	for m in $want; do
		grep -qx "${m/./ }" <<<"$mods" || fail "php module $m missing"
	done
	run "$ref" php -r '$g = gd_info(); exit($g["WebP Support"] && $g["FreeType Support"] && $g["JPEG Support"] && $g["PNG Support"] ? 0 : 1);' \
		|| fail "gd lacks WebP/FreeType/JPEG/PNG"
	run "$ref" php -r 'exit(count(Imagick::queryFormats()) > 50 ? 0 : 1);' || fail "imagick has too few formats"
	run "$ref" composer --version
	run "$ref" wp --version
	run "$ref" php-fpm -t
	if [ "$ver" != "8.5" ]; then
		run "$ref" sh -c '/usr/bin/newrelic-daemon --version | head -1' || fail "newrelic-daemon missing"
	fi
	echo "modules: $(tr '\n' ' ' <<<"$mods")"
	;;
nginx)
	elf_check openresty
	run --entrypoint sh "$ref" -c 'echo "server { listen 80; }" > /usr/local/openresty/nginx/conf/conf.d/main.conf && nginx -V 2>&1 | head -1 && nginx -t'
	;;
nginx-proxy)
	elf_check nginx docker-gen forego
	run --entrypoint sh "$ref" -c 'nginx -v && docker-gen -version && command -v forego htpasswd && grep -q "define \"acl\"" /app/nginx.tmpl && nginx -t'
	;;
redis)
	elf_check redis-server
	run "$ref" redis-server --version
	extra=()
	# Redis's arm64 fork/COW self-test fails under QEMU user emulation only; native arm64 must pass without this.
	host=$(uname -m)
	[ "$arch" = arm64 ] && [ "$host" != aarch64 ] && extra=(--ignore-warnings ARM64-COW-BUG)
	start "$ref" redis-server /usr/local/etc/redis/redis.conf "${extra[@]}"
	wait_exec 30 sh -c '[ "$(redis-cli ping)" = PONG ]' || fail "redis did not answer PING"
	docker exec "$cid" test -f /data/purge_all_cache.lua || fail "purge_all_cache.lua missing"
	;;
mariadb)
	elf_check mariadbd
	start -e MARIADB_ROOT_PASSWORD=smoke "$ref"
	wait_exec 90 mariadb -uroot -psmoke -e 'SELECT 1' || fail "mariadb did not start"
	docker exec "$cid" mariadb -uroot -psmoke -N -e 'SELECT VERSION()'
	;;
postfix)
	elf_check /usr/sbin/postfix /usr/lib/postfix/smtpd
	run "$ref" postconf -h mail_version
	start "$ref"
	wait_exec 30 postfix status || fail "postfix did not start"
	;;
cron)
	elf_check ofelia
	run --entrypoint sh "$ref" -c 'printf "[job-local \"smoke\"]\nschedule = @every 1h\ncommand = true\n" > /tmp/c.ini && ofelia validate --config=/tmp/c.ini'
	;;
mailhog)
	elf_check MailHog
	start "$ref" -invite-jim=false
	wait_exec 30 sh -c 'printf "GET /api/v2/messages HTTP/1.0\r\n\r\n" | nc 127.0.0.1 8025 | grep -q "\"total\""' || fail "mailhog API not up"
	docker exec "$cid" sh -c 'printf "HELO smoke\r\nMAIL FROM:<a@smoke.test>\r\nRCPT TO:<b@smoke.test>\r\nDATA\r\nSubject: smoke\r\n\r\nhi\r\n.\r\nQUIT\r\n" | nc 127.0.0.1 1025 >/dev/null'
	wait_exec 10 sh -c 'printf "GET /api/v2/messages HTTP/1.0\r\n\r\n" | nc 127.0.0.1 8025 | grep -q "\"total\":1"' || fail "mailhog did not receive the test mail"
	;;
newrelic-daemon)
	elf_check /usr/local/bin/newrelic-daemon
	run "$ref" /usr/local/bin/newrelic-daemon --version
	start "$ref"
	sleep 5
	[ "$(docker inspect -f '{{.State.Running}}' "$cid")" = true ] || { docker logs "$cid" >&2; fail "newrelic-daemon exited"; }
	;;
*)
	fail "unknown image"
	;;
esac

echo "OK [$name/$arch] $ref"
