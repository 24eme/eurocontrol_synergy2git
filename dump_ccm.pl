#! /usr/bin/perl -w
    eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
        if 0; #$running_under_some_shell

use strict;
use warnings;

use File::Path qw(make_path);
use File::Basename qw(basename);
use Cwd qw(realpath);
use Data::Dumper;

# name of the synergy database (for example arh)
my $synergy_db = shift @ARGV;
# absolute path toward the git repository
my $root_dir = shift @ARGV;

# step 0: create a git repository, a README.md, a first commit and a branch named db
unless (-d $root_dir) {
    make_path("$root_dir") or die "Can't mkdir -p $root_dir: $!";
    chdir $root_dir or die "Can't chdir -p $root_dir: $!";

    open (my $file, '>', "$root_dir/README.md") or die "Can't create README.md: $!";
    print $file "# EUROCONTROL's migration of CM Synergy base $synergy_db toward git\n\n";
    print $file "all objects are dumped in branch db\n";
    close $file;

    system('git init .') == 0 or die "Can't git init .";
    system('git add README.md') == 0 or die "Can't git add README.md";
    system("git commit -m 'initial commit: migration of $synergy_db'") == 0 or die "Can't git commit";
    system("git branch db") == 0 or die "Can't git branch db";
}

chdir $root_dir or die "Can't chdir -p $root_dir: $!";
system('git checkout db') == 0 or die "Can't git checkout db";

&connect();


# step 1: query all objects (not is_product)
my %objs;
if (-e 'all_obj.dump') {
    my $VAR1 = do 'all_obj.dump';
    %objs = %$VAR1;
} else {
  # beware that "not is_product=TRUE" is not the same as "is_product=FALSE" because is_product is undefined for most of the objects
  %objs = &ccm_query_with_retry('all_obj', '%objectname %status %owner %release %task %{create_time[dateformat="yyyy-MM-dd_HH:mm:ss"]}', "type match '*' and not is_product=TRUE");
}

# remove entries where objectname contains /
map {delete $objs{$_};} grep {/\//} keys %objs;
print "Objs finished\n";


# step 2: query all tasks
my %tasks;
if (-e 'all_task.dump') {
    my $VAR1 = do 'all_task.dump';
    %tasks = %$VAR1;
} else {
  %tasks = &ccm_query_with_retry('all_task', '%displayname %release %task_synopsis', '-t task');
}
print "Tasks finished\n";


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
        next if $ctype =~ m/^(task|releasedef|folder|tset|dir|baseline|process_rule)$/;
        
        my $path = "${ctype}/${name}/${instance}/${version}";
        make_path($path) or die "Can't mkdir -p $path: $!" unless -d $path;
        my $hash_content = "";
        my $hash_hist    = "";
        if ($ctype !~ m/^(project|symlink)$/) {
            system ("ccm cat '$k' > '$path/content'") == 0  or warn ("Can't cat $k\n");
            $hash_content = `git hash-object '$path/content'`;
        }
        if (system ("ccm history '$k' > '$path/hist'") == 0) {
            $hash_hist    = `git hash-object $path/hist`;
        } else {
            warn ("Can't ccm history $k\n");
        }
        chomp $hash_content;
        chomp $hash_hist;
        print $dest "$hash_content;$hash_hist;$k\n";
    }
    close $dest;
}


# step 4 recursive ls of each baselined projects
# if process is stoped during extraction of a project, the work area shall be removed
# manually and the file "ls" in the top directory shall be removed so that it is started again at next start:
#   rm ../arh_repo/project/Oasis_Component_Model/ARH#1/ACE2005B_V0.9/ls
#   ccm delete Oasis_Component_Model-tempo3368
my $wa_dir = realpath("$root_dir/../tmp");
make_path($wa_dir);
chdir $wa_dir or die "Can't chdir $wa_dir: $!";
system ("rm -rf *-tempo*");
foreach my $k (sort keys %objs) {
    my ($name, $version, $ctype, $instance) = parse_object_name($k);
    next if $ctype ne 'project';
    next if $objs{$k}->{'Status'} ne 'released';

    if (-e "$root_dir/${ctype}/${name}/${instance}/${version}/ls") {
        print "Skip project $k already dumped\n";
        next;
    }
    print "Creating a wa of $k\n";

    if (system("ccm cp -t tempo$$ -no_u -scope project_only -setpath $wa_dir $k") != 0) {
        warn "ccm cp failed for $k skip it for the moment\n";
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
        my @ls = `ccm ls $dir -f '%objectname' | tee ${git_path}/ls`;
        # if a symlink is encountered, memorize its value
        foreach my $file (@ls) {
            chomp $file;
            next if $file eq '';
            my ($fname, $fversion, $fctype, $finstance) = parse_object_name($file);
            next unless $fctype eq 'symlink';
            `readlink $dir/$fname > $root_dir/${fctype}/${fname}/${finstance}/${fversion}/content`;
        }
    }
    chdir ('..');
    system("ccm delete '$prj'") == 0 or die "ccm delete failed for $prj";
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
sub ccm_query_with_retry {
    my @args = @_;
    while (1) {
        my %res = eval { ccm_query(@args); };
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
sub ccm_query {
    my ($name, $format, $filter) = @_;
    my $filename = "$root_dir/${name}.csv";
    open my $dest, '>', $filename or die "Can't write $filename: $!";
    $format =~ s/'/'"'"'/g; # see https://stackoverflow.com/questions/24868950/perl-escaping-argument-for-bash-execution
    my $query = "ccm query -u -ch";
    if (defined $filter) {
        if ($filter =~ m/^-t/) {
            $query .= " $filter";
        } else {
            $filter =~ s/'/'"'"'/g;
            $query .= " '$filter'";
        }
    }
    $query .= " -f '$format'";
    print "query: $query\n";
    my %res;
    open my $cmd, "$query |" or die "Can't exec ccm query command: $!";
    #open my $cmd, '<', "queries/${name}.txt" or die "Can't exec queries/${name}.txt: $!";
    my $ch = <$cmd>;
    my @starts = (0);
    my @ends;
    my @titles;
    my $inside = 1;
    #print "ch=$ch\n";
    foreach my $i (1..length($ch)) {
        my $is_space = substr($ch, $i, 1) =~ m/ |\n/;
        if ($inside) {
            if ($is_space) {
                push @ends, $i-1;
                my $s = substr($ch, $starts[$#starts], $i-$starts[$#starts]);
                push @titles, $s;
                #print "title ", $titles[$#titles], " $s $starts[$#starts] $i \n";
                $inside = 0;
            }
        } else {
            if (!$is_space) {
                $inside = 1;
                push @starts, $i;
                #print "push starts $starts[$#starts]\n";
            }
        }
    }
    my @lengths = map {$starts[$_] - $starts[$_-1]} 1..$#titles;
    push @lengths, -1;
    while (my $line = <$cmd>) {
        my %record;
        my @fields;
        foreach my $i (0..$#titles) {
            my $field = substr($line, $starts[$i], $lengths[$i]);
            $field =~ s/\s+$//;
            push @fields, $field;
        }
        #print join(';', @fields), "\n";
        print $dest join(';', @fields), "\n";
        foreach my $i (1..$#titles) {
            $record{$titles[$i]} = $fields[$i];
        }
        $res{$fields[0]} = \%record;
    }
    close $cmd;
    my $exit_status = $? >> 8;
    die "Bad exit status $exit_status" if $exit_status;
    $filename = "$root_dir/${name}.dump";
    open $dest, '>', $filename or die "Can't write $filename: $!";
    print $dest Dumper(\%res);
    close $dest;
    return %res;
}


