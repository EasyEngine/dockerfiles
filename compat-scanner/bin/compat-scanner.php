<?php
/**
 * Entrypoint of easyengine/compat-scanner.
 *
 * Usage: <scan|estimate> <wp|php> <site_container_fs_path> <version> <timeout>
 *
 * Prints exactly one JSON document on stdout. `ee site php-compat` in
 * site-command parses it; keep both in sync with INTERFACE.md.
 */

declare( strict_types=1 );

// Diagnostics never go to stdout, which carries only the JSON document.
ini_set( 'display_errors', 'stderr' );
ini_set( 'log_errors', '0' );
error_reporting( E_ALL );

const MOUNT_ROOT      = '/var/www';
const OUT_DIR         = '/out';
const TOOL_DIR        = '/opt/compat-scanner';
const PHPCS_BIN       = TOOL_DIR . '/vendor/squizlabs/php_codesniffer/bin/phpcs';
const REPORT_CLASS    = TOOL_DIR . '/src/LinesReport.php';
const CALIBRATION_DIR = TOOL_DIR . '/calibration';
const JSON_FLAGS      = JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE;
const TOP_SKIPS       = [ 'uploads', 'cache', 'upgrade', 'languages' ];
const ANY_SKIPS       = [ 'node_modules', '.git' ];
const STRUCTURAL      = [ 'plugins', 'themes', 'mu-plugins' ];
const TYPE_ORDER      = [ 'plugin' => 0, 'theme' => 1, 'mu-plugin' => 2, 'directory' => 3, 'other' => 4 ];
// Same as EE's REPORT_MAX: EE rejects a larger report anyway.
const REPORT_MAX      = 134217728;
// Slack over the cap for PHPCS's own report file: a header line (up to ~6 KB) per file.
const FSIZE_SLACK     = 2097152;
const HEADER_MAX      = 6144;
const LINE_MAX        = 1048576;
const BUFFER_MAX      = 262144;

class TimedOut extends RuntimeException {
}

class BadArgs extends RuntimeException {
}

class ToolError extends RuntimeException {
}

final class Scanner {

	/** @var array<string,mixed> */
	private $cfg;
	/** @var float */
	private $start;
	/** @var float */
	private $deadline;
	/** @var int */
	private $timeoutLabel;
	/** @var bool */
	private $isScan;

	/** @var array<int,array<string,mixed>> Components by index. */
	private $comps = [];
	/** @var array<string,int> */
	private $compKeys = [];
	/** @var string|null Real path of the content root (wp-content, or htdocs for php sites). */
	private $contentReal;
	/** @var string|null Real path of the WordPress directory (wp only). */
	private $siteReal;
	/** @var string[] Real paths of the releases a php site's `current` doesn't point to. */
	private $oldReleases = [];
	/** @var array<int,array<int,bool>> Visited directories by device and inode. */
	private $seenDirs = [];
	/** @var array<int,array<int,bool>> Listed files by device and inode. */
	private $seenFiles = [];
	/** @var array<string,string|false> Real paths of the site path and content root when listed. */
	private $pins = [];
	/** @var int */
	private $ticks = 0;

	/** @var int */
	private $listedFiles = 0;
	/** @var int */
	private $listedBytes = 0;
	/** @var int */
	private $notCheckedCount = 0;

	/** @var string */
	private $work = '';
	/** @var resource|null File list spool (scan mode). */
	private $listFh;
	/** @var string */
	private $listBuf = '';
	/** @var int Bytes of the file list spool. */
	private $listBytes = 0;
	/** @var int Bytes of findings and not_checked entries spooled so far. */
	private $reportBytes = 0;

	public function __construct( array $cfg ) {
		$this->cfg    = $cfg;
		$this->isScan = 'scan' === $cfg['mode'];
		$this->start  = microtime( true );
		$limit        = $this->isScan ? $cfg['timeout'] : $cfg['estimate_timeout'];

		$this->timeoutLabel = $limit;
		$this->deadline     = $this->start + $limit;
	}

	public function run(): array {
		if ( $this->isScan ) {
			$this->work = OUT_DIR . '/.work';
			$this->makeWork();
			$this->listFh = fopen( $this->work . '/files', 'w+b' );
			if ( false === $this->listFh ) {
				throw new ToolError( 'output directory not writable' );
			}
		}

		if ( $this->cfg['debug'] && function_exists( 'posix_getrlimit' ) ) {
			$this->debug( 'core limit ' . ( posix_getrlimit()['soft core'] ?? '?' ) );
		}
		$this->listFiles();

		if ( 0 === $this->listedFiles && 0 === $this->notCheckedCount ) {
			$this->removeWork();
			return $this->reduced( 'no_code_found' );
		}
		if ( ! $this->isScan ) {
			return $this->estimate();
		}

		$this->flushList();
		$this->readHeaders();
		return $this->scan();
	}

	// ---------------------------------------------------------------- listing

	/**
	 * Lists the files in scope. For WordPress, plugins, themes and mu-plugins of
	 * every content root are walked before anything else, so a directory reached
	 * both from there and through another path belongs to the component.
	 */
	private function listFiles(): void {
		$this->pins[ $this->cfg['path'] ] = @realpath( $this->cfg['path'] );
		if ( 'php' === $this->cfg['site_type'] ) {
			$root = MOUNT_ROOT . '/htdocs';
			if ( ! $this->enterRoot( $root ) ) {
				return;
			}
			$this->oldReleases = $this->oldReleases( $this->cfg['path'] );
			$other             = $this->comp( 'other', '', null, $root );
			$entries           = $this->readDir( $root );
			if ( null === $entries ) {
				$this->notChecked( $other, './', 'unreadable' );
				return;
			}
			$this->scanPhpRoot( $root, $entries, $other );
			return;
		}

		$root = $this->cfg['path'] . '/wp-content';
		if ( ! $this->enterRoot( $root ) ) {
			return;
		}
		// Before siteReal is set: the config usually sits inside the WordPress directory.
		$config = $this->wpConfig( $this->cfg['path'] );
		if ( null !== $config ) {
			// Reported by its real path relative to /var/www (the file to edit), e.g. htdocs/wp-config.php.
			$real = @realpath( $config );
			$path = false !== $real && $this->inside( $real ) ? $real : $config;
			$this->visit( $path, 'wp-config.php', $this->comp( 'other', 'wp-config.php', null, MOUNT_ROOT ) );
		}
		$site = @realpath( $this->cfg['path'] );
		if ( false !== $site && $this->inside( $site ) ) {
			$this->siteReal = $site;
		}

		$main = $this->wpRoot( $root, null );
		if ( null === $main['entries'] ) {
			$this->notChecked( $main['other'], './', 'unreadable' );
			return;
		}

		// Branch roots: other direct children holding plugins/ or themes/.
		$candidates = [];
		foreach ( $main['entries'] as $name ) {
			if ( in_array( $name, STRUCTURAL, true ) ) {
				continue;
			}
			$path = $root . '/' . $name;
			$real = $this->resolve( $path );
			if ( null !== $real && is_dir( $real ) && ! $this->outOfScope( $real ) && ( is_dir( $path . '/plugins' ) || is_dir( $path . '/themes' ) ) ) {
				$candidates[] = [ $name, $path, $real ];
			}
		}

		// Main root first, so its plugins and themes win over a branch link to them.
		$main     = $this->structural( $main );
		$branches = [];
		foreach ( $candidates as list( $name, $path, $real ) ) {
			if ( ! $this->markDir( $real ) ) {
				continue;
			}
			$b = $this->wpRoot( $path, (string) $name );
			if ( null === $b['entries'] ) {
				$this->notChecked( $b['other'], './', 'unreadable' );
			}
			$branches[ $name ] = $this->structural( $b );
		}

		$this->others( $main, $branches );
	}

