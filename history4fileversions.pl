#!/bin/perl

# the script history4fileversions.pl takes as parameters two objectnames (the oldest and the newest)
# and reads on stdin the history of a versioned object.
# It searches for a path between the two versions.
#
# If such a path is found, it is written on stdout (one objectname per line).
# for example (on base arh):
# $ ccm history ESCAPE_Supervision-ACE2015C_V2.2:project:ARH#1 | history4fileversions.pl ESCAPE_Supervision-ACE2011B_20111220:project:ARH#1 ESCAPE_Supervision-ACE2015C_V2.2:project:ARH#1
# ESCAPE_Supervision-ACE2011B_20111220:project:ARH#1
# ESCAPE_Supervision-ACE2012A_20130114:project:ARH#1
# ESCAPE_Supervision-ACE2012A_20130422:project:ARH#1
# ESCAPE_Supervision-ACE2012B_20131115:project:ARH#1
# ESCAPE_Supervision-ACE2012B_20131205:project:ARH#1
# ESCAPE_Supervision-ACE2013A_20141031:project:ARH#1
# ESCAPE_Supervision-ACE2015A_20150210:project:ARH#1
# ESCAPE_Supervision-ACE2015B_20151113:project:ARH#1
# ESCAPE_Supervision-ACE2015C_20160212:project:ARH#1
# ESCAPE_Supervision-ACE2015C_V2.1:project:ARH#1
# ESCAPE_Supervision-ACE2015C_V2.2:project:ARH#1
# If path is not found, it does not produce any output

$oldest_version = shift;
$newest_version = shift;

use File::Basename;
$_dir_ = dirname(__FILE__);

require $_dir_."/history.pm";

if ($oldest_version eq '-n') {
		$oldest_version = $firsts[0];
}

sub explore {
        my ($key, $last) = @_;
        return [$key] if ($key eq $last);
        foreach $successor (@{$objects{$key}{"Successors"}}) {
            $ret = explore($successor, $last);
            unshift @{$ret}, $key;
            return $ret;
        }
        return [$key] ;

}
foreach $key (@{explore($oldest_version, $newest_version)}) {
        print "$key\n";
}
