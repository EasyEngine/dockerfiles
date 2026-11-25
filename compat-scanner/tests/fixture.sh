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

	# Clean plugin, with node_modules and .git (skipped at any depth): only their code files are checked.
	php_file "$wc/plugins/clean/clean.php" '/**
 * Plugin Name: Clean Plugin
 */
function clean_plugin() { return 1; }'
	if [ "$errors" = 1 ]; then
		php_file "$wc/plugins/clean/node_modules/pkg/x.php" 'each( $a );'
		php_file "$wc/plugins/clean/.git/hooks/y.php" 'each( $a );'
	else
		mkdir -p "$wc/plugins/clean/node_modules/pkg" "$wc/plugins/clean/.git/hooks"
		printf 'module.exports = 1;\n' > "$wc/plugins/clean/node_modules/pkg/index.js"
		printf '#!/bin/sh\n' > "$wc/plugins/clean/.git/hooks/pre-commit.sample"
	fi

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

	# Top-level skips of the content root: only their code files are checked; with none they add nothing.
	if [ "$errors" = 1 ]; then
		php_file "$wc/uploads/evil.php" 'each( $a );'
		php_file "$wc/cache/c.php" 'each( $a );'
		php_file "$wc/upgrade/u.php" 'each( $a );'
		php_file "$wc/node_modules/n.php" 'each( $a );'
	else
		mkdir -p "$wc/uploads/2026/11" "$wc/cache/page" "$wc/upgrade" "$wc/node_modules/pkg"
		printf 'GIF89a\0\0' > "$wc/uploads/2026/11/a.gif"
		printf '<html></html>\n' > "$wc/cache/page/index.html"
		printf 'module.exports = 1;\n' > "$wc/node_modules/pkg/index.js"
	fi
	# languages/ is scanned: WordPress 6.5+ includes its .l10n.php files.
	php_file "$wc/languages/de_DE.l10n.php" "return [ 'messages' => [ 'a' => 'b' ] ];
$bad"

	# Branch layout: wp-content/main is a second content root; the top-level skips apply only to wp-content itself.
	php_file "$wc/main/plugins/branchy/branchy.php" "/**
 * Plugin Name: Branchy
 * Version: 0.1
 */
$bad"
	php_file "$wc/main/uploads/evil.php" "$bad"
	# Not skipped by name in a branch: a link that dangles or leaves the mount is unreadable.
	if [ "$errors" = 1 ]; then
		ln -s /mnt/shared/upgrade "$wc/main/upgrade"
		ln -s ../../../../../../elsewhere/cache "$wc/main/cache"
	fi
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
	mkdir -p "$h/assets/node_modules/pkg" && printf 'module.exports = 1;\n' > "$h/assets/node_modules/pkg/index.js"
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

# wpscope_fixture <app-dir>: WordPress at htdocs with code outside wp-content. Everything but core is scanned:
# links into the WordPress directory, custom endpoints, a second app, a content dir beside wp-content, a subdirectory install.
wpscope_fixture() {
	local h="$1/htdocs" wc="$1/htdocs/wp-content"
	# Core, here and in a subdirectory install: never scanned.
	php_file "$h/wp-settings.php" 'each( $a );'
	php_file "$h/wp-includes/version.php" 'each( $a );'
	php_file "$h/wp-admin/admin.php" 'each( $a );'
	php_file "$h/index.php" 'each( $a );'
	php_file "$h/xmlrpc.php" 'each( $a );'
	php_file "$h/wp/wp-settings.php" 'each( $a );'
	php_file "$h/wp/wp-includes/load.php" 'each( $a );'
	php_file "$h/wp/wp-load.php" 'each( $a );'
	php_file "$h/wp/wp-content/plugins/stock/stock.php" 'each( $a );'
	# Code that isn't core: a custom endpoint and a second app.
	php_file "$h/custom-api.php" 'each( $a );'
	php_file "$h/forum/index.php" 'each( $a );'
	# A plugin, a theme and an mu-plugin linked from elsewhere in the WordPress directory keep their component.
	php_file "$h/shared/plug-in/plug-in.php" "/* Plugin Name: Plug In */
each( \$a );"
	mkdir -p "$h/shared/theme-in"
	printf '/*\nTheme Name: Theme In\n*/\n' > "$h/shared/theme-in/style.css"
	php_file "$h/shared/theme-in/functions.php" 'each( $a );'
	php_file "$h/shared/mu-link.php" 'each( $a );'
	php_file "$h/shared/loose.php" 'each( $a );'
	php_file "$h/vendor/acme/plug-v/plug-v.php" "/* Plugin Name: Plug V */
each( \$a );"
	mkdir -p "$wc/plugins" "$wc/themes" "$wc/mu-plugins"
	ln -s ../../shared/plug-in "$wc/plugins/plug-in"
	ln -s ../../vendor/acme/plug-v "$wc/plugins/plug-v"
	ln -s ../../shared/theme-in "$wc/themes/theme-in"
	ln -s ../../shared/mu-link.php "$wc/mu-plugins/mu-link.php"
	# Links to core stay out.
	ln -s ../wp-includes "$wc/inc"
	ln -s ../wp/wp-load.php "$wc/load.php"
	ln -s ../wp-includes/version.php "$wc/core-version.php"
	ln -s ../../wp/wp-includes "$wc/mu-plugins/inc"
	# A version.php outside core is code.
	php_file "$h/forum/inc/version.php" 'each( $a );'
	# A content dir beside wp-content (moved WP_CONTENT_DIR): a branch root with its own top-level skips.
	php_file "$h/content/plugins/moved/moved.php" "/* Plugin Name: Moved */
each( \$a );"
	php_file "$h/content/uploads/up.php" 'each( $a );'
	php_file "$h/content/object-cache.php" 'each( $a );'
	chmod -R a+rX "$1"
}

