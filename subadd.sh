#!/bin/bash

allobj=$1
objmd5=$2
alltasks=$3

if ! test "$alltasks" ; then

	echo "USAGE : $0 ALL_OBJ_FILE OBJ2MD5_FILE ALL_TASKS_FILE "
	echo ""
	echo "ALL_OBJ_FILE: "
	printf "\t"
	echo "ccm query -ch \"type match '*'\"  -f \"%displayname %dtatus %owner %cvtype %project %task %objectname %{create_time[dateformat=\"yyyy-MM-dd_HH:mm:ss\"]}\""
	echo "";
	echo "ALL_TASKS_FILE:" 
	printf "\t"
	echo 'ccm query -ch -t task -f "%displayname %task_synopsis"';
	echo "";
	echo "OBK2MD5_FILE:"
	printf "\t"
	echo "based on ccm cat $FILEID | md5sum";
	exit 1
fi

git status -s | awk '{print "md5sum "$2}'| sh | while read md5 path ; do 
	echo -n "$path "; grep $md5 $objmd5  ; 
	echo ; 
done | grep '/'  | while read path id md5 ; do 
	if test "$id" ; then 
		echo -n $path" "$md5" " ; 
		grep "$id" $allobj ; 
		echo ; 
	fi ; 
done | awk '{print $12" "$7" "$10" "$1}END{print "#FIN "}'  | grep '#' | while read date auteur task path ; do 
	if test "$old" && ! test "$old" = "$auteur $task"; then
                if ! test "$mycomment" ; then
			mycomment="commentaire vide"
		fi
		git commit -m "$mycomment" --date "$mydate" --author "$myauteur <$myauteur@eurocontrol.info>"
        fi
	if test "$path"; then
		git add $path
	fi
	old="$auteur $task"
	mytask=$task
	mydate=$date
	myauteur=$auteur
	mycomment=$(grep "$task " $alltasks | sed 's/^[^)]*)//')
done

