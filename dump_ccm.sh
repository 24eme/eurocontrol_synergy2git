#!/bin/bash

# the script dump_ccm.sh has two parameters
# the parameter "base" is the name of the syngergy database, for example arh
# the parameter "dir" is optional (by default same as base). It is the destination directory.

# This script produces the result of 3 synergy queries reformated as csv*:
# db/all_obj.csv
#   query all objects: ccm query "type match '*'"
#   format: %objectname %status %owner %task %{create_time[dateformat=\"yyyy-MM-dd_HH:mm:ss\"]} %displayname
# db/all_tasks.csv
#   query all objects of type task: ccm query -t task
#   format: %displayname %task_synopsis
# db/all_projects.csv
#   query all projects: ccm query -t project
#   default format: %displayname %status %owner %cvtype %project %task
#
# for each objects of type 'dir' found in db/all_obj.csv, the objectname contained in the directory are listed
# using the query
#   ccm query "is_child_of('$dir', '$fullproject')"
# where fullproject takes as value successively all the values of db/all_projects.csv
# the result is a csv file db/all_dirs.csv with 
#
# This script also produces the csv* file
# db/md5_obj.csv that contains for each objectname, the hash of its content (md5sum is used for hashing). The order of the fields is the md5sum followed by the objectname.
# The content of the file (compressed) is saved to a file named by the md5sum (the first two pairs of characters are used as subdirectories)
# The history of the file (output of command ccm history) is saved in a file whose name is similar as previous file with the suffix ".history".
#
# *: csv files are separated by semi-colons.
#
base=$1
dir=$2

if ! test "$dir"; then
	dir=$1;
fi

basedir=$(pwd)"/"$(dirname $0)"/"

# the routine "connect" is called before each query because synergy connections are unreliable
function connect {
	if ! test "$CCM_ADDR" || ! netstat -atn | grep  ":"$(echo $CCM_ADDR | awk -F ':' '{print $2}')" " | grep LISTEN > /dev/null ; then
	        export CCM_ADDR=$(/ccm_data/common/ccmapp -cli $base)
	fi
}

mkdir -p $dir
cd $dir 
mkdir -p db

if ! test -f db/all_obj.csv ; then 
	connect
	ccm query -ch "type match '*'"  -f "%objectname %status %owner %task %{create_time[dateformat=\"yyyy-MM-dd_HH:mm:ss\"]} %displayname" | sed 's/^ *//' | sed 's/  */;/g' > db/all_obj.csv
fi

if ! test -f db/all_tasks.csv ; then
	connect
	ccm query -ch -t task -f "%displayname %task_synopsis" | sed 's/^ *//' | sed 's/[ )]  */;/g' > db/all_tasks.csv
fi

if ! test -f db/all_projects.csv; then
	connect
	ccm query -t project | sed 's/^ *//' | sed 's/  */;/g' > db/all_projects.csv 
fi

if ! test -f db/all_dirs.csv ; then 
        grep ':dir:' db/all_obj.csv | awk -F ';' '{print $2}' | while read dir ; do
		awk -F ';' '{print $2}'  db/all_projects.csv | while read project ; do
			fullproject=$(grep $project":project" db/all_obj.csv | awk -F ';' '{print $2}' ) ;
			connect
			ccm query -u -nf -f %objectname "is_child_of('"$dir"', '"$fullproject"')" | sed 's/^/'$fullproject';'$dir';/' ;
		done  ;
	done > db/all_dirs.csv
fi

touch db/md5_obj.csv
mkdir -p files
cat db/all_obj.csv | grep -v ':task:' | grep -v ':releasedef:' | grep -v '/admin/' | grep -v ':folder:' | grep -v ':tset:' | grep -v ';base/' | awk -F ';' '{print $2}' | while read id ; do
	retrieve_obj=""
	if grep ";"$id'$' db/md5_obj.csv > /tmp/$$.grep ; then
		md5=$(cat /tmp/$$.grep | awk '{print $1}')
                md5path="files/"$(echo $md5 | sed 's/\(..\)\(..\)/\1\/\2\//')
		if ! test -s $md5path ; then
			if ! test -s $md5path".history" ; then
				retrieve_obj="GO"	
			fi

		fi
		rm /tmp/$$.grep
	else
		retrieve_obj="GO"
	fi
	if test "$retrieve_obj" ; then
		connect
		ccm cat $id > .ccm_cat.tmp
                if test -s .ccm_cat.tmp ; then
			md5=$(md5sum .ccm_cat.tmp | awk '{print $1}')
			md5path="files/"$(echo $md5 | sed 's/\(..\)\(..\)/\1\/\2\//')
			mkdir -p $(dirname $md5path)
			cat .ccm_cat.tmp | gzip > $md5path
			connect
			if ! test -s $md5path".history" ; then
				ccm history $id > $md5path".history"
			fi
			if test -s $md5path".history" ; then
				echo "$md5;$id" >> db/md5_obj.csv
			else
				rm $md5path".history" ;
			fi
		fi
		rm .ccm_cat.tmp
	fi
done

cat db/all_dirs.csv | awkcat db/all_dirs.csv | awk -F ';' '{print $1";"$2}'  |  sort -u | while read project_dir_id ; do
    project=$(echo $project_dir_id | awk -F ';' '{print $1}');
    dir=$(echo $project_dir_id | awk -F ';' '{print $2}');
	id=$dir

    connect
    ccm history "$dir" > .ccm.history;
    prev=$( bash -c " echo ; cat .ccm.history | perl $basedir/history4fileversions.pl -n "$dir  | tail -n 2 | head -n 1  );

    grep ';'$dir';' db/all_dirs.csv  | awk -F ';' '{print $3}'  | sort  -u > .dir.actual
	echo "= $dir =" > .dir.content
    cat  .dir.actual >> .dir.content
    if test "$prev" ; then
        grep ';'$prev';' db/all_dirs.csv | awk -F ';' '{print $3}'  | sort  -u > .dir.previous
        diff .dir.previous .dir.actual | grep '^<' | sed 's/^</-/' >> .dir.content
    fi

    md5=$(md5sum .dir.content | awk '{print $1}')
    md5path="files/"$(echo $md5 | sed 's/\(..\)\(..\)/\1\/\2\//')
    mkdir -p $(dirname $md5path)
    cat .dir.content > $md5path".dir"
    cat .ccm.history > $md5path".history"

	if test -s $md5path".history" ; then
		echo "$md5;$id" >> db/md5_obj.csv
	else
		rm $md5path".history" ;
		rm $md5path".dir" ;
		rm $md5path ;
	fi

    rm -f .ccm.history .dir.actual .dir.previous .dir.content
done