# wpmoved_fixture <app-dir>: no wp-content; WP_CONTENT_DIR is htdocs/app.
wpmoved_fixture() {
	local h="$1/htdocs"
	php_file "$h/wp-settings.php" 'each( $a );'
	mkdir -p "$h/wp-includes"
	php_file "$h/app/plugins/p/p.php" "/* Plugin Name: P */
each( \$a );"
	php_file "$1/wp-config.php" "define( 'WP_CONTENT_DIR', __DIR__ . '/htdocs/app' );"
	chmod -R a+rX "$1"
}

# badlink_fixture <app-dir> <wp|php> <target>: wp-content (wp) or htdocs (php) is a link that dangles or leaves the mount.
badlink_fixture() {
	local app=$1 type=$2 target=$3
	mkdir -p "$app/htdocs"
	if [ "$type" = wp ]; then
		php_file "$app/htdocs/wp-settings.php"
		mkdir -p "$app/htdocs/wp-includes"
		ln -s "$target" "$app/htdocs/wp-content"
	else
		rmdir "$app/htdocs"
		ln -s "$target" "$app/htdocs"
	fi
	chmod -R a+rX "$app"
}

# phpbeside_fixture <app-dir>: a php site whose htdocs links to app/public, with the app's code beside it in /var/www.
phpbeside_fixture() {
	local a=$1
	php_file "$a/app/public/index.php" 'require "../src/boot.php";'
	php_file "$a/app/src/boot.php" 'each( $a );'
	php_file "$a/lib.php" '$h = create_function( "", "" );'
	# The www-data user's home: tool caches, not site code.
	php_file "$a/.composer/vendor/x/y.php" 'each( $a );'
	php_file "$a/.wp-cli/packages/z.php" 'each( $a );'
	ln -s app/public "$a/htdocs"
	chmod -R a+rX "$a"
}