	/**
	 * The wp-config.php WordPress loads: in its (resolved) directory, else in the
	 * parent when that holds no wp-settings.php; the unresolved parent last
	 * (`htdocs/wp-config.php` above a `current` link).
	 */
	private function wpConfig( string $wpDir ): ?string {
		$real = @realpath( $wpDir );
		if ( false === $real ) {
			return null;
		}
		if ( file_exists( $real . '/wp-config.php' ) ) {
			return $real . '/wp-config.php';
		}
		foreach ( array_unique( [ dirname( $real ), dirname( $wpDir ) ] ) as $parent ) {
			if ( $this->inside( $parent ) && file_exists( $parent . '/wp-config.php' ) && ! file_exists( $parent . '/wp-settings.php' ) ) {
				return $parent . '/wp-config.php';
			}
		}
		return null;
	}

	/**
	 * CI/CD layout of a php site: the first `current` symlink on the public path,
	 * pointing at a direct child of a real `releases/` dir next to it (as site-command's
	 * backup detects it). Returns the other releases, which aren't scanned.
	 *
	 * @return string[]
	 */
	private function oldReleases( string $publicDir ): array {
		$path = MOUNT_ROOT;
		foreach ( explode( '/', substr( $publicDir, strlen( MOUNT_ROOT ) + 1 ) ) as $part ) {
			$parent = $path;
			$path  .= '/' . $part;
			if ( 'current' !== $part || ! is_link( $path ) ) {
				continue;
			}
			$live      = @realpath( $path );
			$parentRaw = @realpath( $parent );
			if ( false === $live || false === $parentRaw ) {
				return [];
			}
			$releases = $parentRaw . '/releases';
			if ( is_link( $releases ) || ! is_dir( $releases ) || ! $this->inside( $releases ) || dirname( $live ) !== $releases ) {
				return [];
			}
			$old = [];
			foreach ( (array) $this->readDir( $releases ) as $name ) {
				$dir = $releases . '/' . $name;
				if ( $dir !== $live && ! is_link( $dir ) && is_dir( $dir ) ) {
					$old[] = $dir;
				}
			}
			return $old;
		}
		return [];
	}

	/** True when the root exists as a directory inside the mount. */
	private function enterRoot( string $root ): bool {
		$real = @realpath( $root );
		if ( false === $real || ! is_dir( $real ) || ! $this->inside( $real ) ) {
			// A root uid 33 can't reach (EACCES on the way) may hold code: not no_code_found.
			if ( false === $real && function_exists( 'posix_access' ) && ! @posix_access( $root ) && 13 === posix_get_last_error() ) {
				$this->notChecked( $this->comp( 'other', '', null, $root ), './', 'unreadable' );
			}
			return false;
		}
		$this->pins[ $root ] = $real;
		$this->contentReal   = $real;
		$this->markDir( $real );
		return true;
	}

	/** A content root's `other` component and its entries, top-level skips removed. */
	private function wpRoot( string $path, ?string $branch ): array {
		$entries = $this->readDir( $path );
		if ( null !== $entries ) {
			$entries = array_values(
				array_filter(
					$entries,
					static function ( $name ) {
						return ! in_array( $name, TOP_SKIPS, true ) && ! in_array( $name, ANY_SKIPS, true );
					}
				)
			);
		}
		return [
			'path'    => $path,
			'branch'  => $branch,
			'other'   => $this->comp( 'other', '', $branch, $path ),
			'entries' => $entries,
			'plugins' => null,
			'themes'  => null,
		];
	}

	/** First pass over a content root: plugins, theme directories and mu-plugins. */
	private function structural( array $r ): array {
		foreach ( (array) $r['entries'] as $name ) {
			if ( ! in_array( $name, STRUCTURAL, true ) ) {
				continue;
			}
			$path = $r['path'] . '/' . $name;
			$real = $this->resolve( $path );
			if ( null === $real || ! is_dir( $real ) || $this->outOfScope( $real ) || ! $this->markDir( $real ) ) {
				continue;
			}
			if ( 'plugins' === $name ) {
				$r['plugins'] = $this->scanPlugins( $path, $r['branch'], $r['other'] );
			} elseif ( 'themes' === $name ) {
				$r['themes'] = $this->scanThemes( $path, $r['branch'], $r['other'] );
			} else {
				$mu = $this->comp( 'mu-plugin', 'mu-plugins', $r['branch'], $path );
				$this->walk( $path, $mu );
			}
		}
		return $r;
	}

	/** Second pass: everything else under a content root, in sorted order. */
	private function others( array $r, array $branches ): void {
		foreach ( (array) $r['entries'] as $name ) {
			$path = $r['path'] . '/' . $name;
			if ( in_array( $name, STRUCTURAL, true ) ) {
				$loose = 'themes' === $name ? $r['themes'] : ( 'plugins' === $name ? $r['plugins'] : null );
				if ( null !== $loose ) {
					// Loose files in themes/, and header-less ones in plugins/, belong to `other`.
					foreach ( $loose as $file ) {
						$this->visit( $path . '/' . $file, $file, $r['other'] );
					}
					continue;
				}
				$real = $this->resolve( $path );
				if ( null !== $real && is_dir( $real ) ) {
					continue; // Walked in the first pass, or already visited.
				}
			} elseif ( isset( $branches[ $name ] ) ) {
				$this->others( $branches[ $name ], [] );
				continue;
			}
			$this->visit( $path, $name, $r['other'] );
		}
	}

	/** @return string[] Loose files without a plugin header, left for the second pass. */
	private function scanPlugins( string $dir, ?string $branch, int $other ): array {
		$entries = $this->readDir( $dir );
		if ( null === $entries ) {
			$this->notChecked( $other, 'plugins/', 'unreadable' );
			return [];
		}

		$loose = [];
		foreach ( $entries as $name ) {
			if ( in_array( $name, ANY_SKIPS, true ) ) {
				continue;
			}
			$path = $dir . '/' . $name;
			$real = $this->resolve( $path );

			if ( null !== $real && is_dir( $real ) ) {
				if ( ! $this->outOfScope( $real ) && $this->markDir( $real ) ) {
					$comp = $this->comp( 'plugin', $name, $branch, $path, [ 'header' => 'plugin-dir', 'at' => $path ] );
					$this->walk( $path, $comp );
				}
				continue;
			}

			if ( null !== $real && ! $this->isPhpName( $name ) ) {
				continue;
			}
			if ( null === $real && ! $this->linkMatters( $path, $name ) ) {
				continue;
			}
			// WordPress' `index.php` stub and other header-less files aren't plugins.
			if ( null !== $real ) {
				$this->tick();
				$head = read_head( $path );
				if ( null !== $head && null === header_value( str_replace( "\r", "\n", $head ), 'Plugin Name' ) ) {
					$loose[] = $name;
					continue;
				}
			}

			$comp = $this->comp( 'plugin', $name, $branch, $dir, [ 'header' => 'plugin-file', 'at' => $path ] );
			$this->visit( $path, $name, $comp );
		}
		return $loose;
	}

	/** @return string[] Loose entries left for the second pass. */
	private function scanThemes( string $dir, ?string $branch, int $other ): array {
		$entries = $this->readDir( $dir );
		if ( null === $entries ) {
			$this->notChecked( $other, 'themes/', 'unreadable' );
			return [];
		}

		$loose = [];
		foreach ( $entries as $name ) {
			if ( in_array( $name, ANY_SKIPS, true ) ) {
				continue;
			}
			$path = $dir . '/' . $name;
			$real = $this->resolve( $path );

			if ( null !== $real && is_dir( $real ) ) {
				if ( ! $this->outOfScope( $real ) && $this->markDir( $real ) ) {
					$comp = $this->comp( 'theme', $name, $branch, $path, [ 'header' => 'theme', 'at' => $path ] );
					$this->walk( $path, $comp );
				}
			} elseif ( null === $real && $this->linkMatters( $path, $name ) && ! $this->isPhpName( $name ) ) {
				// A theme dir behind a bad link.
				$comp = $this->comp( 'theme', $name, $branch, $path );
				$this->notChecked( $comp, './', 'unreadable' );
			} else {
				$loose[] = $name;
			}
		}
		return $loose;
	}

