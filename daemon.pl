#!/usr/bin/perl

use strict;
use warnings;
use Proc::Daemon;

Proc::Daemon::Init;

my $continue = 1;
$SIG{TERM} = sub { $continue = 0 };

while ($continue)
{
    #do stuff
    sleep(10);
}
