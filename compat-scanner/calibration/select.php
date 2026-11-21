<?php
// Copies the first wp-includes/*.php files, in byte order, until they reach 1 MiB.
// Any failure fails the image build, so an incomplete sample is never published.
function fail( string $msg ): void {
	fwrite( STDERR, "select.php: $msg\n" );
	exit( 1 );
}

[ , $src, $dst ] = $argv;
$files = glob( $src . '/*.php' );
if ( ! $files ) {
	fail( "no PHP files in $src" );
}
sort( $files, SORT_STRING );
if ( ! mkdir( $dst . '/sample', 0755, true ) || ! touch( $dst . '/empty.php' ) ) {
	fail( "could not create $dst/sample or $dst/empty.php" );
}
$list  = [];
$total = 0;
foreach ( $files as $f ) {
	if ( $total >= 1048576 ) {
		break;
	}
	$to = $dst . '/sample/' . basename( $f );
	if ( ! copy( $f, $to ) ) {
		fail( "could not copy $f" );
	}
	$list[] = $to;
	$total += filesize( $f );
}
$data = implode( "\n", $list ) . "\n";
if ( file_put_contents( $dst . '/sample.list', $data ) !== strlen( $data ) ) {
	fail( "could not write $dst/sample.list" );
}
fwrite( STDERR, count( $list ) . " files, $total bytes\n" );