	private function scanPhpRoot( string $root, array $entries, int $other ): void {
		foreach ( $entries as $name ) {
			if ( in_array( $name, ANY_SKIPS, true ) ) {
				continue;
			}
			$path = $root . '/' . $name;
			$real = $this->resolve( $path );

			if ( null !== $real && is_dir( $real ) ) {
				if ( ! $this->outOfScope( $real ) && $this->markDir( $real ) ) {
					$comp = $this->comp( 'directory', $name, null, $path );
					$this->walk( $path, $comp );
				}
			} elseif ( null === $real && $this->linkMatters( $path, $name ) && ! $this->isPhpName( $name ) ) {
				$comp = $this->comp( 'directory', $name, null, $path );
				$this->notChecked( $comp, './', 'unreadable' );
			} else {
				$this->visit( $path, $name, $other );
			}
		}
	}

	private function walk( string $dir, int $comp ): void {
		$entries = $this->readDir( $dir );
		if ( null === $entries ) {
			$this->notChecked( $comp, $this->rel( $comp, $dir ) . '/', 'unreadable' );
			return;
		}

		foreach ( $entries as $name ) {
			if ( in_array( $name, ANY_SKIPS, true ) ) {
				continue;
			}
			$this->visit( $dir . '/' . $name, $name, $comp );
		}
	}

	/** One directory entry: recurse into directories, list PHP files. */
	private function visit( string $path, string $name, int $comp ): void {
		$this->tick();
		$real = $this->resolve( $path );

		if ( null === $real ) {
			if ( $this->linkMatters( $path, $name ) ) {
				$this->notChecked( $comp, $this->rel( $comp, $path ), 'unreadable' );
			}
			return;
		}
		if ( $this->outOfScope( $real ) ) {
			return;
		}

		if ( is_dir( $real ) ) {
			if ( $this->markDir( $real ) ) {
				$this->walk( $path, $comp );
			}
			return;
		}

		if ( ! $this->isPhpName( $name ) ) {
			return;
		}
		$st = @stat( $real );
		if ( false === $st || 0100000 !== ( $st['mode'] & 0170000 ) ) {
			return;
		}
		if ( isset( $this->seenFiles[ $st['dev'] ][ $st['ino'] ] ) ) {
			return;
		}
		$this->seenFiles[ $st['dev'] ][ $st['ino'] ] = true;

		if ( ! is_readable( $real ) ) {
			$this->notChecked( $comp, $this->rel( $comp, $path ), 'unreadable' );
			return;
		}

		$this->comps[ $comp ]['listed']++;
		$this->listedFiles++;
		$this->listedBytes += $st['size'];
		if ( $this->isScan ) {
			// Relative to the component's base; the spool counts against the report cap too.
			$rel   = $this->rel( $comp, $path );
			$entry = pack( 'VPV', $comp, $st['size'], strlen( $rel ) ) . $rel;

			$this->listBytes += strlen( $entry );
			if ( $this->listBytes > $this->cfg['report_max'] ) {
				throw new ToolError( sprintf( 'file list larger than %d bytes', $this->cfg['report_max'] ) );
			}
			$this->listBuf .= $entry;
			if ( strlen( $this->listBuf ) >= BUFFER_MAX ) {
				$this->flushList();
			}
		}
	}

	/** Real path when it exists and stays inside the mount, else null. */
	private function resolve( string $path ): ?string {
		$real = @realpath( $path );
		if ( false === $real || ! $this->inside( $real ) ) {
			return null;
		}
		return $real;
	}

	/**
	 * Targets a link may not pull in: the content root and its ancestors, and
	 * WordPress core (inside the WordPress directory, outside wp-content).
	 */
	private function outOfScope( string $real ): bool {
		foreach ( $this->oldReleases as $old ) {
			if ( 0 === strpos( $real . '/', $old . '/' ) ) {
				return true;
			}
		}
		if ( null !== $this->contentReal && 0 === strpos( $this->contentReal . '/', $real . '/' ) ) {
			return true;
		}
		return null !== $this->siteReal
			&& 0 === strpos( $real . '/', $this->siteReal . '/' )
			&& 0 !== strpos( $real . '/', $this->contentReal . '/' );
	}

	/**
	 * Whether a path that doesn't resolve inside the mount must be reported:
	 * PHP files and (possible) directories; a broken `readme.txt` link isn't.
	 */
	private function linkMatters( string $path, string $name ): bool {
		if ( $this->isPhpName( $name ) ) {
			return true;
		}
		$target = @realpath( $path );
		if ( false !== $target ) {
			return is_dir( $target );
		}
		return ! preg_match( '/\.[A-Za-z0-9]{1,8}\z/', $name );
	}

	private function isPhpName( string $name ): bool {
		return '.php' === substr( $name, -4 );
	}

	private function inside( string $real ): bool {
		return MOUNT_ROOT === $real || 0 === strpos( $real, MOUNT_ROOT . '/' );
	}

	/** Marks a real directory visited; false when it already was (loops, double paths). */
	private function markDir( string $real ): bool {
		$st = @stat( $real );
		if ( false === $st ) {
			return false;
		}
		if ( isset( $this->seenDirs[ $st['dev'] ][ $st['ino'] ] ) ) {
			return false;
		}
		$this->seenDirs[ $st['dev'] ][ $st['ino'] ] = true;
		return true;
	}

	/**
	 * @return string[]|null Entry names, null when the directory can't be listed.
	 * Sorted as if directories had a trailing `/`, so a depth-first walk lists
	 * each component's files in byte order of their full paths.
	 */
	private function readDir( string $dir ): ?array {
		$this->tick();
		$handle = @opendir( $dir );
		if ( false === $handle ) {
			return null;
		}
		$keys = [];
		while ( false !== ( $name = readdir( $handle ) ) ) {
			if ( '.' !== $name && '..' !== $name ) {
				$keys[] = is_dir( $dir . '/' . $name ) ? $name . '/' : $name;
			}
		}
		closedir( $handle );
		sort( $keys, SORT_STRING );
		foreach ( $keys as $i => $key ) {
			if ( '/' === substr( $key, -1 ) ) {
				$keys[ $i ] = substr( $key, 0, -1 );
			}
		}
		return $keys;
	}

	private function tick(): void {
		if ( 0 === ( ++$this->ticks % 500 ) && microtime( true ) >= $this->deadline ) {
			throw new TimedOut( sprintf( 'timed out after %d s while listing files', $this->timeoutLabel ) );
		}
	}

	private function comp( string $type, string $slug, ?string $branch, string $base, array $header = [] ): int {
		$key = $type . "\0" . ( $branch ?? "\0" ) . "\0" . $slug;
		if ( isset( $this->compKeys[ $key ] ) ) {
			return $this->compKeys[ $key ];
		}
		$this->comps[] = [
			'type'     => $type,
			'slug'     => $slug,
			'branch'   => $branch,
			'base'     => $base,
			'header'   => $header,
			'name'     => null,
			'version'  => null,
			'listed'   => 0,
			'files'    => 0,
			'bytes'    => 0,
			'errors'   => 0,
			'warnings' => 0,
		];
		$idx = count( $this->comps ) - 1;

		$this->compKeys[ $key ] = $idx;
		return $idx;
	}

	private function rel( int $comp, string $path ): string {
		$base = $this->comps[ $comp ]['base'];
		if ( $path === $base ) {
			return '.';
		}
		return substr( $path, strlen( $base ) + 1 );
	}

	private function notChecked( int $comp, string $file, string $reason ): void {
		if ( $this->isScan ) {
			$this->spoolNotChecked( $comp, $file, $reason );
		} else {
			$this->notCheckedCount++;
		}
	}

	/** @return int[] Components with at least one listed file. */
	private function listedComponents(): array {
		$out = [];
		foreach ( $this->comps as $idx => $c ) {
			if ( $c['listed'] > 0 ) {
				$out[] = $idx;
			}
		}
		return $out;
	}

	/** Plugin and theme headers, read while the listing deadline still applies. */
	private function readHeaders(): void {
		foreach ( $this->listedComponents() as $idx ) {
			$header = $this->comps[ $idx ]['header'];
			if ( ! $header ) {
				continue;
			}
			list( $name, $ver ) = $this->readHeader( $header );

			$this->comps[ $idx ]['name']    = $name ?? $this->comps[ $idx ]['slug'];
			$this->comps[ $idx ]['version'] = $ver;
		}
	}

