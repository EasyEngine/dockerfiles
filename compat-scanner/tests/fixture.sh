#!/usr/bin/env bash
# Builds the fixture trees for run.sh. Sourced, not run.

# Writes a PHP file: php_file <path> [body]
php_file() {
	mkdir -p "$(dirname "$1")"
	printf '<?php\n%s\n' "${2:-}" > "$1"
}

# wp_fixture <app-dir> <errors:0|1> <unreadable:0|1>
# Lays out <app>/htdocs/current -> releases/1 (the public dir) with the WordPress cases of the EE tests.
wp_fixture() {
	local app=$1 errors=$2 unreadable=$3
	local rel="$app/htdocs/releases/1"
	local wc="$rel/wp-content"
	local bad=''
	[ "$errors" = 1 ] && bad='each( $a );'

	mkdir -p "$wc"
	ln -s /var/www/htdocs/releases/1 "$app/htdocs/current"

	# Core and code outside the public dir: never scanned.
	php_file "$rel/wp-includes/core.php" 'each( $a );'
	php_file "$rel/wp-settings.php" 'each( $a );'

	# wp-config.php above the release, loaded through releases/wp-config.php: scanned as its own component.
	php_file "$app/htdocs/wp-config.php" "define( 'DB_NAME', 'wp' );
$bad"
	ln -s ../wp-config.php "$app/htdocs/releases/wp-config.php"
	php_file "$app/htdocs/wp-content/plugins/outside/outside.php" 'each( $a );'

	# Plugin with a header and two removed functions.
	php_file "$wc/plugins/legacy/legacy.php" "/**
 * Plugin Name: Legacy Plugin
 * Version: 1.2.3
 */
$( [ "$errors" = 1 ] && printf '%s\n%s' '$f = create_function( "", "return 1;" );' 'each( $a );' )"
	php_file "$wc/plugins/legacy/inc/more.php" 'function legacy_more() { return 1; }'

	# WordPress' header-less stub in plugins/ belongs to `other`.
	php_file "$wc/plugins/index.php" '// Silence is golden.'

	# Single-file plugin.
	php_file "$wc/plugins/hello.php" "/*
Plugin Name: Hello Single
Version: 0.9
*/
$( [ "$errors" = 1 ] && printf '%s' 'ereg( "a", "b" );' )"

	# Warnings only: deprecated in 8.x, still works in 8.4.
	php_file "$wc/plugins/warnonly/warnonly.php" '/**
 * Plugin Name: Warn Only
 * Version: 3.0
 */
$x = utf8_encode( "a" );
$y = utf8_decode( "b" );'

	# Clean plugin, with node_modules and .git that are skipped at any depth.
	php_file "$wc/plugins/clean/clean.php" '/**
 * Plugin Name: Clean Plugin
 */
function clean_plugin() { return 1; }'
	php_file "$wc/plugins/clean/node_modules/pkg/x.php" 'each( $a );'
	php_file "$wc/plugins/clean/.git/hooks/y.php" 'each( $a );'

	# A plugin's own cache/, languages/ and plugins/ dirs are real code.
	php_file "$wc/plugins/cachey/cachey.php" '/* Plugin Name: Cachey */'
	php_file "$wc/plugins/cachey/cache/c.php" "$bad"
	php_file "$wc/plugins/cachey/plugins/p.php" "$bad"
	php_file "$wc/plugins/cachey/languages/l.php" 'return [];'

	# Bundled vendor/ library is kept.
	php_file "$wc/plugins/bundled/bundled.php" '/* Plugin Name: Bundled */'
	php_file "$wc/plugins/bundled/vendor/acme/lib/Old.php" "$( [ "$errors" = 1 ] && printf '%s' '$m = get_magic_quotes_runtime();' )"

	# Symlink loop: a link back to the plugin's own dir.
	php_file "$wc/plugins/loop/loop.php" '/* Plugin Name: Loop */'
	ln -s /var/www/htdocs/current/wp-content/plugins/loop "$wc/plugins/loop/self"

	# Syntax error plus a removed function: still tokenized and sniffed.
	php_file "$wc/plugins/broken/broken.php" "/* Plugin Name: Broken */
function broken( \$a, {
$( [ "$errors" = 1 ] && printf '%s' 'each( $a );' )"

	# PHPCS annotations are ignored: none of these hides the error.
	php_file "$wc/plugins/annotated/annotated.php" "/* Plugin Name: Annotated */
// phpcs:ignore PHPCompatibility.FunctionUse.RemovedFunctions.eachDeprecatedRemoved
$bad"
	php_file "$wc/plugins/annotated/whole.php" "// phpcs:ignoreFile
$bad"
	printf '<?php\n/**\n * File doc.\n *\n */\n// phpcs:ignoreFile\n%s\n' "$bad" > "$wc/plugins/annotated/late.php"
	php_file "$wc/plugins/annotated/disable.php" "// phpcs:disable
$bad"
	php_file "$wc/plugins/annotated/inline.php" "$bad // phpcs:ignore"

	# Hard links: one file, counted once.
	php_file "$wc/plugins/hardlink/h1.php" "/* Plugin Name: Hardlink */
$bad"
	ln "$wc/plugins/hardlink/h1.php" "$wc/plugins/hardlink/h2.php"

	# A .php link to a file with another extension is code WordPress loads.
	php_file "$wc/plugins/incl/incl.php" '/* Plugin Name: Incl */'
	php_file "$wc/plugins/incl/real.inc" "$bad"
	ln -s real.inc "$wc/plugins/incl/link.php"

	# Files are recorded in name order, also when one goes through STDIN (newline in the name).
	php_file "$wc/plugins/order/a
b.php" "$bad"
	php_file "$wc/plugins/order/b.php" "$bad"
	php_file "$wc/plugins/order/c.php" "/* Plugin Name: Order */
$bad"

	# Control, bidi and C1 characters in a file name and a header become U+FFFD.
	php_file "$wc/plugins/ctl/ctl.php" "/* Plugin Name: Ctl$(printf '\xe2\x80\xae')evil$(printf '\xc2\x9b')2J$(printf '\x7f') */"
	php_file "$wc/plugins/ctl/x$(printf '\xe2\x80\xae')gpj$(printf '\x1b')[31m.php" "$bad"

	# File name with invalid UTF-8.
	php_file "$wc/plugins/utf/utf.php" '/* Plugin Name: Utf */'
	php_file "$wc/plugins/utf/bad$(printf '\xff\xfe')name.php" "$bad"

	# More than 1,000 findings in one component.
	if [ "$errors" = 1 ]; then
		php_file "$wc/plugins/many/many.php" "/* Plugin Name: Many */
$(for _ in $(seq 1 1100); do printf 'each( $a );\n'; done)"
	fi

	if [ "$unreadable" = 1 ]; then
		# Dangling-symlink plugin, and a plugin dir uid 33 can't list.
		ln -s /var/www/htdocs/nowhere/dangling "$wc/plugins/dangling"
		php_file "$wc/plugins/locked/locked.php" '/* Plugin Name: Locked */'
		chmod 0700 "$wc/plugins/locked"
	fi

	# Theme with a style.css header and a removed call, plus a loose themes/ file.
	mkdir -p "$wc/themes/demo"
	printf '/*\nTheme Name: Demo Theme\nVersion: 2.1\n*/\n' > "$wc/themes/demo/style.css"
	php_file "$wc/themes/demo/functions.php" "$( [ "$errors" = 1 ] && printf '%s' '$q = get_magic_quotes_gpc();' )"
	php_file "$wc/themes/index.php" '// Silence is golden.'

	# A FIFO as style.css must not hang the scan; the theme is named by its slug.
	mkdir -p "$wc/themes/fifo"
	mkfifo "$wc/themes/fifo/style.css"
	php_file "$wc/themes/fifo/index.php" '// Theme index.'

	# mu-plugins is one component.
	php_file "$wc/mu-plugins/loader.php" 'require __DIR__ . "/sub/x.php";'
	php_file "$wc/mu-plugins/sub/x.php" '$s = "${a}";'

	# Drop-in and an unknown directory: `other`.
	php_file "$wc/object-cache.php" 'function wp_cache_init() {}'
	php_file "$wc/lib/helper.php" "$( [ "$errors" = 1 ] && printf '%s' '$h = create_function( "", "" );' )"

	# Links elsewhere to a plugin, a theme root or a plugin file: the component keeps its files.
	ln -s plugins/legacy "$wc/alib"
	ln -s plugins/hello.php "$wc/advanced-cache.php"

	# Links to the WordPress directory, an ancestor or core: never scanned.
	ln -s /var/www "$wc/zlib"
	ln -s .. "$wc/core"
	ln -s ../wp-includes "$wc/inc"
	ln -s ../wp-settings.php "$wc/cfg.php"

	# Top-level skips of the content root.
	php_file "$wc/uploads/evil.php" 'each( $a );'
	php_file "$wc/cache/c.php" 'each( $a );'
	php_file "$wc/upgrade/u.php" 'each( $a );'
	php_file "$wc/languages/l.php" 'each( $a );'
	php_file "$wc/node_modules/n.php" 'each( $a );'

	# Branch layout: wp-content/main is a second content root with its own skips.
	php_file "$wc/main/plugins/branchy/branchy.php" "/**
 * Plugin Name: Branchy
 * Version: 0.1
 */
$bad"
	php_file "$wc/main/uploads/evil.php" 'each( $a );'
	# Skipped by name, also when the link is dangling or leaves the mount.
	ln -s /mnt/shared/upgrade "$wc/main/upgrade"
	ln -s ../../../../../../elsewhere/cache "$wc/main/cache"
	php_file "$wc/main/lib2/x.php" 'function main_lib2() {}'
	ln -s ../themes "$wc/main/themes"

	chmod -R a+rX "$app"
	[ "$unreadable" = 1 ] && chmod 0700 "$wc/plugins/locked"
	return 0
}

# php_fixture <app-dir>: a plain PHP site; the root is htdocs, not the public dir.
php_fixture() {
	local app=$1 h="$1/htdocs"
	php_file "$h/index.php" 'require "app/boot.php";'
	php_file "$h/app/boot.php" 'each( $a );'
	php_file "$h/app/lib/util.php" '$x = utf8_encode( "a" );'
	php_file "$h/public/index.php" 'require "../app/boot.php";'
	php_file "$h/uploads/up.php" 'each( $a );'
	php_file "$h/cache/c.php" 'function c() {}'
	php_file "$h/vendor/acme/Old.php" '$h = create_function( "", "" );'
	php_file "$h/node_modules/x.php" 'each( $a );'
	php_file "$h/.git/y.php" 'each( $a );'
	chmod -R a+rX "$app"
}

# oom_fixture <app-dir>: one file whose PHPCS run outgrows a small container.
oom_fixture() {
	local p="$1/htdocs/wp-content/plugins/big"
	mkdir -p "$p"
	{ printf '<?php\n/* Plugin Name: Big */\n'; for i in $(seq 1 3000); do printf '$a%d = array( %d, "x" );\n' "$i" "$i"; done; } > "$p/chunk"
	{ cat "$p/chunk"; for _ in $(seq 1 99); do tail -n +3 "$p/chunk"; done; } > "$p/big.php"
	rm "$p/chunk"
	chmod -R a+rX "$1"
}

# flood_fixture <app-dir>: 20,000 findings in one file.
flood_fixture() {
	local p="$1/htdocs/wp-content/plugins/flood"
	mkdir -p "$p"
	{ printf '<?php\n/* Plugin Name: Flood */\n'; for _ in $(seq 1 20000); do printf 'each( $a );\n'; done; } > "$p/flood.php"
	chmod -R a+rX "$1"
}

# wide_fixture <app-dir>: 20,000 empty PHP files in one plugin.
wide_fixture() {
	local p="$1/htdocs/wp-content/plugins/wide"
	local d
	for d in $(seq 1 20); do
		mkdir -p "$p/d$d"
		seq 1 1000 | sed "s|^|$p/d$d/file-with-a-longer-name-|; s|\$|.php|" | xargs touch
	done
	chmod -R a+rX "$1"
}

# wpcfg_fixture <app-dir> <dir|parent>: wp-config.php in the WordPress dir (htdocs) or only in its parent.
wpcfg_fixture() {
	local app=$1 where=$2
	php_file "$app/htdocs/wp-content/plugins/p/p.php" '/* Plugin Name: P */'
	php_file "$app/wp-config.php" 'each( $a );'
	[ "$where" = dir ] && php_file "$app/htdocs/wp-config.php" '$f = create_function( "", "" );'
	chmod -R a+rX "$app"
}

# php_release_fixture <app-dir> <real|link>: a php site with htdocs/current -> releases/2.
# With `link`, releases/ is itself a symlink, so the layout isn't recognised and every release is scanned.
php_release_fixture() {
	local app=$1 kind=$2 h="$1/htdocs"
	local store="$h/releases"
	[ "$kind" = link ] && store="$h/release-store"
	php_file "$h/index.php" '// front controller'
	php_file "$store/1/app.php" 'each( $a );'
	php_file "$store/2/app.php" 'each( $a );'
	php_file "$store/2/public/index.php" 'require "../app.php";'
	php_file "$store/hook.php" '// deploy hook'
	php_file "$h/shared/lib.php" '$h = create_function( "", "" );'
	[ "$kind" = link ] && ln -s release-store "$h/releases"
	ln -s releases/2 "$h/current"
	chmod -R a+rX "$app"
}

# slow_php <path>: a clean file that keeps one PHPCS run busy for about two seconds.
slow_php() {
	mkdir -p "$(dirname "$1")"
	{ printf '<?php\n'; for i in $(seq 1 6000); do printf '$a%d = array( 1, 2, 3 ) + [ %d ];\n' "$i" "$i"; done; } > "$1"
}

# switch_fixture <app-dir>: a php site with htdocs/current -> releases/A; B fixes A's error and adds a new one.
switch_fixture() {
	local h="$1/htdocs"
	slow_php "$h/releases/A/public/a-slow.php"
	php_file "$h/releases/A/public/b.php" 'each( $a );'
	slow_php "$h/releases/B/public/a-slow.php"
	php_file "$h/releases/B/public/b.php" '$b = 1;'
	php_file "$h/releases/B/public/c.php" 'each( $a );'
	ln -s releases/A "$h/current"
	chmod -R a+rX "$1"
}

# changed_fixture <app-dir>: a plugin whose second file run.sh grows while the first one is scanned.
changed_fixture() {
	local p="$1/htdocs/wp-content/plugins/p"
	slow_php "$p/a-slow.php"
	php_file "$p/z.php" '$z = 1;'
	chmod -R a+rX "$1"
}

# locked_root_fixture <app-dir>: a wp site whose htdocs uid 33 can't search.
locked_root_fixture() {
	php_file "$1/htdocs/wp-content/plugins/p/p.php" 'each( $a );'
	chmod -R a+rX "$1"
	chmod 0700 "$1/htdocs"
}

# bigmsg_fixture <app-dir>: a finding whose message quotes more than 1 MiB of code.
bigmsg_fixture() {
	local p="$1/htdocs/wp-content/plugins/p"
	mkdir -p "$p"
	printf "<?php\nfunction f() {\n\tglobal \$\$x['%s'];\n}\n" "$(head -c 1100000 /dev/zero | tr '\0' a)" > "$p/big.php"
	chmod -R a+rX "$1"
}

# ext_fixture <app-dir>: a wp site with PHP code in other extensions and in upper/mixed-case names.
ext_fixture() {
	local wc="$1/htdocs/wp-content" f
	php_file "$wc/plugins/ext/ext.php" '/* Plugin Name: Ext */'
	for f in x.inc x.phtml x.module x.install x.theme x.engine x.php5 x.php7 UPPER.PHP Mixed.Inc; do
		php_file "$wc/plugins/ext/$f" 'each( $a );'
	done
	# Not code: never listed.
	for f in readme.txt x.phps x.js; do php_file "$wc/plugins/ext/$f" 'each( $a );'; done
	ln -s nowhere.inc "$wc/plugins/ext/gone.inc"

	# Only a lowercase .php file is a single-file plugin or a header candidate, as in WordPress.
	php_file "$wc/plugins/legacy.inc" '/* Plugin Name: Not A Plugin */
each( $a );'
	php_file "$wc/plugins/Loose.PHP" '/* Plugin Name: Not A Plugin Either */
each( $a );'
	ln -s nowhere.inc "$wc/plugins/gone.inc"
	php_file "$wc/plugins/hdr/main.inc" '/* Plugin Name: Wrong */'
	php_file "$wc/plugins/hdr/MAIN.PHP" '/* Plugin Name: Wrong Too */'

	# One file under two code names: the first in sorted order wins. A code name linking to a non-code file is checked under the link name.
	php_file "$wc/plugins/dedup/dedup.php" '/* Plugin Name: Dedup */'
	php_file "$wc/plugins/dedup/a.inc" 'each( $a );'
	ln -s a.inc "$wc/plugins/dedup/z.php"
	php_file "$wc/plugins/dedup/data.txt" 'each( $a );'
	ln -s data.txt "$wc/plugins/dedup/b.inc"

	mkdir -p "$wc/themes"
	ln -s nowhere.inc "$wc/themes/gone.inc"
	chmod -R a+rX "$1"
}

# ext_php_fixture <app-dir>: a php site with code only in non-.php names.
ext_php_fixture() {
	local h="$1/htdocs"
	php_file "$h/x.inc" 'each( $a );'
	php_file "$h/app/Y.PHTML" 'each( $a );'
	php_file "$h/app/readme.txt" 'each( $a );'
	mkdir -p "$h" && ln -s nowhere.inc "$h/gone.inc"
	chmod -R a+rX "$1"
}
