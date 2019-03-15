#!/bin/perl

$oldest_version = shift;
$newest_version = shift;

use File::Basename;
$_dir_ = dirname(__FILE__);

require $_dir_."/history.pm";

sub explore {
	my ($key, $last) = @_;
	return [$key] if ($key eq $last);
	foreach $successor (@{$objects{$key}{"Successors"}}) {
	    $ret = explore($successor, $last);
	    if ($ret) {
		unshift @{$ret}, $key;
		return $ret;
	    }
	}
	return 0;

}
foreach $key (@{explore($oldest_version, $newest_version)}) {
	print "$key\n";
}
