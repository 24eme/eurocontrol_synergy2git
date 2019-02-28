#!/bin/perl

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

foreach $k (keys %objects) {
  foreach $p (@{$objects{$k}{"Predecessors"}}) {
       push(@{$objects{$p}{"Successors"}}, $k) if(!grep($k, @{$objects{$p}{"Successors"}})) ;
  }
  foreach $s (@{$objects{$k}{"Successors"}}) {
       push(@{$objects{$s}{"Predessors"}}, $k) if(!grep($k, @{$objects{$s}{"Predessors"}})) ;
  }
}

foreach $k (keys %objects) {
  if ($#{$objects{$k}{"Predecessors"}} < 0) {
       push (@firsts, $k);
  }
}
foreach $k (keys %objects) {
  if ($#{$objects{$k}{"Successors"}} < 0) {
       push (@lasts, $k);
  }
}

foreach $item (@lasts) {
	while (removecyclic($item)) {
	}
}

sub removecyclic {
	my ($key, $alreadyseen) = @_;
	$alreadyseen = \%alreadyseen unless($alreadseen);
	$alreadyseen->{$key} = 1;
	foreach $predessor (@{$objects{$key}{"Predessors"}}) {
		if ($alreadyseen->{$predessor}) {
                        @{$objects{$key}{"Predessors"}} = grep { $_ ne $predessor } @{$objects{$key}{"Predessors"}};
			@{$objects{$key}{"Successors"}} = grep { $_ ne $key } @{$objects{$predessor}{"Successors"}};
			return 1;
		}
		removecyclic($predessor, $alreadyseen);
	}
	return 0;
}

1;