	/** Reads `Plugin Name`/`Theme Name` and `Version` the way WordPress' get_file_data() does. */
	private function readHeader( array $header ): array {
		$field = 'theme' === $header['header'] ? 'Theme Name' : 'Plugin Name';

		if ( 'theme' === $header['header'] ) {
			$candidates = [ $header['at'] . '/style.css' ];
		} elseif ( 'plugin-file' === $header['header'] ) {
			$candidates = [ $header['at'] ];
		} else {
			$candidates = [];
			foreach ( (array) $this->readDir( $header['at'] ) as $n ) {
				if ( $this->isPhpName( $n ) ) {
					$candidates[] = $header['at'] . '/' . $n;
				}
			}
		}

		foreach ( $candidates as $file ) {
			$this->tick();
			$data = read_head( $file );
			if ( null === $data ) {
				continue;
			}
			$data = str_replace( "\r", "\n", $data );
			$name = header_value( $data, $field );
			if ( null !== $name ) {
				return [ $name, header_value( $data, 'Version' ) ];
			}
		}
		return [ null, null ];
	}

	// --------------------------------------------------------------- estimate

	private function estimate(): array {
		$files = $this->listedFiles;
		$bytes = $this->listedBytes;

		$this->work = '/tmp/compat-estimate';
		$this->makeWork();
		try {
			$empty = $this->timed( [ CALIBRATION_DIR . '/empty.php' ] );
			$list  = array_values( array_filter( array_map( 'trim', file( CALIBRATION_DIR . '/sample.list' ) ) ) );
			$calBytes = 0;
			foreach ( $list as $p ) {
				$calBytes += filesize( $p );
			}
			$sample = $this->timed( $list );
		} finally {
			$this->removeWork();
		}

		$calSeconds = max( 0.01, $sample - $empty );
		$bps        = $calBytes / $calSeconds;
		$batches    = $files > 0 ? (int) ceil( $files / $this->cfg['batch_size'] ) : 0;
		$perBatch   = $this->cfg['seconds_per_batch'];
		$raw        = $bytes / $bps + $batches * $perBatch;
		$est        = max( 1, (int) round( $raw ) );

		$doc = $this->head( 'ok' );

		$doc['php_files']              = $files + $this->notCheckedCount;
		$doc['php_bytes']              = $bytes;
		$doc['components']             = count( $this->listedComponents() );
		$doc['estimated_seconds']      = $est;
		$doc['estimated_seconds_low']  = max( 1, (int) round( $est * $this->cfg['low_factor'] ) );
		$doc['estimated_seconds_high'] = max( 1, (int) ceil( $est * $this->cfg['high_factor'] ) );
		$doc['inputs']                 = [
			'calibration_bytes'   => $calBytes,
			'calibration_seconds' => round( $calSeconds, 2 ),
			'startup_seconds'     => round( $empty, 2 ),
			'bytes_per_second'    => (int) round( $bps ),
			'batches'             => $batches,
			'seconds_per_batch'   => $perBatch,
			'cpus'                => cpu_count(),
			'load_average_1m'     => load_average(),
			'low_factor'          => $this->cfg['low_factor'],
			'high_factor'         => $this->cfg['high_factor'],
		];
		return $doc;
	}

	/** Wall time of one successful PHPCS run over $paths. */
	private function timed( array $paths ): float {
		$t   = hrtime( true );
		$res = $this->phpcs( $paths, $this->cfg['batch_memory'], 'cal' );
		$dt  = ( hrtime( true ) - $t ) / 1e9;
		if ( $res['timeout'] || ( ! $res['ok'] && microtime( true ) >= $this->deadline ) ) {
			throw new TimedOut( sprintf( 'timed out after %d s while calibrating', $this->timeoutLabel ) );
		}
		if ( ! $res['ok'] ) {
			throw new ToolError( 'calibration run failed with exit code ' . $res['rc'] );
		}
		return $dt;
	}

	// ------------------------------------------------------------------- scan

	private function scan(): array {
		rewind( $this->listFh );
		$batch = [];
		$read  = 0;
		while ( null !== ( $rec = $this->nextFile() ) ) {
			$read++;
			$batch[] = $rec;
			if ( count( $batch ) >= $this->cfg['batch_size'] ) {
				$this->runBatch( $batch );
				$batch = [];
			}
		}
		if ( $batch ) {
			$this->runBatch( $batch );
		}
		fclose( $this->listFh );
		$this->listFh = null;
		if ( $read !== $this->listedFiles ) {
			throw new ToolError( 'could not read the file list' );
		}
		$this->checkPins();

		return $this->finish();
	}

	/** @return array{comp:int,size:int,path:string}|null */
	private function nextFile(): ?array {
		$head = fread( $this->listFh, 16 );
		if ( '' === $head && feof( $this->listFh ) ) {
			return null;
		}
		if ( false === $head || 16 !== strlen( $head ) ) {
			throw new ToolError( 'could not read the file list' );
		}
		$h   = unpack( 'Vcomp/Psize/Vlen', $head );
		$rel = $h['len'] > 0 ? fread( $this->listFh, $h['len'] ) : '';
		if ( false === $rel || strlen( $rel ) !== $h['len'] || ! isset( $this->comps[ $h['comp'] ] ) ) {
			throw new ToolError( 'could not read the file list' );
		}
		return [ 'comp' => $h['comp'], 'size' => $h['size'], 'path' => $this->comps[ $h['comp'] ]['base'] . '/' . $rel ];
	}

	/**
	 * Steps 1 and 2: the batch, then on their own the files it didn't finish.
	 * Files are recorded in list order, so findings stay sorted by file.
	 */
	private function runBatch( array $batch ): void {
		$this->checkPins();
		$plain = [];
		foreach ( $batch as $k => $f ) {
			$real = $this->resolve( $f['path'] );
			$st   = null === $real ? false : @stat( $real );
			if ( false === $st || 0100000 !== ( $st['mode'] & 0170000 ) ) {
				$batch[ $k ]['real'] = null; // Gone, or no longer a regular file.
				continue;
			}
			// A file rewritten since the listing (a live site) is checked as it is now.
			$batch[ $k ]['size']  = $st['size'];
			$batch[ $k ]['real']  = $real;
			// --file-list splits on newlines and trims each line, and PHPCS skips a
			// file whose real name doesn't end in .php: such files go through STDIN.
			$batch[ $k ]['stdin'] = odd_path( $real ) || ! $this->isPhpName( $real );
			if ( ! $batch[ $k ]['stdin'] ) {
				$plain[ $real ] = $k;
			}
		}

		$reader = null;
		if ( $plain ) {
			$res = $this->phpcs( array_keys( $plain ), $this->cfg['batch_memory'], 'batch' );
			$this->debug( sprintf( 'batch %d files rc=%d %.2fs', count( $plain ), $res['rc'], $res['seconds'] ) );
			if ( $res['timeout'] || ( ! $res['ok'] && microtime( true ) >= $this->deadline ) ) {
				throw $this->timedOutAt( $batch[ reset( $plain ) ]['path'] );
			}
			$this->checkSize( $res );
			if ( $res['ok'] ) {
				$reader = new ReportReader( $res['report'] );
				if ( ! $reader->valid() ) {
					$reader->close();
					$reader = null;
				}
			}
		}

		$remaining = $plain;
		foreach ( $batch as $f ) {
			if ( null === $f['real'] ) {
				$this->spoolNotChecked( $f['comp'], $this->rel( $f['comp'], $f['path'] ), 'unreadable' );
				continue;
			}
			if ( null !== $reader && ! $f['stdin'] ) {
				// Skip report blocks of files that aren't still expected; a block of a
				// later file means PHPCS didn't report this one.
				while ( null !== ( $name = $reader->peek() ) && $name !== $f['real'] && ! isset( $remaining[ $name ] ) ) {
					$reader->skip();
				}
				unset( $remaining[ $f['real'] ] );
				if ( $name === $f['real'] ) {
					$this->record( $f, $reader );
					continue;
				}
				$this->checkSpace();
			}
			$this->runSingle( $f );
		}

		if ( null !== $reader ) {
			$reader->close();
		}
	}