# bedrock_fixture <app-dir>: Bedrock in htdocs (config/ and vendor/ beside web/, content in web/app, core in web/wp).
bedrock_fixture() {
	local h="$1/htdocs"
	php_file "$h/config/application.php" "Config::define( 'WP_CONTENT_DIR', \$webroot_dir . '/app' );
each( \$a );"
	php_file "$h/vendor/acme/lib/Lib.php" 'each( $a );'
	php_file "$h/web/index.php" "require __DIR__ . '/wp/wp-blog-header.php';"
	php_file "$h/web/wp-config.php" "require dirname( __DIR__ ) . '/config/application.php';"
	php_file "$h/web/app/plugins/p/p.php" "/* Plugin Name: P */
each( \$a );"
	php_file "$h/web/app/mu-plugins/m.php" 'each( $a );'
	php_file "$h/web/app/uploads/u.php" 'each( $a );'
	php_file "$h/web/wp/wp-settings.php" 'each( $a );'
	php_file "$h/web/wp/wp-load.php" 'each( $a );'
	php_file "$h/web/wp/wp-includes/x.php" 'each( $a );'
	php_file "$h/web/wp/wp-admin/y.php" 'each( $a );'
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

# tempbackup_fixture <app-dir>: a clean plugin beside WordPress' rollback copies in wp-content/upgrade-temp-backup/.
tempbackup_fixture() {
	local wc="$1/htdocs/wp-content"
	php_file "$wc/plugins/p/p.php" '/* Plugin Name: P */'
	php_file "$wc/upgrade-temp-backup/plugins/old/old.php" '/* Plugin Name: Old */
each( $a );'
	php_file "$wc/upgrade-temp-backup/themes/oldt/functions.php" 'each( $a );'
	chmod -R a+rX "$1"
}

# phpdeep_fixture <app-dir>: htdocs links two levels into the app beside it (project/app/public).
phpdeep_fixture() {
	local a=$1
	php_file "$a/project/app/public/index.php" 'require "../src/boot.php";'
	php_file "$a/project/app/src/boot.php" 'each( $a );'
	php_file "$a/project/lib/x.php" 'each( $a );'
	ln -s project/app/public "$a/htdocs"
	chmod -R a+rX "$a"
}

# wflogs <dir>: Wordfence 9.1.1's WAF files (tests/wflogs, written by its own code with tests/wflogs-gen.php: data files that
# start `<?php exit('Access denied'); __halt_compiler(); ?>`, and a compiled rules.php), plus the template.php it writes.
wflogs() {
	mkdir -p "$1"
	cp "$HERE"/wflogs/*.php "$1/"
	printf "<?php exit('Access denied'); __halt_compiler(); ?>\n" > "$1/template.php"
}

# skipdirs_fixture <app-dir>: code in every directory the scanner skips by name; its code files are checked, not walked whole.
skipdirs_fixture() {
	local h="$1/htdocs" wc="$1/htdocs/wp-content"
	php_file "$h/wp-settings.php"
	mkdir -p "$h/wp-includes"
	php_file "$wc/plugins/p/p.php" '/* Plugin Name: P */'
	php_file "$wc/plugins/p/node_modules/pkg/x.php" 'each( $a );'
	php_file "$wc/plugins/p/.git/y.php" 'each( $a );'
	# No code in it: silent, unless the search budget is gone.
	mkdir -p "$wc/plugins/q/node_modules/pkg" && printf 'module.exports = 1;\n' > "$wc/plugins/q/node_modules/pkg/index.js"
	wflogs "$wc/uploads/wflogs"
	php_file "$wc/uploads/2026/11/deep/shell.PHP" 'each( $a );'
	printf 'GIF89a\0\0<?php each( $a );' > "$wc/uploads/2026/11/a.gif"
	printf '<?php each( $a );' > "$wc/uploads/2026/11/not-sniffed.txt"
	# Links out of scope inside a skipped dir are ignored there too: the WordPress dir and an ancestor.
	ln -s ../../.. "$wc/uploads/2026/up"
	ln -s /var/www "$wc/uploads/2026/www"
	php_file "$wc/cache/object/c.php" 'each( $a );'
	mkdir -p "$wc/upgrade" && printf '<?php __HALT_COMPILER();' > "$wc/upgrade/pkg.phar"
	php_file "$wc/upgrade-temp-backup/plugins/old/old.php" '/* Plugin Name: Old */'
	php_file "$wc/node_modules/n.php" 'each( $a );'
	php_file "$wc/.git/hooks/h.php" 'each( $a );'
	php_file "$h/node_modules/x.php" 'each( $a );'
	# A skipped name that dangles can't be searched.
	ln -s /var/www/nowhere "$h/.git"
	chmod -R a+rX "$1"
}

# wordfence_fixture <app-dir>: a clean site with Wordfence's WAF data in wflogs/ (both places it has used).
wordfence_fixture() {
	local wc="$1/htdocs/wp-content"
	php_file "$1/htdocs/wp-settings.php"
	mkdir -p "$1/htdocs/wp-includes"
	php_file "$wc/plugins/p/p.php" '/* Plugin Name: P */'
	wflogs "$wc/uploads/wflogs"
	wflogs "$wc/wflogs"
	printf 'GIF89a\0\0' > "$wc/uploads/a.gif"
	chmod -R a+rX "$1"
}

# contentlike_fixture <app-dir>: a directory holding themes/ is a content root, but only wp-content has the top-level skips.
contentlike_fixture() {
	local h="$1/htdocs"
	php_file "$h/wp-settings.php"
	mkdir -p "$h/wp-includes" "$h/tools/themes"
	php_file "$h/tools/cache/shell.php" 'each( $a );'
	php_file "$h/wp-content/main/plugins/b/b.php" '/* Plugin Name: B */'
	php_file "$h/wp-content/main/uploads/u.php" 'each( $a );'
	chmod -R a+rX "$1"
}

# pluginnm_fixture <app-dir>: a plugin dir and a theme dir named node_modules or .git are scanned like any other.
pluginnm_fixture() {
	local wc="$1/htdocs/wp-content"
	php_file "$wc/plugins/node_modules/evil.php" '/* Plugin Name: Evil */
each( $a );'
	php_file "$wc/plugins/.git/g.php" 'each( $a );'
	mkdir -p "$wc/themes/node_modules"
	printf '/*\nTheme Name: NM\n*/\n' > "$wc/themes/node_modules/style.css"
	php_file "$wc/themes/node_modules/functions.php" 'each( $a );'
	chmod -R a+rX "$1"
}

# l10n_fixture <app-dir>: WordPress 6.5+ translation files in wp-content/languages are PHP.
l10n_fixture() {
	local wc="$1/htdocs/wp-content"
	php_file "$wc/languages/de_DE.l10n.php" "return [ 'messages' => [ 'a' => 'b' ] ];"
	php_file "$wc/languages/plugins/x-de_DE.l10n.php" 'each( $a );
return [];'
	printf 'msgid ""\n' > "$wc/languages/de_DE.po"
	chmod -R a+rX "$1"
}

# sniff_fixture <app-dir>: PHP in files without a code extension, a phar, and non-PHP files.
sniff_fixture() {
	local p="$1/htdocs/wp-content/plugins/p"
	php_file "$p/p.php" '/* Plugin Name: P */'
	php_file "$p/views/admin.tpl" 'each( $a );'
	mkdir -p "$p/bin" && printf '#!/usr/bin/env php\n<?php\neach( $a );\n' > "$p/bin/tool"
	printf '\xef\xbb\xbf<?= each( $a ); ?>\n' > "$p/views/bom.html"
	printf '<div>\n<?php each( $a ); ?>\n</div>\n' > "$p/views/page.html"
	printf '<p>\n<?php $x = utf8_encode( "a" ); ?>\n' > "$p/views/warn.html"
	# Never templates: docs, scripts, styles and data aren't sniffed, whatever they quote.
	for f in README.md notes.txt app.js app.ts style.css data.json; do printf 'x <?php each( $a ); ?>\n' > "$p/$f"; done
	{ printf '<p>\n'; head -c 1100000 /dev/zero | tr '\0' a; printf '\n'; } > "$p/big.txt"
	{ printf 'x <?php echo 1; ?>\n'; head -c 1100000 /dev/zero | tr '\0' a; } > "$p/big-mixed.tpl"
	printf '\x89PNG\r\n\x1a\n\0\0\0\r<?php each( $a );' > "$p/logo.png"
	printf '{"a": "<?xml version=1.0?>"}\n' > "$p/data.json"
	printf '<?php __HALT_COMPILER();' > "$p/lib.phar"
	printf 'x' > "$p/lib.phar.tar.gz"
	ln -s lib.phar "$p/a-lib.php"
	printf '<p>\n<?php each( $a ); ?>\n' > "$p/tpl.php"
	ln -s tpl.php "$p/a-tpl.txt"
	ln -s nowhere.phar "$p/gone.phar"
	chmod -R a+rX "$1"
}

# nested_fixture <app-dir>: another WordPress install below the root (and inside a plugin): its core isn't skipped silently.
nested_fixture() {
	local h="$1/htdocs" wc="$1/htdocs/wp-content"
	php_file "$h/wp-settings.php" 'each( $a );'
	php_file "$h/wp-includes/load.php" 'each( $a );'
	php_file "$h/index.php" 'each( $a );'
	# The root's own files with other names are code.
	php_file "$h/wp-custom.php" 'each( $a );'
	php_file "$h/old/wp-settings.php" 'each( $a );'
	php_file "$h/old/wp-includes/x.php" 'each( $a );'
	php_file "$h/old/index.php" 'each( $a );'
	php_file "$h/old/xmlrpc.php" 'each( $a );'
	php_file "$h/old/custom.php" 'each( $a );'
	php_file "$wc/plugins/fakecore/index.php" '/* Plugin Name: Fake Core */
each( $a );'
	php_file "$wc/plugins/fakecore/wp-settings.php" 'each( $a );'
	mkdir -p "$wc/plugins/fakecore/wp-includes"
	ln -s ../old/wp-includes "$wc/inc"
	chmod -R a+rX "$1"
}

# hang_fixture <app-dir>: sniffed templates whose PHPCS run is cut by COMPAT_SNIFFED_TIMEOUT: a slow one, and one that
# hangs PHPCompatibility 10.0.0-alpha3 (from CodeMirror's mode/php/test.js, MIT; PHPCS reads `<?php]` as a short tag).
hang_fixture() {
	local p="$1/htdocs/wp-content/plugins/p"
	php_file "$p/p.php" '/* Plugin Name: P */'
	mkdir -p "$p/views"
	# Deterministic: plain PHP under a template name that takes PHPCS far longer than the 1 s cap the test sets.
	{ printf '<?php\n'; for i in $(seq 1 40000); do printf '$a%d = array( 1, 2, 3 ) + [ %d ];\n' "$i" "$i"; done; } > "$p/views/slow.tpl"
	cat > "$p/views/hang.tpl" <<'TPL'
<p>
<?php ?>
     '[meta <?php] [comment /* Escaping */]',
     '[keyword echo] [string "aaa\\$aaaa->aaa.aaa"];',
     '[keyword echo] [string "aaa\\$aaaa[[2]]aaa.aaa"];',
     '[keyword echo] [string "aaa\\$aaaa[[asd]]aaa.aaa"];',
     '[keyword echo] [string "aaa{\\$aaaa->aaa.aaa"];',
     '[keyword echo] [string "aaa{\\$aaaa[[2]]aaa.aaa"];',
     '[keyword echo] [string "aaa{\\aaaaa[[asd]]aaa.aaa"];',
     '[keyword echo] [string "aaa\\${aaaa->aaa.aaa"];',
TPL
	chmod -R a+rX "$1"
}

# cache_fixture <app-dir> <n>: <n> W3TC disk cache files (`<?php exit; ?>` + expiry + data), WP Super Cache legacy pages
# (`<?php die(); ?>` + HTML), Docket Cache files (real `return` code, checked) and a header followed by another open tag.
cache_fixture() {
	local wc="$1/htdocs/wp-content" n=$2 d
	php_file "$1/htdocs/wp-settings.php"
	mkdir -p "$1/htdocs/wp-includes"
	php_file "$wc/plugins/p/p.php" '/* Plugin Name: P */'
	for d in $(seq 0 $(( (n - 1) / 1000 ))); do
		mkdir -p "$wc/cache/object/$d"
		seq $(( d * 1000 + 1 )) $(( d * 1000 + 1000 < n ? d * 1000 + 1000 : n )) | sed "s|^|$wc/cache/object/$d/|; s|\$|.php|" |
			xargs -n 500 sh -c 'for f; do printf "<?php exit; ?>1795600000a:1:{s:3:\"key\";s:5:\"value\";}" > "$f"; done' sh
	done
	mkdir -p "$wc/cache/supercache" "$wc/cache/docket-cache"
	printf '<?php die(); ?><!DOCTYPE html><html><body>cached page</body></html>' > "$wc/cache/wp-cache-1a2b.php"
	printf "<?php exit('Access denied'); ?>\\n<html></html>" > "$wc/cache/supercache/page.php"
	printf "<?php if(!\\\\defined('ABSPATH')){return false;}\\nreturn array('key'=>'k','group'=>'options','data'=>array('a'=>1));\\n/*@DOCKET_CACHE_EOF*/" > "$wc/cache/docket-cache/0a1b2c.php"
	printf '<?php exit; ?>data\\n<?php each( $a );\\n' > "$wc/cache/object/tail.php"
	# Too large to read to the end: scanned like other code, not counted as data.
	{ printf '<?php exit; ?>'; head -c 9000000 /dev/zero | tr '\0' a; } > "$wc/cache/object/huge.php"
	chmod -R a+rX "$1"
}

# stdin_fixture <app-dir>: files PHPCS reads through STDIN (a non-lowercase code extension, a newline in the name, a
# sniffed file) whose first line starts with `phpcs_input_file:`, which PHPCS's STDIN reader would take as a file name and
# drop; names that differ only in control characters on record()'s not_checked route; a skipped dir under a non-UTF-8 name.
stdin_fixture() {
	local p="$1/htdocs/wp-content/plugins/s" l1="phpcs_input_file: <?php \$f = create_function( '', '' );"
	php_file "$p/s.php" '/* Plugin Name: S */'
	printf '%s\neach( $a );\n' "$l1" > "$p/X.PHP"
	printf '%s\r\neach( $a );\r\n' "$l1" > "$p/crlf.PHP"
	printf '%s\reach( $a );\r' "$l1" > "$p/cr.PHP"
	printf '%s\neach( $a );\n' "$l1" > "$p/new"$'\n'"line.php"
	: > "$p/empty.PHP"
	mkdir -p "$p/bin" && printf '%s\n' "$l1" > "$p/bin/tool"
	printf '<p>\n<?php each( $a ); ?>\n' > "$p/t"$'\x01'".tpl"
	printf '<p>\n<?php each( $a ); ?>\n' > "$p/t"$'\x02'".tpl"
	php_file "$1/htdocs/wp-content/plugins/"$'\xff'"/node_modules/x/tool" 'each( $a );'
	chmod -R a+rX "$1"
}

# phpdot_fixture <app-dir> <beside|root>: a php site whose public dir is in a dot entry of /var/www (beside: htdocs ->
# .release/public, code in .release/lib; root: htdocs -> .release), beside the www-data home's tool caches.
phpdot_fixture() {
	local a=$1
	if [ "$2" = beside ]; then
		php_file "$a/.release/public/index.php" 'require "../lib/helper.php";'
		php_file "$a/.release/lib/helper.php" '$f = create_function( "", "" );'
		ln -s .release/public "$a/htdocs"
		# Code in the home: WP-CLI packages, a script without a code extension, a dot file.
		php_file "$a/.wp-cli/packages/vendor/v/v.php" 'each( $a );'
		php_file "$a/.composer/vendor/bin/tool" 'each( $a );'
		php_file "$a/.user.php" 'each( $a );'
	else
		php_file "$a/.release/index.php" 'echo 1;'
		ln -s .release "$a/htdocs"
	fi
	# No code: caches, history, docs and binaries that quote a tag.
	mkdir -p "$a/.composer/cache/files/x" "$a/.wp-cli/cache/core" "$a/.cache" "$a/.npm/_cacache"
	printf 'PK\3\4<?php ' > "$a/.composer/cache/files/x/a.zip"
	printf 'x' > "$a/.wp-cli/cache/core/wordpress-7.1.4-en_US.tar.gz"
	printf '{"a": "<?php"}' > "$a/.cache/x.json"
	printf '\0<?php each( $a );' > "$a/.npm/_cacache/0123abcd"
	printf 'x <?php each( $a ); ?>\n' > "$a/.cache/notes.md"
	printf 'ls\n' > "$a/.bash_history"
	chmod -R a+rX "$a"
}

# untraversable_fixture <app-dir>: directories uid 33 can list but not search (r without x), in a plugin and in uploads/.
untraversable_fixture() {
	local wc="$1/htdocs/wp-content"
	php_file "$wc/plugins/lk/lk.php" '/* Plugin Name: LK */'
	php_file "$wc/plugins/lk/locked/c.php" 'each( $a );'
	php_file "$wc/plugins/lk/locked/sub/a.php" 'each( $a );'
	php_file "$wc/plugins/lk/locked/lib.v2/b.php" 'each( $a );'
	php_file "$wc/uploads/locked/sub/d.php" 'each( $a );'
	php_file "$wc/uploads/locked/lib.v2/e.php" 'each( $a );'
	chmod -R a+rX "$1"
	chmod 0744 "$wc/plugins/lk/locked" "$wc/uploads/locked"
}

# pharflood_fixture <app-dir> <n>: n empty .phar files under long names: not_checked entries without a PHPCS run.
pharflood_fixture() {
	local d="$1/htdocs/wp-content/plugins/p/$(printf 'd%.0s' $(seq 1 200))"
	php_file "$1/htdocs/wp-content/plugins/p/p.php" '/* Plugin Name: P */'
	mkdir -p "$d"
	(cd "$d" && seq -f "f%06g-$(printf 'n%.0s' $(seq 1 100)).phar" 1 "$2" | xargs touch)
	chmod -R a+rX "$1"
}
