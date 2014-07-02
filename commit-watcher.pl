#!/usr/bin/perl

use strict;
use warnings;

package commit_watcher_bin;

use FindBin '$Bin';

use lib $Bin;

use CommitWatcher ();

use Carp 'confess';

$SIG{ __DIE__ } = \&confess;

CommitWatcher -> new( config => \@ARGV ) -> process();

exit 0;
