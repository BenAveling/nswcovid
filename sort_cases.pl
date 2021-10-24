#!/usr/bin/perl -w
# ######################################################################
# Copyright (c) 2021 Ben Aveling.
# ######################################################################
# This script ...
#
my $usage = qq{Usage:
  perl sort_cases.pl from to
};
# ######################################################################
# History:
# 2021-MM-DD Created. 
# ######################################################################

# ####
# VARS
# ####

use strict;
use autodie;

require 5.022; # lower would probably work, but has not been tested

# use Carp;
# use Data::Dumper;
# print Dumper $data;
# use FindBin;
# use lib "$FindBin::Bin/libs";
# use Time::HiRes qw (sleep);
# alarm 10; 

# ####
# SUBS
# ####

# ####
# MAIN
# ####

die $usage if !@ARGV;
# this next line is useful on dos
# @ARGV = map {glob($_)} @ARGV;

my $from_file=shift or die;
my $to_file=shift or die;

open(my $FROM,$from_file) or die "Can't read $from_file: $!";
open(my $TO,">",$to_file) or die "Can't write $to_file: $!";
binmode($TO);
my @in=<$FROM>;
print $TO shift @in;
print $TO sort @in;

print STDERR "Done\n";

