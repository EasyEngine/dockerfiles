<?php
// Checks the outputs run.sh collected in <dir>. Runs inside the scanner image.

$dir   = $argv[1];
$fails = 0;
$count = 0;

function check( bool $ok, string $what ) {
	global $fails, $count;
	$count++;
	if ( ! $ok ) {
		$fails++;
	}
	echo( $ok ? 'ok   ' : 'FAIL ' ), $what, "\n";
}

function out( string $name ): array {
	global $dir;
	$raw = (string) @file_get_contents( "$dir/$name.stdout" );
	check( 1 === substr_count( $raw, "\n" ) && "\n" === substr( $raw, -1 ), "$name: stdout is one line" );
	$doc = json_decode( $raw, true );
	check( is_array( $doc ), "$name: stdout is a JSON object" );
	return is_array( $doc ) ? $doc : [];
}

function report( string $name ): array {
	global $dir;
	$doc = json_decode( (string) @file_get_contents( "$dir/$name.report.json" ), true );
	check( is_array( $doc ), "$name: report.json is a JSON object" );
	return is_array( $doc ) ? $doc : [];
}

function rc( string $name ): int {
	global $dir;
	return (int) trim( (string) @file_get_contents( "$dir/$name.rc" ) );
}

function eq( $actual, $expected, string $what ) {
	$ok = $actual === $expected;
	check( $ok, $what . ( $ok ? '' : ' (got ' . json_encode( $actual ) . ', want ' . json_encode( $expected ) . ')' ) );
}

function comp_rows( array $report ): array {
	$rows = [];
	foreach ( $report['components'] ?? [] as $c ) {
		$rows[] = [ $c['type'], $c['slug'], $c['branch'], $c['name'], $c['version'], $c['files'], $c['errors'], $c['warnings'] ];
	}
	return $rows;
}

/** The value, or 'missing' when the key is absent (?? can't tell null from absent). */
function field( array $doc, string $key ) {
	return array_key_exists( $key, $doc ) ? $doc[ $key ] : 'missing';
}

/** The component with this type, slug and branch, or []. */
function comp_of( array $report, string $type, string $slug, ?string $branch = null ): array {
	foreach ( $report['components'] ?? [] as $c ) {
		if ( $c['type'] === $type && $c['slug'] === $slug && $c['branch'] === $branch ) {
			return $c;
		}
	}
	return [];
}

function raw( string $name ): string {
	global $dir;
	return (string) @file_get_contents( "$dir/$name" );
}

/** A tool_error run: one JSON line, the detail, the exit code, and report.json equal to stdout. */
function tool_error( string $name, string $detail_prefix, int $code, bool $report = true ): array {
	$doc = out( $name );
	eq( rc( $name ), $code, "$name: exit $code" );
	eq( [ $doc['status'] ?? null, field( $doc, 'safe_to_upgrade' ) ], [ 'tool_error', null ], "$name: tool_error, no verdict" );
	check( 0 === strpos( $doc['detail'] ?? '', $detail_prefix ), "$name: detail starts with '$detail_prefix' (" . ( $doc['detail'] ?? '' ) . ')' );
	if ( $report ) {
		eq( report( $name ), $doc, "$name: report.json equals stdout" );
		eq( trim( raw( "$name.outdir" ) ), './report.json', "$name: /out holds only report.json" );
	}
	return $doc;
}

function summary_of( array $report ): array {
	unset( $report['components'], $report['not_checked'] );
	return $report;
}

function without_duration( array $doc ): array {
	unset( $doc['duration_s'] );
	return $doc;
}

// ----------------------------------------------------------------- full tree

