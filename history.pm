#!/bin/perl

# the script history.pm is a perl module that reads the history of a versioned object on stdin.
# This builds the variables:
# - %objects
#      the hash indexed by the objectname stores "records" with the following properties of the object's version:
#         project: unused, filled with the instance part of the objectname
#         Owner: unix account used to create the object's version
#         Created: creation date
#         Task: string containing a comma separated list of tasks
#         Comment: array of strings
#         Predecessors: array of objectnames of predecessors
#         Successors: array of objectnames of successors
# - @firts
#         array of objectnames that have no predecessors
# - @lasts
#         array of objectnames that have no successors

# this can be used from commandline. For example, on base arh:
# ccm history ADS.doc-5:fmdoc:ARH#2 | perl -mhistory -e 'print join(", ", keys %objects), "\n"'

while(<STDIN>) {
  chomp;
  next if (/\*+/);
  if (/^Object:\s*(\S+) \(([^:]*):([^)]*)\)/) {
    $object = $1;
    $object = "$object:$2:$3" if (!grep(/:$2:/, $object));
    $objects{$object}{"project"} = $3;
  }elsif(/^(Owner|Created|Task): *(\S.+)/) {
    $objects{$object}{$1} = $2;
  }elsif(/^(Comment|Predecessors|Successors):\s*(\S.*|)$/){
    $typename = $1;
    push(@{$objects{$object}{$typename}}, $2) if ($2) ;
  }else{
    s/^\s*//;
    s/<void>//;
    push(@{$objects{$object}{$typename}}, $_) if ($_);
  }
}

# ensure that links to a predecessor (or successor) have always a symetric link to ourself from the predessor (or successor).
foreach $k (keys %objects) {
  foreach $p (@{$objects{$k}{"Predecessors"}}) {
       push(@{$objects{$p}{"Successors"}}, $k) if(!grep($k, @{$objects{$p}{"Successors"}})) ;
  }
  foreach $s (@{$objects{$k}{"Successors"}}) {
       push(@{$objects{$s}{"Predecessors"}}, $k) if(!grep($k, @{$objects{$s}{"Predecessors"}})) ;
  }
}

# @firsts is the array of objectnames who have no predecessors
foreach $k (keys %objects) {
  if ($#{$objects{$k}{"Predecessors"}} < 0) {
       push (@firsts, $k);
  }
}
# @lasts is the array of objectnames who have no successors
foreach $k (keys %objects) {
  if ($#{$objects{$k}{"Successors"}} < 0) {
       push (@lasts, $k);
  }
}

# cut links so that there is a single path between an object without successor and any of its ancestors.
if ($enable_removecyclic) {
	foreach $item (@lasts) {
		while (removecyclic($item)) {
		}
	}
}

sub removecyclic {
	my ($key, $alreadyseen) = @_;
	$alreadyseen = \%alreadyseen unless($alreadseen);
	$alreadyseen->{$key} = 1;
	foreach $predessor (@{$objects{$key}{"Predecessors"}}) {
		if ($alreadyseen->{$predessor}) {
                        @{$objects{$key}{"Predecessors"}} = grep { $_ ne $predessor } @{$objects{$key}{"Predecessors"}};
			@{$objects{$predessor}{"Successors"}} = grep { $_ ne $key } @{$objects{$predessor}{"Successors"}};
			return 1;
		}
		removecyclic($predessor, $alreadyseen);
	}
	return 0;
}

1;
