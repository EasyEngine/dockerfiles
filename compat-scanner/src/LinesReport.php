<?php
/**
 * PHPCS report: per processed file, one header line then one line per message.
 *
 * Header: {"f":"<base64 file name>","n":<message count>,"u":0|1}; "u" is 1 when
 * PHPCS couldn't tokenize or process the file. Each message line is
 * [line, column, type, source, message]. One line per message lets the
 * entrypoint stream a report without holding a file's findings in memory.
 * Clean files get a header too, so the caller knows which files PHPCS finished.
 */

namespace EasyEngine\CompatScanner;

use PHP_CodeSniffer\Files\File;
use PHP_CodeSniffer\Reports\Report;

class LinesReport implements Report {

	const FLAGS = JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE;

	// Messages can quote code of any length; the entrypoint reads lines of at most 1 MiB (LINE_MAX),
	// and 64 KiB stays below that even when every byte is escaped as \u00XX.
	const MESSAGE_MAX = 65536;

	public function generateFileReport( array $report, File $phpcsFile, bool $showSources = false, int $width = 80 ) {
		$count       = 0;
		$unparseable = 0;
		foreach ( $report['messages'] as $columns ) {
			foreach ( $columns as $list ) {
				foreach ( $list as $message ) {
					$count++;
					if ( 0 === strpos( $message['source'], 'Internal.Tokenizer.Exception' ) || 0 === strpos( $message['source'], 'Internal.Exception' ) ) {
						$unparseable = 1;
					}
				}
			}
		}

		echo json_encode( [ 'f' => base64_encode( $report['filename'] ), 'n' => $count, 'u' => $unparseable ] ), "\n";
		foreach ( $report['messages'] as $line => $columns ) {
			foreach ( $columns as $column => $list ) {
				foreach ( $list as $message ) {
					$text = $message['message'];
					if ( strlen( $text ) > self::MESSAGE_MAX ) {
						$text = substr( $text, 0, self::MESSAGE_MAX ) . '…';
					}
					echo json_encode( [ (int) $line, (int) $column, $message['type'], $message['source'], $text ], self::FLAGS ), "\n";
				}
			}
		}

		return true;
	}

	public function generate( string $cachedData, int $totalFiles, int $totalErrors, int $totalWarnings, int $totalFixable, bool $showSources = false, int $width = 80, bool $interactive = false, bool $toScreen = true ) {
		echo $cachedData;
	}
}