$full = out( 'full' );
$rep  = report( 'full' );
eq( rc( 'full' ), 0, 'full: exit 0' );
eq( $full['status'] ?? null, 'ok', 'full: status ok' );
eq( field( $full, 'safe_to_upgrade' ), false, 'full: safe_to_upgrade false' );
eq( array_keys( $full ), [ 'v', 'status', 'site', 'target', 'safe_to_upgrade', 'errors', 'warnings', 'files_checked', 'files_not_checked', 'php_bytes', 'components_checked', 'components_with_errors', 'duration_s', 'tool' ], 'full: summary keys and order' );
eq( [ $full['v'], $full['site'], $full['target'] ], [ 1, 'fixture.test', '8.4' ], 'full: v, site, target' );
eq( [ $full['errors'], $full['warnings'], $full['files_checked'], $full['files_not_checked'], $full['components_checked'], $full['components_with_errors'] ], [ 1124, 3, 40, 2, 22, 16 ], 'full: counts' );
check( $full['php_bytes'] > 0 && is_int( $full['duration_s'] ), 'full: php_bytes and duration_s' );
eq( array_keys( $full['tool'] ), [ 'phpcs', 'phpcompatibility', 'phpcompatibility_wp', 'image' ], 'full: tool keys' );
check( 0 === strpos( $full['tool']['phpcs'], '4.0.' ) && '10.0.0-alpha3' === $full['tool']['phpcompatibility'] && '3.0.0-alpha3' === $full['tool']['phpcompatibility_wp'], 'full: tool versions' );
eq( summary_of( $rep ), $full, 'full: report summary equals stdout' );

eq(
	comp_rows( $rep ),
	[
		[ 'plugin', 'many', null, 'Many', null, 1, 1100, 0 ],
		[ 'plugin', 'annotated', null, 'Annotated', null, 5, 5, 0 ],
		[ 'plugin', 'order', null, 'Order', null, 3, 3, 0 ],
		[ 'plugin', 'cachey', null, 'Cachey', null, 4, 2, 0 ],
		[ 'plugin', 'hello.php', null, 'Hello Single', '0.9', 1, 2, 0 ],
		[ 'plugin', 'legacy', null, 'Legacy Plugin', '1.2.3', 2, 2, 0 ],
		[ 'plugin', 'broken', null, 'Broken', null, 1, 1, 0 ],
		[ 'plugin', 'bundled', null, 'Bundled', null, 2, 1, 0 ],
		[ 'plugin', 'ctl', null, "Ctl\u{FFFD}evil\u{FFFD}2J\u{FFFD}", null, 2, 1, 0 ],
		[ 'plugin', 'hardlink', null, 'Hardlink', null, 1, 1, 0 ],
		[ 'plugin', 'incl', null, 'Incl', null, 2, 1, 0 ],
		[ 'plugin', 'utf', null, 'Utf', null, 2, 1, 0 ],
		[ 'plugin', 'branchy', 'main', 'Branchy', '0.1', 1, 1, 0 ],
		[ 'theme', 'demo', null, 'Demo Theme', '2.1', 1, 1, 0 ],
		[ 'other', '', null, null, null, 4, 1, 0 ],
		[ 'other', 'wp-config.php', null, null, null, 1, 1, 0 ],
		[ 'plugin', 'warnonly', null, 'Warn Only', '3.0', 1, 0, 2 ],
		[ 'mu-plugin', 'mu-plugins', null, null, null, 2, 0, 1 ],
		[ 'plugin', 'clean', null, 'Clean Plugin', null, 1, 0, 0 ],
		[ 'plugin', 'loop', null, 'Loop', null, 1, 0, 0 ],
		[ 'theme', 'fifo', null, 'fifo', null, 1, 0, 0 ],
		[ 'other', '', 'main', null, null, 1, 0, 0 ],
	],
	'full: components, grouping, names, versions, branches, order'
);

