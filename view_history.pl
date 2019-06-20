#!/bin/perl

# the aim of the script history2gitcommands.pl is to migrate a project managed in synergy toward a git repository
# it assumes dump_ccm.sh has already be runned to extract 
# the parameters are:
# - repo_directory: the prefix used for the creation of two directories
#    - <repo_directory>_repo that will contain the git repository. It should be created before running this script if we need a .gitignore
#    - <repo_directory>_src that will be used for extraction
# - ccm: the constant string "ccm"
# - subadds: the string "$PWD/subadd.sh  <absolute_path_to_dump>"
#      this is used to launch script subadd.sh that takes a single parameter: the repo_directory
# - folderinside: specific directory (in source of a ccm cfs) where directly get the files
#
# the input of this script is the history of a project
# the output of this script is a bash script that contains all the commands to be executed


# parse stdin (the history of a project)
use File::Basename;
$_dir_ = dirname(__FILE__);
require $_dir_."/history.pm";

# Replace all the # and : characters in the objectname by underscores. This sanitization ensures
# it can be used as tag name.
sub key2tagname {
  my ($key) = @_;
  $key =~ s/[#:]/_/g;
  return $key;
}

sub followtree {
  my ($key, $tirets) = @_;
  # progression information of stderr
  print STDERR "$tirets $key\n";
  # recursive call for each successor of current version of project
  foreach $successor (@{$objects{$key}{"Successors"}}) {
    followtree($successor, $tirets.'-');
  }
}
# for each version of the project that have no ancestor
foreach $first (@firsts) {
  followtree($first, '-');
}
