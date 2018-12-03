#!/bin.perl

while(<STDIN>) {
  chomp;
  next if (/\*+/);
  if (/^Object: *(\S+) \(project:([^)]*)\)/) {
    $object = $1;
    $objects{$object}{"project"} = $2;
  }elsif(/^(Owner|Created|Task): *(\S.+)/) {
    $objects{$object}{$1} = $2;
  }elsif(/^(Comment|Predecessors|Successors): *(\S*)/){
    $typename = $1;
    $objects{$object}{$typename} = [];
    push(@{$objects{$object}{$typename}}, $2) if ($2) ;
  }else{
    s/^\s*//;
    push(@{$objects{$object}{$typename}}, $_) if ($_);
  }
}

foreach $k (keys %objects) {
  if ($#{$objects{$k}{"Predecessors"}} < 0) {
    push (@firsts, $k);
  }
}

sub followtree {
  print STDERR "$tirets $key\n";
  foreach $successor (@{$objects{$key}{"Successors"}}) {
    followtree($successor, $tirets.'-');
  }
}
foreach $first (@firsts) {
  followtree($first, '-');
}