$total = 0;
$files = [];
foreach ( $rep['components'] ?? [] as $c ) {
	$n = count( $c['findings'] );
	$total += $n;
	check( $n === $c['errors'] + $c['warnings'], "full: {$c['slug']}/{$c['branch']} lists every finding ($n)" );
	$sorted = $c['findings'];
	usort(
		$sorted,
		static function ( $a, $b ) {
			return [ 'ERROR' === $a['type'] ? 0 : 1, $a['file'], $a['line'] ] <=> [ 'ERROR' === $b['type'] ? 0 : 1, $b['file'], $b['line'] ];
		}
	);
	check( array_map( 'json_encode', $sorted ) === array_map( 'json_encode', $c['findings'] ), "full: {$c['slug']}/{$c['branch']} findings ordered" );
	if ( $c['findings'] ) {
		eq( array_keys( $c['findings'][0] ), [ 'file', 'line', 'type', 'source', 'message' ], 'full: finding keys' );
	}
	foreach ( $c['findings'] as $f ) {
		$files[ $c['type'] . ':' . $c['slug'] . ':' . $c['branch'] . ':' . $f['file'] ] = true;
	}
}
eq( $total, 1127, 'full: report has every finding (>1,000, uncapped)' );
eq( count( $rep['components'][0]['findings'] ?? [] ), 1100, 'full: 1,100 findings of one component all listed' );

ksort( $files );
$expect_files = [
	'other:::lib/helper.php',
	'other:wp-config.php::htdocs/wp-config.php',
	'plugin:annotated::annotated.php',
	'plugin:annotated::disable.php',
	'plugin:annotated::inline.php',
	'plugin:annotated::late.php',
	'plugin:annotated::whole.php',
	'plugin:hardlink::h1.php',
	'plugin:incl::link.php',
	"plugin:order::a\u{FFFD}b.php",
	'plugin:order::b.php',
	'plugin:order::c.php',
	"plugin:ctl::x\u{FFFD}gpj\u{FFFD}[31m.php",
	'plugin:branchy:main:branchy.php',
	'plugin:broken::broken.php',
	'plugin:bundled::vendor/acme/lib/Old.php',
	'plugin:cachey::cache/c.php',
	'plugin:cachey::plugins/p.php',
	'plugin:hello.php::hello.php',
	'plugin:legacy::legacy.php',
	'plugin:many::many.php',
	"plugin:utf::bad\u{FFFD}\u{FFFD}name.php",
	'plugin:warnonly::warnonly.php',
	'mu-plugin:mu-plugins::sub/x.php',
	'theme:demo::functions.php',
];
sort( $expect_files );
eq( array_keys( $files ), $expect_files, 'full: findings per file (paths relative to the component; skips, core, links to core/ancestors and outside code absent; invalid UTF-8 and control characters substituted)' );

$legacy = comp_of( $rep, 'plugin', 'legacy' )['findings'] ?? [];
eq(
	array_map( static function ( $f ) { return $f['line'] . ' ' . $f['source']; }, $legacy ),
	[ '6 PHPCompatibility.FunctionUse.RemovedFunctions.create_functionDeprecatedRemoved', '7 PHPCompatibility.FunctionUse.RemovedFunctions.eachDeprecatedRemoved' ],
	'full: legacy findings'
);
eq( comp_of( $rep, 'plugin', 'broken' )['findings'][0]['source'] ?? '', 'PHPCompatibility.FunctionUse.RemovedFunctions.eachDeprecatedRemoved', 'full: syntax-error file still sniffed' );
eq( array_column( comp_of( $rep, 'plugin', 'annotated' )['findings'] ?? [], 'file' ), [ 'annotated.php', 'disable.php', 'inline.php', 'late.php', 'whole.php' ], 'full: annotations ignored (targeted phpcs:ignore, phpcs:ignoreFile on line 1 and line 6, blanket phpcs:disable, bare phpcs:ignore)' );
eq( array_column( comp_of( $rep, 'plugin', 'order' )['findings'] ?? [], 'file' ), [ "a\u{FFFD}b.php", 'b.php', 'c.php' ], 'full: findings in file order with a STDIN file first' );
eq( array_column( comp_of( $rep, 'plugin', 'incl' )['findings'] ?? [], 'file' ), [ 'link.php' ], 'full: .php link to a .inc file checked under the link name' );
eq( comp_of( $rep, 'plugin', 'hardlink' )['files'] ?? null, 1, 'full: hard-linked file counted once' );
eq( [ comp_of( $rep, 'plugin', 'index.php' ), comp_of( $rep, 'other', '' )['files'] ?? null ], [ [], 4 ], 'full: header-less plugins/index.php is in other, not a plugin' );
$raw = raw( 'full.report.json' );
check( false === strpos( $raw, "\u{202E}" ) && false === strpos( $raw, "\u{9B}" ) && false === strpos( $raw, "\x7f" ) && false === strpos( $raw, '\\u001b' ), 'full: no bidi, C1, DEL or escape characters in report.json' );

