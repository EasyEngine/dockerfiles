<?php
// Copies the first wp-includes/*.php files, in byte order, until they reach 1 MiB.
[ , $src, $dst ] = $argv;
$files = glob( $src . '/*.php' );
sort( $files, SORT_STRING );
mkdir( $dst . '/sample', 0755, true );
touch( $dst . '/empty.php' );
$list  = [];
$total = 0;
foreach ( $files as $f ) {
	if ( $total >= 1048576 ) {
		break;
	}
	copy( $f, $dst . '/sample/' . basename( $f ) );
	$list[] = $dst . '/sample/' . basename( $f );
	$total += filesize( $f );
}
file_put_contents( $dst . '/sample.list', implode( "\n", $list ) . "\n" );
fwrite( STDERR, count( $list ) . " files, $total bytes\n" );
