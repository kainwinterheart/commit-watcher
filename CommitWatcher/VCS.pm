package CommitWatcher::VCS;

use strict;
use warnings;

use Mouse;

use File::Spec ();

use boolean;

use namespace::autoclean;


has 'wcpath' => ( is => 'ro', isa => 'Str', required => true );


sub to_abs {

    my ( $self, $file ) = @_;

    $file = File::Spec -> rel2abs( $file, $self -> wcpath() );
    $file = File::Spec -> canonpath( $file );

    return $file;
}

sub to_rel {

    my ( $self, $file ) = @_;

    $file = File::Spec -> abs2rel( $file, $self -> wcpath() );
    $file = File::Spec -> canonpath( $file );

    return $file;
}

=head2 get_changes( Str $revision )

=cut

sub get_changes;

=head2 patch( Str $diff_contents )

=cut

sub patch;

=head2 next_rev( Str $revision )

=cut

sub next_rev;

=head2 commit()

=cut

sub commit;

=head2 clone( Str $url )

=cut

sub clone;

=head2 update( Maybe[Str] $revision )

=cut

sub update;

=head2 get_base_rev()

=cut

sub get_base_rev;


sub trace {

    my ( $self, @arr ) = @_;

    print STDERR join( ' ', '#', @arr ), "\n";

    return;
}

__PACKAGE__ -> meta() -> make_immutable();

1;

__END__