eq(
	$rep['not_checked'] ?? null,
	[
		[ 'type' => 'plugin', 'slug' => 'dangling', 'branch' => null, 'file' => 'dangling', 'reason' => 'unreadable' ],
		[ 'type' => 'plugin', 'slug' => 'locked', 'branch' => null, 'file' => './', 'reason' => 'unreadable' ],
	],
	'full: not_checked has the dangling link and the unlistable dir'
);
eq( trim( (string) file_get_contents( "$dir/full.outdir" ) ), './report.json', 'full: /out holds only report.json' );

// ---------------------------------------------------------- verdict variants

$clean = out( 'clean' );
eq( [ $clean['status'] ?? null, field( $clean, 'safe_to_upgrade' ), $clean['errors'] ?? null, $clean['warnings'] ?? null, $clean['files_not_checked'] ?? null ], [ 'ok', true, 0, 3, 0 ], 'clean: true with warnings only' );
eq( report( 'clean' )['not_checked'] ?? null, [], 'clean: not_checked empty' );

$null = out( 'null' );
eq( [ $null['status'] ?? null, field( $null, 'safe_to_upgrade' ), $null['errors'] ?? null, $null['files_not_checked'] ?? null ], [ 'ok', null, 0, 2 ], 'null: null when only unreadable entries' );

// ------------------------------------------------------------------ retries

foreach ( [ 'batchmem' => 'single-file step', 'filemem' => 'higher-memory retry' ] as $name => $what ) {
	$doc = out( $name );
	$r   = report( $name );
	eq( without_duration( $doc ), without_duration( $full ), "$name: summary equals the normal run ($what)" );
	eq( $r['components'] ?? null, $rep['components'] ?? [], "$name: findings equal the normal run" );
	eq( $r['not_checked'] ?? null, $rep['not_checked'] ?? [], "$name: not_checked equals the normal run" );
}

$all = out( 'allmem' );
$r   = report( 'allmem' );
eq( [ field( $all, 'safe_to_upgrade' ), $all['errors'] ?? null, $all['files_checked'] ?? null, $all['files_not_checked'] ?? null ], [ null, 0, 0, 42 ], 'allmem: nothing checked, verdict null' );
$reasons = array_count_values( array_column( $r['not_checked'] ?? [], 'reason' ) );
eq( $reasons, [ 'unreadable' => 2, 'memory' => 40 ], 'allmem: every file in not_checked with reason memory' );

$oom = out( 'oom' );
eq( field( $oom, 'safe_to_upgrade' ), null, 'oom: verdict null' );
eq( report( 'oom' )['not_checked'] ?? null, [ [ 'type' => 'plugin', 'slug' => 'big', 'branch' => null, 'file' => 'big.php', 'reason' => 'memory' ] ], 'oom: a kernel OOM kill is reason memory (' . trim( preg_replace( '/\s+/', ' ', raw( 'oom.stderr' ) ) ) . ')' );

// ------------------------------------------------------------------ timeout

$t = out( 'timeout' );
eq( rc( 'timeout' ), 1, 'timeout: exit 1' );
eq( array_keys( $t ), [ 'v', 'status', 'site', 'target', 'safe_to_upgrade', 'detail' ], 'timeout: reduced keys only, no counts' );
eq( [ $t['status'] ?? null, field( $t, 'safe_to_upgrade' ) ], [ 'tool_error', null ], 'timeout: tool_error, no verdict' );
check( (bool) preg_match( '#^timed out after 1 s at htdocs/current/wp-content/\S+\.php$#', $t['detail'] ?? '' ), 'timeout: detail names the file (' . ( $t['detail'] ?? '' ) . ')' );
eq( report( 'timeout' ), $t, 'timeout: report.json equals stdout, no not_checked' );

