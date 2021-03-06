#!/usr/bin/perl -w
    eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
        if 0; #$running_under_some_shell

use strict;
use warnings;

use File::Path qw(make_path);
use File::Find;
use File::Basename qw(basename dirname);
use Cwd qw(realpath);
use Data::Dumper;
use POSIX;

print strftime ('%F %T ', localtime $^T), join (' ', $0, @ARGV), "\n";

my $filter_products = '';
my $include_prep = 1;

# name of the synergy database (for example arh)
START:
my $synergy_db = shift @ARGV;
# parameter -noprod avoids dump of product objects
if (defined $synergy_db and $synergy_db eq '-noprod') {
    # beware that "not is_product=TRUE" is not the same as "is_product=FALSE" because is_product is undefined for most of the objects
    $filter_products = 'and not is_product=TRUE';
    goto START;
# parameter -noprep avoids projects in prep state to be dumped
} elsif (defined $synergy_db and $synergy_db eq '-noprep') {
    $include_prep = 0;
    goto START;
}
# absolute path toward the git repository
my $root_dir;
my $bin_dir;
if ($#ARGV > -1) {
    $root_dir = realpath(shift @ARGV);
    $bin_dir = realpath(dirname($0));
}

unless (defined $synergy_db && defined $root_dir) {
    print STDERR "USAGE: $0 [-noprod] [-noprep] <synergy_db_name> <dump_dir_path>\n";
    exit 1;
}

&connect();

chdir ($root_dir);

# step 1: query all objects (not is_product if -noprod is specified)
#my @all_types = map {my ($name) = split(' ', $_);$name} `ccm typedef -l`;
my %objs;
if (-e 'all_obj.dump') {
    my $VAR1 = do 'all_obj.dump';
    %objs = %$VAR1;
} else {
    # beware that "not is_product=TRUE" is not the same as "is_product=FALSE" because is_product is undefined for most of the objects
    # type acifs causes crashs in ace_grd and ace_cmn
    # type acifc and bat causes crashs in ino
    %objs = &ccm_query_with_retry('all_obj', ['%objectname', '%status', '%owner', '%release', '%task', '%{create_time[dateformat="yyyy-MM-dd_HH:mm:ss"]}'], "type!='acifs' and type!='acifc' and type!='bat' $filter_products");
}