	/** Steps 2 to 4 for one file. */
	private function runSingle( array $f ): void {
		$last = null;
		foreach ( [ $this->cfg['file_memory'], $this->cfg['retry_memory'] ] as $memory ) {
			$res = $this->phpcs( [ $f['real'] ], $memory, 'single', $f['stdin'] );
			$this->debug( sprintf( 'single %s at %s rc=%d %.2fs', $f['path'], $memory, $res['rc'], $res['seconds'] ) );
			if ( $res['timeout'] || ( ! $res['ok'] && microtime( true ) >= $this->deadline ) ) {
				throw $this->timedOutAt( $f['path'] );
			}
			$this->checkSize( $res );
			if ( $res['unreadable'] ) {
				$this->spoolNotChecked( $f['comp'], $this->rel( $f['comp'], $f['path'] ), 'unreadable' );
				return;
			}
			$last = $res;
			if ( $res['ok'] ) {
				// One input, so the one block is this file, whatever name PHPCS gave it.
				$reader = new ReportReader( $res['report'] );
				if ( ! $reader->valid() ) {
					// A finished run leaves a complete report unless the write failed.
					$reader->close();
					throw new ToolError( 'could not write to the output directory' );
				}
				$found = 1 === $reader->blocks() && null !== $reader->peek();
				if ( $found ) {
					$this->record( $f, $reader );
				}
				$reader->close();
				if ( $found ) {
					return;
				}
				$this->checkSpace();
				break; // Finished without reporting it: more memory won't change that.
			}
		}

		// busybox `timeout` execs PHP, so a SIGKILL from the kernel's OOM killer
		// arrives as 9 rather than 137; the deadline was ruled out above.
		$reason = null !== $last && in_array( $last['rc'], [ 9, 137, 255 ], true ) ? 'memory' : 'error';
		$this->spoolNotChecked( $f['comp'], $this->rel( $f['comp'], $f['path'] ), $reason );
	}

	/** A deploy that re-points `current` (or the content root) mid-scan would mix releases: no verdict then. */
	private function checkPins(): void {
		clearstatcache( true );
		foreach ( $this->pins as $path => $real ) {
			if ( @realpath( $path ) !== $real ) {
				throw new ToolError( 'the site code changed during the scan' );
			}
		}
	}

	private function timedOutAt( string $path ): TimedOut {
		return new TimedOut( sprintf( 'timed out after %d s at %s', $this->timeoutLabel, clean_text( substr( $path, strlen( MOUNT_ROOT ) + 1 ) ) ) );
	}

	/** A file missing from a finished run on a nearly full disk is a write failure, not `error`. */
	private function checkSpace(): void {
		$free = @disk_free_space( $this->work );
		if ( false !== $free && $free < 1048576 ) {
			throw new ToolError( 'could not write to the output directory' );
		}
	}

	private function checkSize( array $res ): void {
		if ( $res['too_large'] ) {
			throw $this->tooLarge();
		}
	}

	private function tooLarge(): ToolError {
		return new ToolError( sprintf( 'report larger than %d bytes', $this->cfg['report_max'] ) );
	}

	/** Counts one finished file and spools its findings from the report block. */
	private function record( array $f, ReportReader $reader ): void {
		$comp = $f['comp'];
		$rel  = clean_text( $this->rel( $comp, $f['path'] ) );

		$block = $reader->take();
		if ( $block['u'] ) {
			$reader->skipMessages();
			$this->spoolNotChecked( $comp, $rel, 'unparseable' );
			return;
		}

		$errors = $warnings = 0;
		$buf    = [ 'e' => '', 'w' => '' ];
		while ( null !== ( $m = $reader->message() ) ) {
			list( $line, , $type, $source, $text ) = $m;
			if ( 0 === strpos( $source, 'Internal.' ) ) {
				continue;
			}
			$entry = ',' . json_encode(
				[ 'file' => $rel, 'line' => $line, 'type' => $type, 'source' => clean_text( $source ), 'message' => clean_text( $text ) ],
				JSON_FLAGS
			);
			$this->addReportBytes( strlen( $entry ) );
			if ( 'ERROR' === $type ) {
				$errors++;
				$key = 'e';
			} else {
				$warnings++;
				$key = 'w';
			}
			$buf[ $key ] .= $entry;
			if ( strlen( $buf[ $key ] ) >= BUFFER_MAX ) {
				$this->append( $this->work . "/c$comp.$key", $buf[ $key ] );
				$buf[ $key ] = '';
			}
		}
		foreach ( $buf as $key => $data ) {
			if ( '' !== $data ) {
				$this->append( $this->work . "/c$comp.$key", $data );
			}
		}

		$c = &$this->comps[ $comp ];
		$c['files']++;
		$c['errors']   += $errors;
		$c['warnings'] += $warnings;
		$c['bytes']    += $f['size'];
		unset( $c );
	}

	private function spoolNotChecked( int $comp, string $file, string $reason ): void {
		$c     = $this->comps[ $comp ];
		$entry = ',' . json_encode(
			[ 'type' => $c['type'], 'slug' => clean_text( $c['slug'] ), 'branch' => clean_nullable( $c['branch'] ), 'file' => clean_text( $file ), 'reason' => $reason ],
			JSON_FLAGS
		);
		$this->addReportBytes( strlen( $entry ) );
		$this->append( $this->work . '/not_checked', $entry );
		$this->notCheckedCount++;
	}

	private function addReportBytes( int $n ): void {
		$this->reportBytes += $n;
		if ( $this->reportBytes > $this->cfg['report_max'] ) {
			throw $this->tooLarge();
		}
	}

	/** Builds the summary and streams the report from the spool. */
	private function finish(): array {
		$listed = $this->listedComponents();

		$errors = $warnings = $checked = $bytes = $withErrors = 0;
		foreach ( $listed as $idx ) {
			$c         = $this->comps[ $idx ];
			$errors   += $c['errors'];
			$warnings += $c['warnings'];
			$checked  += $c['files'];
			$bytes    += $c['bytes'];
			if ( $c['errors'] > 0 ) {
				$withErrors++;
			}
		}

		if ( $errors > 0 ) {
			$verdict = false;
		} elseif ( $this->notCheckedCount > 0 ) {
			$verdict = null;
		} else {
			$verdict = true;
		}

		$doc = $this->head( 'ok' );

		$doc['safe_to_upgrade']        = $verdict;
		$doc['errors']                 = $errors;
		$doc['warnings']               = $warnings;
		$doc['files_checked']          = $checked;
		$doc['files_not_checked']      = $this->notCheckedCount;
		$doc['php_bytes']              = $bytes;
		$doc['components_checked']     = count( $listed );
		$doc['components_with_errors'] = $withErrors;
		$doc['duration_s']             = (int) round( microtime( true ) - $this->start );
		$doc['tool']                   = tool_versions( $this->cfg['image'] );

		$comps = $this->comps;
		usort(
			$listed,
			static function ( $a, $b ) use ( $comps ) {
				$x = $comps[ $a ];
				$y = $comps[ $b ];
				return [ $y['errors'], $y['warnings'], TYPE_ORDER[ $x['type'] ], null !== $x['branch'], (string) $x['branch'], $x['slug'] ]
					<=> [ $x['errors'], $x['warnings'], TYPE_ORDER[ $y['type'] ], null !== $y['branch'], (string) $y['branch'], $y['slug'] ];
			}
		);

		$this->writeReport( $doc, $listed );
		$this->removeWork();
		$this->debug( sprintf( 'entrypoint peak memory %d bytes', memory_get_peak_usage() ) );
		return $doc;
	}

