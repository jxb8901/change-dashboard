#!/usr/bin/env perl

use strict;
use warnings;
use Time::HiRes qw(sleep time);

my $count = $ENV{LHC_EVENT_COUNT} || 0;
my $rate = $ENV{LHC_EVENT_RATE} || 1;
$| = 1;

for my $sequence (1 .. $count) {
    printf "event-%04d %.6f\n", $sequence, time();
    sleep(1 / $rate) if $sequence < $count;
}
