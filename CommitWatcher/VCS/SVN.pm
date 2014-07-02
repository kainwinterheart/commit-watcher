package CommitWatcher::VCS::SVN;

use strict;
use warnings;

use Mouse;

use SVN::Client ();

use File::Temp 'tmpnam';

use List::Util 'min';
use List::MoreUtils 'uniq';

use String::ShellQuote 'shell_quote';

use boolean;

use namespace::autoclean;

extends 'CommitWatcher::VCS';

has 'backend' => ( is => 'ro', isa => 'SVN::Client', init_arg => undef, lazy => true, builder => 'build_backend' );

has 'head_rev' => ( is => 'ro', isa => 'Str', init_arg => undef, lazy => true, builder => 'build_head_rev' );

after [ 'update', 'diff', 'add', 'commit', 'get_base_rev', 'build_head_rev' ] => sub {

    my ( $self ) = @_;

    $self -> backend() -> pool() -> clear();
};


sub build_backend {

    my ( $self ) = @_;

    return SVN::Client -> new();
}

sub next_rev {

    my ( $self, $rev ) = @_;

    return ( ( $rev >= $self -> head_rev() ) ? undef : ( $rev + 1 ) );
}

sub get_changes {

    my ( $self, $rev ) = @_;

    return $self -> diff( $rev );
}

sub update {

    my ( $self, $rev ) = @_;

    $rev //= 'HEAD';

    my $file = $self -> wcpath();

    $self -> trace( 'svn up -r', $rev, $file );

    $self -> backend() -> update( $file, $rev, true );

    return;
}

sub add {

    my ( $self, $file ) = @_;

    $self -> trace( 'svn add', $file );

    $self -> backend() -> add( $file, true );

    return;
}

sub patch {

    my ( $self, $diff ) = @_;

    my ( $fh, $diff_file ) = tmpnam();

    print $fh $diff;

    close( $fh );

    my $cmd = sprintf( 'patch -s -p0 < %s', shell_quote( $diff_file ) );

    $self -> trace( $cmd );

    my $code = system( $cmd );

    unlink( $diff_file );

    if( $code >> 8 ) {

        die sprintf( 'Patch failed with code %d', $code );
    }

    return;
}

sub diff {

    my ( $self, $rev ) = @_;

    return $self -> _diff( $self -> wcpath(), $rev - 1, $rev );
}

sub _diff {

    my ( $self, $file, $from, $to ) = @_;

    $file = $self -> to_rel( $file );

    $file = '' if( $file eq '.' );

    my ( $fh, $diff_file ) = tmpnam();

    $self -> trace( 'svn diff -r', "$from:$to", $file );

    $self -> backend() -> diff( [], $file, $from, $file, $to, true, false, false, $fh, *STDERR );

    seek( $fh, 0, 0 );

    my $out = join( '', <$fh> );

    close( $fh );
    unlink( $diff_file );

    return $out;
}

sub commit {

    my ( $self ) = @_;

    my $file = $self -> wcpath();

    $self -> trace( 'svn ci', $file );

    $self -> backend() -> commit( [ $file ], false );

    return;
}

sub clone {

    my ( $self, $url ) = @_;

    my $path = $self -> wcpath();

    $self -> trace( 'svn co', $url, $path );

    $self -> backend() -> checkout( $url, $path, 'HEAD', true );

    return;
}

sub get_base_rev {

    my ( $self ) = @_;

    my $file      = $self -> wcpath();
    my $base_rev  = 'BASE';
    my $info_func = sub {

        $base_rev = $_[ 1 ] -> rev();
    };

    $self -> backend() -> info( $file, undef, undef, $info_func, false );

    return $base_rev;
}

sub build_head_rev {

    my ( $self ) = @_;

    my $file      = $self -> wcpath();
    my $base_rev  = 'HEAD';
    my $info_func = sub {

        $base_rev = $_[ 1 ] -> rev();
    };

    $self -> backend() -> info( $file, 'HEAD', 'HEAD', $info_func, false );

    return $base_rev;
}


__PACKAGE__ -> meta() -> make_immutable();

1;

__END__
