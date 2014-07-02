package CommitWatcher;

use strict;
use warnings;

use Mouse;

use YAML ();
use File::Spec ();
use File::Slurp 'slurp', 'write_file';
use Getopt::Long 'GetOptionsFromArray';
use Module::Load 'load';
use Cwd 'getcwd';

use namespace::autoclean;
use boolean;

use constant {

    FN_STATE => 'state.yaml',
    DN_MASTER => 'master',
    DN_BRANCH => 'branch',
};


has 'workdir' => ( is => 'ro', isa => 'Str', default => sub{ getcwd() } );

has 'state_file_name' => ( is => 'ro', isa => 'Str', init_arg => undef, lazy => true, builder => 'build_state_file_name' );

has '_config' => ( is => 'ro', isa => 'ArrayRef', required => true, init_arg => 'config' );

has 'config' => ( is => 'ro', isa => 'HashRef', init_arg => undef, lazy => true, builder => 'load_config' );

has 'state' => ( is => 'ro', isa => 'HashRef', init_arg => undef, lazy => true, builder => 'load_state' );

has 'master_vcs' => ( is => 'ro', isa => 'CommitWatcher::VCS', init_arg => undef, lazy => true, builder => 'load_master_vcs' );

has 'branch_vcs' => ( is => 'ro', isa => 'CommitWatcher::VCS', init_arg => undef, lazy => true, builder => 'load_branch_vcs' );


sub sset {

    my ( $self, $key, $value ) = @_;

    return $self -> state() -> { $key } = $value;
}

sub sget {

    my ( $self, $key ) = @_;

    return $self -> state() -> { $key };
}

sub cget {

    my ( $self, $key ) = @_;

    return $self -> config() -> { $key };
}

sub load_master_vcs {

    my ( $self ) = @_;

    return $self -> load_vcs( $self -> cget( 'master-vcs' ), DN_MASTER );
}

sub load_branch_vcs {

    my ( $self ) = @_;

    return $self -> load_vcs( $self -> cget( 'branch-vcs' ), DN_BRANCH );
}

sub load_vcs {

    my ( $self, $vcs_name, $vcs_path ) = @_;

    $vcs_path = File::Spec -> catfile( $self -> cget( 'root' ), $vcs_path );

    my $base = sprintf( '%s::VCS', ref( $self ) );
    my $vcs  = sprintf( '%s::%s', $base, $vcs_name );

    if( eval{ load( $vcs ); 1 } ) {

        if( $vcs -> isa( $base ) ) {

            return $vcs -> new( wcpath => $vcs_path );
        }

    } else {

        warn $@;
    }

    die sprintf( 'Unknown VCS plugin: %s', $vcs );
}

sub build_state_file_name {

    my ( $self ) = @_;

    return File::Spec -> catfile( $self -> cget( 'root' ), FN_STATE );
}

sub load_state {

    my ( $self ) = @_;

    my $state_file = $self -> state_file_name();

    return {} unless( -e $state_file );

    return YAML::Load( scalar( slurp( $state_file ) ) );
}

sub write_state {

    my ( $self ) = @_;

    my $data = YAML::Dump( $self -> state() );

    write_file( $self -> state_file_name(), {
        atomic => 1,
        buf_ref => \$data,
        binmode => ':utf8',
    } );

    return;
}

sub load_config {

    my ( $self ) = @_;

    my %config = ();

    GetOptionsFromArray(
        $self -> _config(),
        'master=s' => \$config{ 'master' },
        'branch=s' => \$config{ 'branch' },
        'master-vcs=s' => \$config{ 'master-vcs' },
        'branch-vcs=s' => \$config{ 'branch-vcs' },
        'root=s' => \$config{ 'root' },
    );

    $config{ 'root' } = File::Spec -> rel2abs( $config{ 'root' }, $self -> workdir() );

    return \%config;
}

sub init {

    my ( $self ) = @_;

    my $root = $self -> cget( 'root' );

    foreach my $spec ( 'master', 'branch' ) {

        my $vcs_method = sprintf( '%s_vcs', $spec );

        my $vcs = $self -> $vcs_method();
        my $rev = $self -> sget( sprintf( 'last_%s', $spec ) );

        if( -e $vcs -> wcpath() ) {

            chdir( $vcs -> wcpath() );

            $vcs -> update( ( defined( $rev ) ? $rev : () ) );

            chdir( $self -> workdir() );

        } else {

            $vcs -> clone( $self -> cget( $spec ) );

            if( defined $rev ) {

                chdir( $vcs -> wcpath() );

                $vcs -> update( $rev );

                chdir( $self -> workdir() );
            }
        }
    }

    return;
}

sub process {

    my ( $self ) = @_;

    $self -> init();

    my $last_master = $self -> sget( 'last_master' );
    my $master_vcs  = $self -> master_vcs();
    my $branch_vcs  = $self -> branch_vcs();

    $last_master //= $master_vcs -> get_base_rev();

    chdir( $master_vcs -> wcpath() );

    while( defined( my $next_master = $master_vcs -> next_rev( $last_master ) ) ) {

        my $diff = $master_vcs -> get_changes( $next_master );

        chdir( $branch_vcs -> wcpath() );

        $branch_vcs -> patch( $diff ) if $diff;

        $last_master = $self -> sset( last_master => $next_master );
        $self -> write_state();

        chdir( $master_vcs -> wcpath() );
    }

    chdir( $branch_vcs -> wcpath() );

    $branch_vcs -> commit();

    if( $last_master ne ( $self -> sget( 'last_master' ) // '' ) ) {

        $last_master = $self -> sset( last_master => $last_master );
        $self -> write_state();
    }

    chdir( $self -> workdir() );

    return;
}


__PACKAGE__ -> meta() -> make_immutable();

1;

__END__
