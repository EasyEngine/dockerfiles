<?php
// Checks a scan's /out/manifest.json against the fixture it scanned, mounted at /var/www as for the scan.
// Every code file under the manifest's roots, by the manifest's own rules (code_extensions, phar_regex, sniff), must be
// checked (same inode) or under not_checked, unless it is the scanned root's core or an old release (`excluded` is not
// an exemption). Run as uid 33, or as root with DAC_OVERRIDE to walk the whole tree as EE does.
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

// A path that isn't UTF-8 is listed as `b64:` + base64 of its bytes, in the lists and in the head fields.
$decode = static function ( $p ) {
	return is_string( $p ) && 0 === strpos( $p, 'b64:' ) ? base64_decode( substr( $p, 4 ), true ) : $p;
};
foreach ( [ 'checked', 'not_checked', 'roots', 'excluded', 'old_releases' ] as $list ) {
	$m[ $list ] = array_map( $decode, $m[ $list ] );
}
$m['sniff']['skipped_dirs'] = array_map( $decode, $m['sniff']['skipped_dirs'] );
$m['core']['root']          = $decode( $m['core']['root'] );

// uid 33 (gid 33, no other groups) may read the file: by mode bits, with search permission on every directory above it.
$root      = 0 === posix_geteuid();
$allows    = static function ( string $p, int $bit ): bool {
	$st = @stat( $p );
	if ( false === $st ) {
		return false;
	}
	$shift = 33 === $st['uid'] ? 6 : ( 33 === $st['gid'] ? 3 : 0 );
	return 0 !== ( $st['mode'] & ( $bit << $shift ) );
};
$readable = static function ( string $path ) use ( $root, $allows ): bool {
	if ( ! $root ) {
		return is_readable( $path );
	}
	for ( $d = dirname( $path ); strlen( $d ) > 1; $d = dirname( $d ) ) {
		if ( ! $allows( $d, 1 ) ) {
			return false;
		}
	}
	return $allows( $path, 4 );
};

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
$skipped = $m['old_releases'];

$isCode = static function ( string $path, string $name ) use ( $codeRe, $m, $sniff, $under, $readable ): bool {
	if ( preg_match( $codeRe, $name ) || preg_match( $m['phar_regex'], $name ) ) {
		return true;
	}
	if ( 'except_skipped_dirs' !== $sniff['scope'] || $under( $path, $sniff['skipped_dirs'] ) ) {
		return false;
	}
	if ( in_array( strtolower( (string) pathinfo( $name, PATHINFO_EXTENSION ) ), $sniff['exclude_extensions'], true ) ) {
		return false;
	}
	$fh = $readable( $path ) ? @fopen( $path, 'rb' ) : false;
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