	private function writeReport( array $summary, array $order ): void {
		$tmp = OUT_DIR . '/report.json.tmp';
		$out = @fopen( $tmp, 'wb' );
		if ( false === $out ) {
			throw new ToolError( 'output directory not writable' );
		}

		$written = 0;
		$write   = function ( string $data ) use ( $out, &$written ) {
			$written += strlen( $data );
			if ( $written > $this->cfg['report_max'] ) {
				throw $this->tooLarge();
			}
			if ( fwrite( $out, $data ) !== strlen( $data ) ) {
				throw new ToolError( 'could not write the report' );
			}
		};

		try {
			$head = json_encode( $summary, JSON_FLAGS );
			$write( substr( $head, 0, -1 ) . ',"components":[' );

			foreach ( $order as $n => $idx ) {
				$c    = $this->comps[ $idx ];
				$meta = json_encode(
					[
						'type'     => $c['type'],
						'slug'     => clean_text( $c['slug'] ),
						'branch'   => clean_nullable( $c['branch'] ),
						'name'     => clean_nullable( $c['name'] ),
						'version'  => clean_nullable( $c['version'] ),
						'files'    => $c['files'],
						'errors'   => $c['errors'],
						'warnings' => $c['warnings'],
					],
					JSON_FLAGS
				);
				$write( ( $n ? ',' : '' ) . substr( $meta, 0, -1 ) . ',"findings":[' );
				$first = true;
				foreach ( [ "c$idx.e", "c$idx.w" ] as $spool ) {
					$this->copySpool( $this->work . '/' . $spool, $write, $first );
				}
				$write( ']}' );
			}

			$write( '],"not_checked":[' );
			$first = true;
			$this->copySpool( $this->work . '/not_checked', $write, $first );
			$write( "]}\n" );
		} catch ( Throwable $e ) {
			fclose( $out );
			@unlink( $tmp );
			throw $e;
		}

		if ( ! fclose( $out ) || ! @rename( $tmp, OUT_DIR . '/report.json' ) ) {
			throw new ToolError( 'could not write the report' );
		}
	}

	/** Appends a spool of `,{...}` items, dropping the leading comma of the first; then deletes it. */
	private function copySpool( string $file, callable $write, bool &$first ): void {
		if ( ! is_file( $file ) ) {
			return;
		}
		$in = fopen( $file, 'rb' );
		if ( false === $in ) {
			throw new ToolError( 'could not read the spool' );
		}
		if ( $first ) {
			fread( $in, 1 );
			$first = false;
		}
		while ( ! feof( $in ) ) {
			$chunk = fread( $in, BUFFER_MAX );
			if ( false === $chunk ) {
				throw new ToolError( 'could not read the spool' );
			}
			if ( '' !== $chunk ) {
				$write( $chunk );
			}
		}
		fclose( $in );
		@unlink( $file );
	}

	// ------------------------------------------------------------------ phpcs

	/**
	 * One PHPCS run under `timeout -s KILL` with the time left.
	 *
	 * @return array{ok:bool,timeout:bool,too_large:bool,unreadable:bool,rc:int,seconds:float,report:string}
	 */
	private function phpcs( array $paths, string $memory, string $tag, bool $stdin = false ): array {
		$report = $this->work . "/phpcs-$tag.out";
		$res    = [ 'ok' => false, 'timeout' => false, 'too_large' => false, 'unreadable' => false, 'rc' => -1, 'seconds' => 0.0, 'report' => $report ];

		$left = $this->deadline - microtime( true );
		if ( $left <= 0 ) {
			$res['timeout'] = true;
			return $res;
		}

		@unlink( $report );

		$cmd = [
			// The exact time left (busybox takes fractions), so no run finishes past the deadline.
			'timeout', '-s', 'KILL', sprintf( '%.3F', ceil( $left * 1000 ) / 1000 ),
			PHP_BINARY, '-d', 'memory_limit=' . $memory, '-d', 'display_errors=stderr', '-d', 'log_errors=0',
			PHPCS_BIN,
			'--standard=' . ( 'php' === $this->cfg['site_type'] ? 'PHPCompatibility' : 'PHPCompatibilityWP' ),
			'--runtime-set', 'testVersion', $this->cfg['version'],
			'--extensions=php', '--no-cache', '-q', '--no-colors', '--ignore-annotations',
			'--report=' . REPORT_CLASS, '--report-file=' . $report,
		];

		$in = [ 'file', '/dev/null', 'r' ];
		if ( $stdin ) {
			$in = open_regular( $paths[0] );
			if ( null === $in ) {
				$res['unreadable'] = true;
				return $res;
			}
			// PHPCS resolves --stdin-path and filters it by extension, so it must end in .php.
			$cmd[] = '--stdin-path=' . $paths[0] . ( $this->isPhpName( $paths[0] ) ? '' : '.php' );
			$cmd[] = '-';
		} else {
			$list = $this->work . '/phpcs.list';
			$this->put( $list, implode( "\n", $paths ) . "\n" );
			$cmd[] = '--file-list=' . $list;
		}

		$err = $this->cfg['debug'] ? STDERR : [ 'file', '/dev/null', 'w' ];
		$t   = hrtime( true );

		// Bounds what PHPCS can write (SIGXFSZ past the limit); set only around the fork.
		$fsize = $this->cfg['report_max'] + max( FSIZE_SLACK, count( $paths ) * HEADER_MAX );
		set_fsize( $fsize );
		$proc = proc_open( $cmd, [ 0 => $in, 1 => [ 'file', '/dev/null', 'w' ], 2 => $err ], $pipes );
		set_fsize( null );
		if ( is_resource( $in ) ) {
			fclose( $in );
		}
		if ( ! is_resource( $proc ) ) {
			throw new ToolError( 'could not start phpcs' );
		}
		$rc = proc_close( $proc );

		$res['rc']      = $rc;
		$res['seconds'] = ( hrtime( true ) - $t ) / 1e9;

		clearstatcache();
		$size = @filesize( $report );
		if ( false !== $size && $size >= $fsize ) {
			$res['too_large'] = true;
		} elseif ( $rc >= 0 && $rc <= 3 && false !== $size ) {
			$res['ok'] = true;
		}
		return $res;
	}

	// ------------------------------------------------------------------ misc

	/** Appends to a work file; a short write (full disk) is a tool error. */
	private function append( string $file, string $data ): void {
		if ( @file_put_contents( $file, $data, FILE_APPEND ) !== strlen( $data ) ) {
			throw new ToolError( 'could not write to the output directory' );
		}
	}

	private function put( string $file, string $data ): void {
		if ( @file_put_contents( $file, $data ) !== strlen( $data ) ) {
			throw new ToolError( 'could not write to the output directory' );
		}
	}

	private function flushList(): void {
		if ( '' === $this->listBuf ) {
			return;
		}
		if ( fwrite( $this->listFh, $this->listBuf ) !== strlen( $this->listBuf ) ) {
			throw new ToolError( 'could not write to the output directory' );
		}
		$this->listBuf = '';
	}

	private function makeWork(): void {
		$this->removeWork();
		if ( ! @mkdir( $this->work, 0700 ) ) {
			throw new ToolError( 'output directory not writable' );
		}
	}

	public function removeWork(): void {
		if ( is_resource( $this->listFh ) ) {
			fclose( $this->listFh );
			$this->listFh = null;
		}
		if ( '' === $this->work || ! is_dir( $this->work ) ) {
			return;
		}
		foreach ( (array) scandir( $this->work ) as $f ) {
			if ( '.' !== $f && '..' !== $f ) {
				@unlink( $this->work . '/' . $f );
			}
		}
		@rmdir( $this->work );
	}

	public function head( string $status ): array {
		return doc_head( $this->cfg, $status );
	}

	public function reduced( string $status ): array {
		$doc = $this->head( $status );

		$doc['safe_to_upgrade'] = null;
		return $doc;
	}

	private function debug( string $msg ): void {
		if ( $this->cfg['debug'] ) {
			fwrite( STDERR, sprintf( "[%7.2f] %s\n", microtime( true ) - $this->start, $msg ) );
		}
	}
}

/**
 * Streams a LinesReport file: validate() first, then peek()/take() each file's
 * header and read its messages with message(), all in report order.
 */
final class ReportReader {

	/** @var resource|null */
	private $fh;
	/** @var bool */
	private $valid = false;
	/** @var int */
	private $blocks = 0;
	/** @var array|null Header of the next block, read ahead. */
	private $next;
	/** @var int Messages of the taken block still unread. */
	private $pending = 0;
	/** @var bool A line without its newline was read (truncated file). */
	private $broken = false;

	public function __construct( string $file ) {
		$fh = @fopen( $file, 'rb' );
		if ( false === $fh ) {
			return;
		}
		$this->fh = $fh;
		// PHPCS ends even an empty report with a newline; zero bytes is a failed write.
		$st = fstat( $fh );
		if ( false !== $st && $st['size'] > 0 && $this->validate() ) {
			$this->valid = true;
			rewind( $this->fh );
			$this->next = $this->header();
		}
	}

