#!/bin/perl

$folder = shift;
$folder = "repo" if (!$folder);
$ccm_cmd = shift;
$ccm_cmd = "ccm" if (!$ccm_cmd);
$subadds = shift;

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

sub key2tagname {
  my ($key) = @_;
  $key =~ s/[#:]/_/g;
  return $key;
}

sub followtree {
  my ($key, $tirets) = @_;
  my $cauthor, $cdate, $ccomment, $cpredecessor, $cbranch;
  $cbranch = key2tagname($key);
  $cpredecessor = key2tagname($objects{$key}{"Predecessors"}[0]);
  $cpredecessor = "initial_commit" unless($cpredecessor);
  $owner = $objects{$key}{"Owner"};
  $cauthor = "$owner <" . $owner . "\@eurocontrol.int>";
  $cdate = $objects{$key}{"Created"};
  $ccomment = "Project $key - ".join(" ", @{$objects{$key}{"Comment"}})." - tasks: ".$objects{$key}{"Task"}." ";
  print "git checkout tags/$cpredecessor\n";
  print "git branch -d $cpredecessor 2> /dev/null\n";
  print "git branch $cbranch\n";
  print "git checkout heads/$cbranch\n";
  print "rm -rf *;\n";
  print "$ccm_cmd cfs \"$key\" -p . \n";
  print "$subadds \n" if ($subadds);
  print "git add -A *\n";
  print "git commit --allow-empty --author \"$cauthor\" --date \"$cdate\" -m \"$ccomment (imported via git2synergy)\"\n";
  print "git tag $cbranch\n";
  print STDERR "$tirets $key\n";
  foreach $successor (@{$objects{$key}{"Successors"}}) {
    followtree($successor, $tirets.'-');
  }
}
print("mkdir -p $folder\n");
print("cd $folder\n");
print("rm -rf .git *\n");
print("git init\n");
print("printf \"# $title \\n\\nrepository generated automaticaly\\n\" > README.md\n");
print("git add README.md\n");
print("git commit --author=\"synergy2git <contact@24eme.fr>\" -m \"initial commit\"\n");
print("git tag initial_commit\n");
foreach $first (@firsts) {
  followtree($first, '-');
}
print ("git-big-picture -o ../repo.png -a .\n");
print ("cd ..\n");