# remove entries where objectname contains /
map {delete $objs{$_};} grep {/\//} keys %objs;
# remove entrie of temporairy objects
map {delete $objs{$_};} grep {/-temp/} keys %objs;
delete $objs{'ERGO_IHM_JAVA-HMI#ACE2008B_Int_20100910:project:ACE_EONS#1'};
delete $objs{'Common_Items-ACE2016A_V3.0:project:ACE_CMN#1'};
print strftime ('%F %T ', localtime (time)), "Objs finished\n";


# step 2: query all tasks
my %tasks;
if (-e 'all_task.dump') {
    my $VAR1 = do 'all_task.dump';
    %tasks = %$VAR1;
} else {
    %tasks = &ccm_query_with_retry('all_task', ['%displayname', '%release', '%task_synopsis'], '-t task');
}
print strftime ('%F %T ', localtime (time)), "Tasks finished\n";

# step 3: dump all objects and keep their hash (and the hash of their history)
my $filename = "$root_dir/md5_obj.csv";
if (-e $filename) {
    print "Skip dump of all objects because $filename already exists\n";
} else {
    open my $dest, '>', $filename or die "Can't write $filename: $!";

    foreach my $k (sort keys %objs) {
        print "$k\n";
        my ($name, $version, $ctype, $instance) = parse_object_name($k);

        # skip what can not be dumped
        next if $ctype =~ m/^(task|releasedef|folder|tset|process_rule)$/;

        my $path = "${ctype}/${name}/${instance}/${version}";
        make_path($path) or die "Can't mkdir -p $path: $!" unless -d $path;
        my $hash_content = "";
        my $hash_hist    = "";
        if ($ctype !~ m/^(project|symlink|dir|dcmdbdef|folder_temp|project_grouping|saved_query|processdef)$/) {
            system ("ccm cat '$k' > '$path/content'") == 0  or warn ("Can't cat $k\n");
            $hash_content = `git hash-object '$path/content'`;
        }elsif($ctype eq 'dir') {
            $hash_content = `echo $k | git hash-object /dev/stdin`;
        }
        if (system ("ccm history '$k' > '$path/hist'") == 0) {
            $hash_hist    = `git hash-object '$path/hist'`;
        } else {
            warn ("Can't ccm history $k\n");
        }
        system("echo $k > '$path/id'");
        chomp $hash_content;
        chomp $hash_hist;
        print $dest "$hash_content;$hash_hist;$k;$path\n";
    }
    close $dest;
}


# exec_obj.csv contains the list of objectname that have been identified as executables.
$filename = "$root_dir/exec_obj.csv";
my %exec_obj;
if (-e $filename) {
    print "reading $filename\n";
    open (my $file, '<', $filename) or die "Can't read $filename: $!";
    while (my $line = <$file>) {
        chomp $line;
        $exec_obj{$line}++;
    }
}
open (my $filex, '>>', $filename) or die "Can't append to $filename: $!";

# not_exec_obj.csv contains the list of objectname that have been identified as not executables.
my $filename_not = "$root_dir/not_exec_obj.csv";
my %not_exec_obj;
if (-e $filename_not) {
    print "reading $filename_not\n";
    open (my $file, '<', $filename_not) or die "Can't read $filename_not: $!";
    while (my $line = <$file>) {
        chomp $line;
        $not_exec_obj{$line}++;
    }
}
open (my $filex_not, '>>', $filename_not) or die "Can't append to $filename_not: $!";
print strftime ('%F %T ', localtime (time)), "Step 3 finished\n";


# step 4 recursive ls of each baselined projects (status is released, integrate or prep)
# if process is stoped during extraction of a project, the work area shall be removed
# manually and the file "ls" in the top directory shall be removed so that it is started again at next start:
#   rm ../arh_repo/project/Oasis_Component_Model/ARH#1/ACE2005B_V0.9/ls
#   ccm delete Oasis_Component_Model-tempo3368
my $wa_dir = realpath("$root_dir/../tmp$$");
make_path($wa_dir);
chdir $wa_dir or die "Can't chdir $wa_dir: $!";
system ("rm -rf *-tempo*");
foreach my $k (sort keys %objs) {
    my ($name, $version, $ctype, $instance) = parse_object_name($k);
    next if $ctype ne 'project';
    if ($objs{$k}->{'status'} ne 'released' && $objs{$k}->{'status'} ne 'integrate') {
        next if ($include_prep == 0) || $objs{$k}->{'status'} ne 'prep';
    }

    if (-e "$root_dir/${ctype}/${name}/${instance}/${version}/ls") {
        print "Skip project $k already dumped\n";
        next;
    }
  START:
    print "Creating a wa of $k\n";

    # create a copy of a project with a working area (link based) and no_update
    if (system("ccm cp -release ACE2019A -t tempo$$ -no_u -lb -scope project_only -setpath $wa_dir $k") != 0) {
        warn "ccm cp failed for $k skip it for the moment\n";
        next;
    }
    unless (-d "$root_dir/${ctype}/${name}/${instance}/${version}") {
        next;
    }
    chdir $wa_dir or die "Can't chdir $wa_dir: $!";
    my $prj = `ls`; chomp $prj;
    chdir($prj) or die "Can't chdir ${prj}: $!";
    my @all_dirs = `find . -type d`;
    chomp @all_dirs;
    foreach my $dir (@all_dirs) {
        my $git_path = "$root_dir/${ctype}/${name}/${instance}/${version}/$dir";
        make_path($git_path);
        my @ls = `ccm ls "$dir" -f '%objectname' | tee "${git_path}/ls"`;
        # if a symlink is encountered, memorize its value
        foreach my $file (@ls) {
            chomp $file;
            next if $file eq '';
            my ($fname, $fversion, $fctype, $finstance) = parse_object_name($file);
            if ($fctype eq 'symlink') {
                `readlink "$dir/$fname" > "$root_dir/${fctype}/${fname}/${finstance}/${fversion}/content"`;
            } elsif ($fctype ne 'dir' and $fctype ne 'project') {
                # if a file is encountered memorize its permissions (executable or not)
                if ((not exists $exec_obj{$file})) {
                    if ((-l "$dir/$fname" && -x readlink("$dir/$fname"))
                        or -x "$dir/$fname") {
                        $exec_obj{$file}++;
                        print $filex "$file\n";
                    } else {
                        $not_exec_obj{$file}++;
                        print $filex_not "$file\n";
                    }
                }
            }
        }
    }
    chdir ('..');
    # delete the project
    if (system("ccm delete '$prj'") != 0) {
        warn "ccm delete failed for $prj\n";
	sleep (5);
        &connect();
        if (system("ccm delete '$prj'") != 0) {
            warn "ccm delete failed twice for $prj\n";
            system ("rm -rf $wa_dir/*");
        }
        # in case of problems, restart the dump of the last project
        goto START;
    }
    # clean the .moved directory
    system("rm -rf $ENV{HOME}/ccm_wa/.moved/$synergy_db/*");
}
close $filex;
close $filex_not;

chdir ($root_dir);
print strftime ('%F %T ', localtime (time)), "Step 4 finished\n";


# step 5 : retrieve the content of directories

# make it faster by memorizing which projects contains which directories in one pass
my %dirs_in_projects;

my $current_obj;
foreach (sort keys %objs) {
    $current_obj = $_;
    my ($name, $version, $ctype, $instance) = parse_object_name($current_obj);
    next if $ctype ne 'project';
    find (\&wanted, "${ctype}/${name}/${instance}/${version}");
}

sub wanted {
    return unless $_ eq 'ls' && -f $_;
    open my $file, '<', $_ or die "Can't read $File::Find::name: $!";
    foreach my $line (<$file>) {
	chomp $line;
	next if $line eq '';
	my ($name2, $version2, $ctype2, $instance2) = parse_object_name($line);
	next if $ctype2 ne 'dir';
	push @{$dirs_in_projects{$line}}, $current_obj;
    }
}

foreach my $k (sort keys %objs) {
    my ($name, $version, $ctype, $instance) = parse_object_name($k);
    next if $ctype ne 'dir';
    foreach my $fullproject ( @{$dirs_in_projects{$k}} ) {
        my %content = &ccm_query_with_retry('dir_content', ['%objectname', '%release'], "is_child_of(\"$k\", \"$fullproject\")");
        my %res;
        my $ls;
        if (-f "$root_dir/${ctype}/${name}/${instance}/${version}/ls") {
            open $ls,  "$root_dir/${ctype}/${name}/${instance}/${version}/ls";
            foreach (<$ls>) {
                next if (/^- /);
                chomp;
                $res{$_} = $_;
            }
            close $ls;
        }
        foreach my $contentid ( keys %content )  {
            $contentid =~ s/\s.*//;
            $res{$contentid} = $contentid ;
        }
        open $ls,  "> $root_dir/${ctype}/${name}/${instance}/${version}/ls";
        foreach ( sort keys %res ) {
            print $ls "$_\n";
        }
        close $ls;
    }
}
print strftime ('%F %T ', localtime (time)), "Step 5 finished\n";


# step 6 : retrive the deleted content of directories
foreach my $k (sort keys %objs) {
    my ($name, $version, $ctype, $instance) = parse_object_name($k);
    next if $ctype ne 'dir';
    my $previous = get_previous_version($k);
    next unless ($previous);
    my ($pname, $pversion, $pctype, $pinstance) = parse_object_name($previous);
    next unless (-f "$root_dir/${pctype}/${pname}/${pinstance}/${pversion}/ls");
    next unless (-f "$root_dir/${ctype}/${name}/${instance}/${version}/ls");
    open my $diff, "diff $root_dir/${pctype}/${pname}/${pinstance}/${pversion}/ls $root_dir/${ctype}/${name}/${instance}/${version}/ls | grep '^<' | grep -v '^< - ' |" ;
    open my $ls,  ">> $root_dir/${ctype}/${name}/${instance}/${version}/ls";
    foreach (<$diff>) {
        chomp;
        s/^< *//;
        print $ls "- $_\n";
    }
    close $diff;
    close $ls;
}
print strftime ('%F %T ', localtime (time)), "Step 6 finished\n";

sub get_previous_version {
    my $k = shift;
    my ($name, $version, $ctype, $instance) = parse_object_name($k);
    my $history_path = "$root_dir/${ctype}/${name}/${instance}/${version}/hist";
    open my $history, "cat '$history_path' | perl $bin_dir/history4fileversions.pl -n $k |" ;
    my @history = <$history>;
    close $history;
    pop @history;
    if ($#history < 0) {
        return ;
    }
    my $h = pop @history;
    chomp($h);
    return $h;
}

# split the four part objectname even in edge cases (names containing dash or separated from version using colon instead of dash)
sub parse_object_name {
    my $objectname = shift;
    # extract fourth part: instance
    my $ri = rindex($objectname, ':');
    die "wrong objectname $objectname does not contain : before instance" if $ri == -1;
    my $instance = substr($objectname, $ri + 1);
    # extract third part: type
    my $cri = rindex($objectname, ':', $ri - 1);
    die "wrong objectname $objectname does not contain : before type" if $cri == -1;
    my $ctype = substr($objectname, $cri + 1, $ri - $cri -1);
    # extract second part: version
    my $vri = rindex($objectname, ':', $cri - 1);
    $vri = rindex($objectname, '-', $cri - 1) if $vri == -1;
    die "wrong objectname $objectname does not contain : or - before version" if $vri == -1;
    my $version = substr($objectname, $vri + 1, $cri - $vri -1);
    # first part: name
    my $name = substr($objectname, 0, $vri);
    return ($name, $version, $ctype, $instance);
}

# wait for reconnection to synergy (tolerates the long backup interruption)
sub connect {
    while (1) {
        $ENV{CCM_ADDR} = `/ccm_data/common/ccmapp -cli $synergy_db`;
        chomp $ENV{CCM_ADDR};
        # check if success
        return if `ccm delim` eq "-\n";
        print "Connect failed, retrying in 5s\n";
        sleep 5;
    }
}

#
sub ccm_query_with_retry($\@$) {
    my $name = shift;
    my $format = shift;
    my $filter = shift;
    while (1) {
        my %res = eval { ccm_query($name, $format, $filter); };
        if ($@) {
            warn "ccm_query failed $@\nretry\n";
            &connect();
        } else {
            return %res;
        }
    }
}

# as queries were performed using the qualifier "-ch" that forces formating in columns, I have used that formating
# to perform splitting in columns
# Result of queries is returned as a hash and also stored in a csv file and a perl dump.
sub ccm_query($\@$) {
    my $name = shift;
    my $format = shift;
    my $filter = shift;
    my @format = @{$format};

    my $filename = "$root_dir/${name}.csv";
    open my $dest, '>', $filename or die "Can't write $filename: $!";
    my $qformat = join('||', @format);
    $qformat =~ s/'/'"'"'/g; # see https://stackoverflow.com/questions/24868950/perl-escaping-argument-for-bash-execution
    my $query = "ccm query -u";
    if (defined $filter) {
        if ($filter =~ m/^-t/) {
            $query .= " $filter";
        } else {
            $filter =~ s/'/'"'"'/g;
            $query .= " '$filter'";
        }
    }
    $query .= " -f '$qformat'";
    print "query: $query\n";

    my @titles;
    foreach my $atitle (@format) {
        $atitle =~ s/^%\{?//;
        $atitle =~ s/[\[\{].*//;
        push @titles, $atitle;
    }

    my %res;
    open my $cmd, "$query |" or die "Can't exec ccm query command: $!";
    #open my $cmd, '<', "queries/${name}.txt" or die "Can't exec queries/${name}.txt: $!";
    while (my $line = <$cmd>) {
        next unless ($line =~ /\|\|/);
        chomp($line);
        my %record;
        my @fields = split(/\|\|/, $line);
        print $dest join(';', @fields), "\n";
        foreach my $i (1..$#titles) {
            $record{$titles[$i]} = $fields[$i];
        }
        $res{$fields[0]} = \%record;
    }
    close $cmd;
    my $exit_status = $? >> 8;
    die "Bad exit status $exit_status" if ($exit_status && $exit_status != 6);
    $filename = "$root_dir/${name}.dump";
    open $dest, '>', $filename or die "Can't write $filename: $!";
    print $dest Dumper(\%res);
    close $dest;
    return %res;
}