// ------------------------------------------------------- memory and size bounds

$flood = out( 'flood' );
eq( [ $flood['status'] ?? null, $flood['errors'] ?? null ], [ 'ok', 20000 ], 'flood: 20,000 findings with a 12M entrypoint' );
eq( count( comp_of( report( 'flood' ), 'plugin', 'flood' )['findings'] ?? [] ), 20000, 'flood: every finding in the report' );

$wide = out( 'wide-est' );
eq( [ $wide['status'] ?? null, $wide['php_files'] ?? null ], [ 'ok', 20000 ], 'wide-est: 20,000 files listed with an 8M entrypoint' );

$fatal = tool_error( 'fatal', 'internal error: Allowed memory size', 1 );
tool_error( 'flood-cap', 'report larger than 1024 bytes', 1 );
check( false !== strpos( raw( 'flood-cap.stderr' ), 'rc=25' ), 'flood-cap: PHPCS stopped at the file size limit (SIGXFSZ)' );
check( false !== strpos( raw( 'flood-cap.stderr' ), 'core limit 0' ), 'flood-cap: core dumps disabled' );
tool_error( 'full-cap', 'report larger than 100000 bytes', 1 );
tool_error( 'wide-cap', 'file list larger than 100000 bytes', 1 );
tool_error( 'fullout', 'could not write', 1, false );

// ------------------------------------------------------------- wp-config.php

foreach ( [ 'wpcfg-dir' => [ 'htdocs/wp-config.php', 'PHPCompatibility.FunctionUse.RemovedFunctions.create_functionDeprecatedRemoved' ], 'wpcfg-parent' => [ 'wp-config.php', 'PHPCompatibility.FunctionUse.RemovedFunctions.eachDeprecatedRemoved' ] ] as $name => list( $file, $source ) ) {
	$doc = out( $name );
	$c   = comp_of( report( $name ), 'other', 'wp-config.php' );
	eq( [ $doc['errors'] ?? null, $doc['files_checked'] ?? null ], [ 1, 2 ], "$name: only the loaded wp-config.php is scanned" );
	eq( [ $c['files'] ?? null, array_column( $c['findings'] ?? [], 'file' ), array_column( $c['findings'] ?? [], 'source' ) ], [ 1, [ $file ], [ $source ] ], "$name: component other/wp-config.php, file $file" );
}

// ------------------------------------------------------------ php releases

$pr = out( 'php-rel' );
eq( [ $pr['errors'] ?? null, $pr['files_checked'] ?? null ], [ 2, 5 ], 'php-rel: only the live release (and shared/, releases/ files) scanned' );
eq(
	comp_rows( report( 'php-rel' ) ),
	[
		[ 'directory', 'current', null, null, null, 2, 1, 0 ],
		[ 'directory', 'shared', null, null, null, 1, 1, 0 ],
		[ 'directory', 'releases', null, null, null, 1, 0, 0 ],
		[ 'other', '', null, null, null, 1, 0, 0 ],
	],
	'php-rel: components (old release 1 absent)'
);
$e = out( 'est-php-rel' );
eq( [ $e['php_files'] ?? null, $e['php_bytes'] ?? null, $e['components'] ?? null ], [ $pr['files_checked'] + $pr['files_not_checked'], $pr['php_bytes'] ?? null, $pr['components_checked'] ?? null ], 'est-php-rel: counts equal the scan' );
eq( [ out( 'php-rel-link' )['errors'] ?? null ], [ 3 ], 'php-rel-link: symlinked releases/ is not the layout, every release scanned' );

// --------------------------------------------------------------- php site

