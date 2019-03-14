#!/bin/bash

base=$1
dir=$2

if ! test "$dir"; then
	dir=$1;
fi

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

touch db/md5_obj.csv
mkdir -p files
cat db/all_obj.csv | grep -v ':task:' | grep -v ':releasedef:' | grep -v '/admin/' | grep -v ':folder:' | grep -v ':dir:' | grep -v ':tset:' | awk -F ';' '{print $2}' | while read id ; do
	retrieve_obj=""
	if grep " "$id'$' db/md5_obj.csv > /tmp/$$.grep ; then
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
			ccm history $id > $md5path".history"
		fi
		if test -s $md5path".history" ; then
			echo "$md5 $id" >> db/md5_obj.csv
		else
			rm $md5path".history" ;
		fi
	fi
done
