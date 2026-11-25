<?php
// Checks a scan's /out/manifest.json against the fixture it scanned, mounted at /var/www as for the scan.
// Every code file under the manifest's roots, by the manifest's own rules (code_extensions, phar_regex, sniff), must be
// checked (same inode) or under not_checked, unless it is the scanned root's core, an old release or excluded.
// Usage: php manifest-check.php <manifest.json>   Prints one JSON object: counts and problems.

$m        = json_decode( (string) file_get_contents( $argv[1] ), true );
$problems = [];
$out      = static function () use ( &$problems, &$m, &$codeFiles ) {
	echo json_encode(
		[
			'checked'     => count( $m['checked'] ?? [] ),
			'not_checked' => count( $m['not_checked'] ?? [] ),
			'code_files'  => $codeFiles ?? 0,
			'problems'    => array_slice( $problems, 0, 50 ),
		],
		JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE
	), "\n";
};
$keys = [ 'v', 'code_extensions', 'extensions_case_insensitive', 'phar_regex', 'sniff', 'roots', 'excluded', 'old_releases', 'core', 'checked', 'not_checked' ];
if ( ! is_array( $m ) || array_keys( $m ) !== $keys ) {
	$problems[] = 'manifest keys: ' . json_encode( is_array( $m ) ? array_keys( $m ) : null );
	$out();
	exit;
}

// A path that isn't UTF-8 is listed as `b64:` + base64 of its bytes.
foreach ( [ 'checked', 'not_checked' ] as $list ) {
	foreach ( $m[ $list ] as $i => $p ) {
		if ( 0 === strpos( $p, 'b64:' ) ) {
			$m[ $list ][ $i ] = base64_decode( substr( $p, 4 ), true );
		}
	}
}

$under = static function ( string $path, array $dirs ): bool {
	foreach ( $dirs as $d ) {
		if ( 0 === strpos( $path, $d ) ) {
			return true;
		}
	}
	return false;
};

// checked: unique real paths of regular files under /var/www.
$inodes = [];
if ( count( $m['checked'] ) !== count( array_unique( $m['checked'] ) ) ) {
	$problems[] = 'checked has duplicates';
}
foreach ( $m['checked'] as $p ) {
	$st = @lstat( $p );
	if ( 0 !== strpos( $p, '/var/www/' ) || false === $st || 0100000 !== ( $st['mode'] & 0170000 ) || realpath( $p ) !== $p ) {
		$problems[] = "checked entry not a real regular file: $p";
		continue;
	}
	$inodes[ $st['dev'] . ':' . $st['ino'] ] = true;
}
$ncDirs  = [];
$ncFiles = [];
foreach ( $m['not_checked'] as $p ) {
	if ( '/' === substr( $p, -1 ) ) {
		$ncDirs[] = $p;
	} else {
		$ncFiles[ $p ] = true;
		$st = @stat( $p );
		if ( false !== $st ) {
			$ncFiles[ $st['dev'] . ':' . $st['ino'] ] = true; // Another name of a not_checked file is not_checked too.
		}
	}
}
foreach ( $m['checked'] as $p ) {
	if ( isset( $ncFiles[ $p ] ) ) {
		$problems[] = "both checked and not_checked: $p";
	}
}

$codeRe  = '/\.(?:' . implode( '|', array_map( 'preg_quote', $m['code_extensions'] ) ) . ')\z/' . ( $m['extensions_case_insensitive'] ? 'i' : '' );
$sniff   = $m['sniff'];
$core    = $m['core']['root'];
$skipped = array_merge( $m['excluded'], $m['old_releases'] );

$isCode = static function ( string $path, string $name ) use ( $codeRe, $m, $sniff, $under ): bool {
	if ( preg_match( $codeRe, $name ) || preg_match( $m['phar_regex'], $name ) ) {
		return true;
	}
	if ( 'except_skipped_dirs' !== $sniff['scope'] || $under( $path, $sniff['skipped_dirs'] ) ) {
		return false;
	}
	if ( in_array( strtolower( (string) pathinfo( $name, PATHINFO_EXTENSION ) ), $sniff['exclude_extensions'], true ) ) {
		return false;
	}
	$fh = @fopen( $path, 'rb' );
	if ( false === $fh ) {
		return false; // uid 33 can't read it, so PHP-FPM can't run it.
	}
	$head = (string) fread( $fh, $sniff['bytes'] );
	fclose( $fh );
	return 1 === preg_match( $sniff['regex'], $head );
};

$codeFiles = 0;
$stack     = $m['roots'];
while ( $stack ) {
	$dir = array_pop( $stack );
	if ( $under( $dir, $skipped ) ) {
		continue;
	}
	$h = @opendir( $dir );
	if ( false === $h ) {
		if ( ! $under( $dir, $ncDirs ) ) {
			$problems[] = "unlistable dir not in not_checked: $dir";
		}
		continue;
	}
	while ( false !== ( $name = readdir( $h ) ) ) {
		if ( '.' === $name || '..' === $name ) {
			continue;
		}
		$path = $dir . $name;
		$st   = @lstat( $path );
		if ( false === $st ) {
			continue;
		}
		$type = $st['mode'] & 0170000;
		if ( 0040000 === $type ) {
			$stack[] = $path . '/';
			continue;
		}
		if ( 0100000 !== $type || $under( $path, $skipped ) || ! $isCode( $path, $name ) ) {
			continue;
		}
		$codeFiles++;
		if ( null !== $core && ( $under( $path, [ $core . 'wp-admin/', $core . 'wp-includes/' ] ) || ( dirname( $path ) . '/' === $core && in_array( $name, $m['core']['files'], true ) ) ) ) {
			continue; // The scanned root's core: exempt by shape.
		}
		$ino = $st['dev'] . ':' . $st['ino'];
		if ( ! isset( $inodes[ $ino ] ) && ! isset( $ncFiles[ $path ] ) && ! isset( $ncFiles[ $ino ] ) && ! $under( $path, $ncDirs ) ) {
			$problems[] = "code file neither checked nor not_checked: $path";
		}
	}
	closedir( $h );
}
$out();