$php = out( 'php' );
$r   = report( 'php' );
eq( [ $php['status'] ?? null, field( $php, 'safe_to_upgrade' ), $php['errors'] ?? null, $php['warnings'] ?? null, $php['files_checked'] ?? null ], [ 'ok', false, 3, 1, 7 ], 'php: verdict and counts (root is htdocs, WordPress skips not applied)' );
eq(
	comp_rows( $r ),
	[
		[ 'directory', 'app', null, null, null, 2, 1, 1 ],
		[ 'directory', 'uploads', null, null, null, 1, 1, 0 ],
		[ 'directory', 'vendor', null, null, null, 1, 1, 0 ],
		[ 'directory', 'cache', null, null, null, 1, 0, 0 ],
		[ 'directory', 'public', null, null, null, 1, 0, 0 ],
		[ 'other', '', null, null, null, 1, 0, 0 ],
	],
	'php: directory components'
);

// ------------------------------------------------------------ other statuses

$nc = out( 'nocode' );
eq( $nc, [ 'v' => 1, 'status' => 'no_code_found', 'site' => 'fixture.test', 'target' => '8.4', 'safe_to_upgrade' => null ], 'nocode: no_code_found document' );
eq( report( 'nocode' ), $nc, 'nocode: report.json equals stdout' );

$bad = out( 'badargs' );
eq( rc( 'badargs' ), 2, 'badargs: exit 2' );
check( 'tool_error' === ( $bad['status'] ?? '' ) && 0 === strpos( $bad['detail'] ?? '', 'bad arguments: ' ), 'badargs: tool_error with detail' );

// ----------------------------------------------------------------- estimate

foreach ( [ 'est' => [ $full, 'full' ], 'est-php' => [ $php, 'php' ] ] as $name => list( $scan, $of ) ) {
	$e = out( $name );
	eq( array_keys( $e ), [ 'v', 'status', 'estimate', 'site', 'target', 'php_files', 'php_bytes', 'components', 'estimated_seconds', 'estimated_seconds_low', 'estimated_seconds_high', 'inputs' ], "$name: keys" );
	eq( [ $e['status'] ?? null, $e['estimate'] ?? null ], [ 'ok', true ], "$name: status ok" );
	eq(
		[ $e['php_files'] ?? null, $e['php_bytes'] ?? null, $e['components'] ?? null ],
		[ $scan['files_checked'] + $scan['files_not_checked'], $scan['php_bytes'], $scan['components_checked'] ],
		"$name: counts equal the $of scan"
	);
	$lo = $e['estimated_seconds_low'] ?? 0;
	$mid = $e['estimated_seconds'] ?? 0;
	$hi = $e['estimated_seconds_high'] ?? 0;
	check( $lo > 0 && $lo <= $mid && $mid <= $hi, "$name: times positive and ordered ($lo <= $mid <= $hi)" );
	$in = $e['inputs'] ?? [];
	check( ( $in['calibration_bytes'] ?? 0 ) > 500000 && ( $in['bytes_per_second'] ?? 0 ) > 0 && ( $in['cpus'] ?? 0 ) == 1 && isset( $in['load_average_1m'], $in['batches'], $in['seconds_per_batch'], $in['low_factor'], $in['high_factor'] ), "$name: inputs" );
}
tool_error( 'est-timeout', 'timed out after 1 s', 1, false );
tool_error( 'badver', 'bad arguments: version must look like 8.4', 2, false );
eq( out( 'est-nocode' ), [ 'v' => 1, 'status' => 'no_code_found', 'estimate' => true, 'site' => 'fixture.test', 'target' => '8.4', 'safe_to_upgrade' => null ], 'est-nocode: no_code_found' );
eq( trim( (string) file_get_contents( "$dir/tree" ) ), 'unchanged', 'fixture tree unchanged by scans and estimates' );
eq( trim( (string) file_get_contents( "$dir/mount" ) ), 'readonly', 'code mount is read-only inside the container' );

echo "\n", $count - $fails, '/', $count, " checks passed\n";
exit( $fails ? 1 : 0 );