	public function valid(): bool {
		return $this->valid;
	}

	public function blocks(): int {
		return $this->blocks;
	}

	/** Real file name of the next block, or null at the end. */
	public function peek(): ?string {
		$this->skipMessages();
		return null === $this->next ? null : $this->next['f'];
	}

	/** @return array{f:string,n:int,u:int} */
	public function take(): array {
		$this->skipMessages();
		$block         = $this->next;
		$this->pending = $block['n'];
		$this->next    = null;
		return $block;
	}

	public function skip(): void {
		$this->take();
		$this->skipMessages();
	}

	/** Next message of the taken block, or null when it has none left. */
	public function message(): ?array {
		if ( $this->pending <= 0 ) {
			return null;
		}
		$this->pending--;
		$m = $this->decode( $this->line() );
		if ( 0 === $this->pending ) {
			$this->next = $this->header();
		}
		return $m;
	}

	public function skipMessages(): void {
		while ( $this->pending > 0 ) {
			$this->pending--;
			$this->line();
		}
		if ( null === $this->next && null !== $this->fh && ! feof( $this->fh ) ) {
			$this->next = $this->header();
		}
	}

	public function close(): void {
		if ( null !== $this->fh ) {
			fclose( $this->fh );
			$this->fh = null;
		}
	}

	/** Checks the whole file: every header is followed by exactly its count of message lines. */
	private function validate(): bool {
		while ( true ) {
			$line = $this->line();
			if ( null === $line ) {
				return ! $this->broken;
			}
			if ( '' === $line ) {
				continue;
			}
			$h = $this->parseHeader( $line );
			if ( null === $h ) {
				return false;
			}
			$this->blocks++;
			for ( $i = 0; $i < $h['n']; $i++ ) {
				if ( null === $this->decode( $this->line() ) ) {
					return false;
				}
			}
		}
	}

	private function header(): ?array {
		while ( null !== ( $line = $this->line() ) ) {
			if ( '' !== $line ) {
				return $this->parseHeader( $line );
			}
		}
		return null;
	}

	private function parseHeader( string $line ): ?array {
		$h = json_decode( $line, true, 4 );
		if ( ! is_array( $h ) || ! isset( $h['f'], $h['n'], $h['u'] ) || ! is_string( $h['f'] ) || ! is_int( $h['n'] ) || $h['n'] < 0 ) {
			return null;
		}
		$name = base64_decode( $h['f'], true );
		if ( false === $name ) {
			return null;
		}
		return [ 'f' => $name, 'n' => $h['n'], 'u' => $h['u'] ? 1 : 0 ];
	}

	private function decode( ?string $line ): ?array {
		if ( null === $line ) {
			return null;
		}
		$m = json_decode( $line, true, 4, JSON_INVALID_UTF8_SUBSTITUTE );
		if ( ! is_array( $m ) || 5 !== count( $m ) || ! is_int( $m[0] ) || ! is_string( $m[2] ) || ! is_string( $m[3] ) || ! is_string( $m[4] ) ) {
			return null;
		}
		return $m;
	}

	/** One line without its newline; null at EOF, on a truncated or overlong line. */
	private function line(): ?string {
		if ( null === $this->fh ) {
			return null;
		}
		$line = fgets( $this->fh, LINE_MAX + 1 );
		if ( false === $line ) {
			return null;
		}
		if ( "\n" !== substr( $line, -1 ) ) {
			$this->broken = true;
			return null;
		}
		return substr( $line, 0, -1 );
	}
}

// -------------------------------------------------------------------- helpers

function doc_head( array $cfg, string $status ): array {
	$doc = [ 'v' => 1, 'status' => $status ];
	if ( 'estimate' === ( $cfg['mode'] ?? '' ) ) {
		$doc['estimate'] = true;
	}
	if ( '' !== $cfg['site'] ) {
		$doc['site'] = $cfg['site'];
	}
	$doc['target'] = $cfg['version'];
	if ( 'estimate' !== ( $cfg['mode'] ?? '' ) || 'ok' !== $status ) {
		$doc['safe_to_upgrade'] = null;
	}
	return $doc;
}

/**
 * Text from the site (paths, headers, messages) made safe to print: invalid
 * UTF-8, control, bidi and zero-width characters each become U+FFFD.
 */
function clean_text( string $s ): string {
	if ( ! mb_check_encoding( $s, 'UTF-8' ) ) {
		$s = (string) json_decode( (string) json_encode( $s, JSON_INVALID_UTF8_SUBSTITUTE ) );
	}
	return (string) preg_replace( '/[\x{00}-\x{1F}\x{7F}-\x{9F}\x{061C}\x{200B}-\x{200F}\x{2028}-\x{202E}\x{2060}-\x{2069}\x{FEFF}]/u', "\u{FFFD}", $s );
}

function clean_nullable( ?string $s ): ?string {
	return null === $s ? null : clean_text( $s );
}

/**
 * Opens a site file only when it is a regular file; non-blocking, so a FIFO
 * can't hang the entrypoint.
 *
 * @return resource|null
 */
function open_regular( string $path ) {
	$fh = @fopen( $path, 'rbn' );
	if ( false === $fh ) {
		return null;
	}
	$st = fstat( $fh );
	if ( false === $st || 0100000 !== ( $st['mode'] & 0170000 ) ) {
		fclose( $fh );
		return null;
	}
	return $fh;
}

/** First 8 KB of a regular file inside the mount, or null. */
function read_head( string $path ): ?string {
	$real = @realpath( $path );
	if ( false === $real || ( MOUNT_ROOT !== $real && 0 !== strpos( $real, MOUNT_ROOT . '/' ) ) ) {
		return null;
	}
	$fh = open_regular( $real );
	if ( null === $fh ) {
		return null;
	}
	$data = fread( $fh, 8192 );
	fclose( $fh );
	return false === $data ? null : $data;
}

function header_value( string $data, string $field ): ?string {
	if ( preg_match( '/^(?:[ \t]*<\?php)?[ \t\/*#@]*' . preg_quote( $field, '/' ) . ':(.*)$/mi', $data, $m ) ) {
		$value = trim( preg_replace( '/\s*(?:\*\/|\?>).*/', '', $m[1] ) );
		if ( '' !== $value ) {
			return $value;
		}
	}
	return null;
}

/** Sets the soft file size limit that children inherit; null restores the original. */
function set_fsize( ?int $bytes ): void {
	static $orig = null;
	if ( ! function_exists( 'posix_setrlimit' ) ) {
		return;
	}
	if ( null === $orig ) {
		$lim  = posix_getrlimit();
		$orig = [ $lim['soft filesize'] ?? 'unlimited', $lim['hard filesize'] ?? 'unlimited' ];
		$orig = array_map(
			static function ( $v ) {
				return 'unlimited' === $v ? POSIX_RLIMIT_INFINITY : (int) $v;
			},
			$orig
		);
	}
	$soft = null === $bytes ? $orig[0] : $bytes;
	if ( POSIX_RLIMIT_INFINITY !== $orig[1] && ( POSIX_RLIMIT_INFINITY === $soft || $soft > $orig[1] ) ) {
		$soft = $orig[1];
	}
	@posix_setrlimit( POSIX_RLIMIT_FSIZE, $soft, $orig[1] );
}

function tool_versions( string $image ): array {
	$out  = [ 'phpcs' => null, 'phpcompatibility' => null, 'phpcompatibility_wp' => null ];
	$map  = [
		'squizlabs/php_codesniffer'            => 'phpcs',
		'phpcompatibility/php-compatibility'   => 'phpcompatibility',
		'phpcompatibility/phpcompatibility-wp' => 'phpcompatibility_wp',
	];
	$data = json_decode( (string) @file_get_contents( TOOL_DIR . '/vendor/composer/installed.json' ), true );
	foreach ( $data['packages'] ?? [] as $p ) {
		if ( isset( $map[ $p['name'] ] ) ) {
			$out[ $map[ $p['name'] ] ] = ltrim( $p['version'], 'v' );
		}
	}
	if ( '' !== $image ) {
		$out['image'] = $image;
	}
	return $out;
}

function odd_path( string $path ): bool {
	return trim( $path ) !== $path || false !== strpbrk( $path, "\r\n" );
}

/** @return int|float */
function cpu_count() {
	$max = @file_get_contents( '/sys/fs/cgroup/cpu.max' );
	if ( false !== $max && preg_match( '/^(\d+)\s+(\d+)/', $max, $m ) && (int) $m[2] > 0 ) {
		$n = (int) $m[1] / (int) $m[2];
		return $n == (int) $n ? (int) $n : round( $n, 2 );
	}
	$info = (string) @file_get_contents( '/proc/cpuinfo' );
	return max( 1, preg_match_all( '/^processor\s*:/m', $info ) );
}

function load_average(): ?float {
	$load = @file_get_contents( '/proc/loadavg' );
	return false === $load ? null : (float) strtok( $load, ' ' );
}

function env_int( string $name, int $default, int $min = 1 ): int {
	$v = getenv( $name );
	if ( false === $v || '' === $v ) {
		return $default;
	}
	if ( ! ctype_digit( $v ) || (int) $v < $min ) {
		throw new BadArgs( "$name must be an integer >= $min" );
	}
	return (int) $v;
}

function env_float( string $name, float $default ): float {
	$v = getenv( $name );
	if ( false === $v || '' === $v ) {
		return $default;
	}
	if ( ! is_numeric( $v ) || ! is_finite( (float) $v ) || (float) $v < 0 ) {
		throw new BadArgs( "$name must be a finite non-negative number" );
	}
	return (float) $v;
}

function env_memory( string $name, string $default ): string {
	$v = getenv( $name );
	if ( false === $v || '' === $v ) {
		return $default;
	}
	if ( ! preg_match( '/^\d+[KMG]?\z/', $v ) ) {
		throw new BadArgs( "$name must look like 448M" );
	}
	return $v;
}

function parse_args( array $argv, array &$cfg ): void {
	$cfg['mode']      = $argv[0] ?? '';
	$cfg['site_type'] = $argv[1] ?? '';
	$cfg['path']      = $argv[2] ?? '';
	$cfg['version']   = (string) ( $argv[3] ?? '' );
	$timeout          = $argv[4] ?? '';

	if ( ! in_array( $cfg['mode'], [ 'scan', 'estimate' ], true ) ) {
		throw new BadArgs( 'mode must be scan or estimate' );
	}
	if ( ! in_array( $cfg['site_type'], [ 'wp', 'php' ], true ) ) {
		throw new BadArgs( 'site type must be wp or php' );
	}
	$path = rtrim( $cfg['path'], '/' );
	if ( ( MOUNT_ROOT !== $path && 0 !== strpos( $path, MOUNT_ROOT . '/' ) ) || preg_match( '#/\.\.?(/|\z)|//|[\x00-\x1F\x7F]#', $path ) ) {
		throw new BadArgs( 'path must be an absolute path under ' . MOUNT_ROOT );
	}
	$cfg['path'] = $path;
	if ( ! preg_match( '/^\d+\.\d+\z/', $cfg['version'] ) ) {
		throw new BadArgs( 'version must look like 8.4' );
	}
	if ( 'scan' === $cfg['mode'] || '' !== $timeout ) {
		if ( ! ctype_digit( (string) $timeout ) || (int) $timeout < 1 ) {
			throw new BadArgs( 'timeout must be a positive integer' );
		}
	}
	$cfg['timeout'] = (int) $timeout;

	$cfg['batch_size']        = env_int( 'COMPAT_BATCH_SIZE', 200 );
	$cfg['batch_memory']      = env_memory( 'COMPAT_BATCH_MEMORY', '448M' );
	$cfg['file_memory']       = env_memory( 'COMPAT_FILE_MEMORY', $cfg['batch_memory'] );
	$cfg['retry_memory']      = env_memory( 'COMPAT_RETRY_MEMORY', '960M' );
	$cfg['estimate_timeout']  = env_int( 'COMPAT_ESTIMATE_TIMEOUT', 120 );
	$cfg['seconds_per_batch'] = env_float( 'COMPAT_SECONDS_PER_BATCH', 0.1 );
	$cfg['low_factor']        = env_float( 'COMPAT_LOW_FACTOR', 0.8 );
	$cfg['high_factor']       = env_float( 'COMPAT_HIGH_FACTOR', 1.5 );
	$cfg['report_max']        = env_int( 'COMPAT_REPORT_MAX', REPORT_MAX, 1024 );
	if ( $cfg['low_factor'] > 1 || $cfg['high_factor'] < 1 ) {
		throw new BadArgs( 'COMPAT_LOW_FACTOR must be at most 1 and COMPAT_HIGH_FACTOR at least 1' );
	}
}

function emit( array $doc, int $code, bool $report ): void {
	global $emitted;
	$emitted = true;
	$json    = json_encode( $doc, JSON_FLAGS ) . "\n";
	if ( $report ) {
		$tmp = OUT_DIR . '/report.json.tmp';
		if ( ! ( is_dir( OUT_DIR ) && is_writable( OUT_DIR ) && strlen( $json ) === @file_put_contents( $tmp, $json ) && @rename( $tmp, OUT_DIR . '/report.json' ) ) ) {
			@unlink( $tmp );
			// The report is part of the result: without it only a tool_error stands.
			if ( 'tool_error' !== $doc['status'] ) {
				$doc['status'] = 'tool_error';
				$doc['detail'] = 'could not write the report';
				$json          = json_encode( $doc, JSON_FLAGS ) . "\n";
				$code          = 1;
			}
		}
	}
	fwrite( STDOUT, $json );
	exit( $code );
}

// ----------------------------------------------------------------------- main

// No core dumps of scanned code, for this process and every PHPCS run.
if ( function_exists( 'posix_setrlimit' ) ) {
	@posix_setrlimit( POSIX_RLIMIT_CORE, 0, 0 );
}

$emitted = false;
$scanner = null;
$cfg     = [
	'mode'    => '',
	'version' => '',
	'site'    => (string) getenv( 'COMPAT_SITE' ),
	'image'   => (string) getenv( 'COMPAT_IMAGE' ),
	'debug'   => '1' === getenv( 'COMPAT_DEBUG' ),
];

$tool_error = static function ( string $detail ) use ( &$cfg ): array {
	$doc = doc_head( $cfg, 'tool_error' );

	$doc['detail'] = $detail;
	return $doc;
};

// A fatal error (e.g. memory) still ends with one tool_error document on stdout.
$reserve = str_repeat( ' ', 262144 );
register_shutdown_function(
	static function () use ( &$reserve, &$scanner, &$cfg, $tool_error ) {
		global $emitted;
		$reserve = null;
		$e       = error_get_last();
		if ( $emitted || null === $e || ! in_array( $e['type'], [ E_ERROR, E_CORE_ERROR, E_COMPILE_ERROR, E_PARSE ], true ) ) {
			return;
		}
		if ( $scanner instanceof Scanner ) {
			$scanner->removeWork();
		}
		emit( $tool_error( 'internal error: ' . clean_text( $e['message'] ) ), 1, 'scan' === $cfg['mode'] );
	}
);

try {
	parse_args( array_slice( $argv, 1 ), $cfg );
} catch ( BadArgs $e ) {
	emit( $tool_error( 'bad arguments: ' . $e->getMessage() ), 2, false );
}

$isScan = 'scan' === $cfg['mode'];
if ( $isScan && ( ! is_dir( OUT_DIR ) || ! is_writable( OUT_DIR ) ) ) {
	emit( $tool_error( 'output directory not writable' ), 1, false );
}

$scanner = new Scanner( $cfg );
try {
	$doc = $scanner->run();
	emit( $doc, 0, $isScan && 'ok' !== $doc['status'] );
} catch ( TimedOut $e ) {
	$scanner->removeWork();
	emit( $tool_error( $e->getMessage() ), 1, $isScan );
} catch ( Throwable $e ) {
	$scanner->removeWork();
	$msg = $e instanceof ToolError ? $e->getMessage() : 'internal error: ' . clean_text( $e->getMessage() );
	emit( $tool_error( $msg ), 1, $isScan );
}
