#!/bin/bash


path2dump=$1
path2bin=$(dirname $0)

allobj=$path2dump"/db/all_obj.csv"
objmd5=$path2dump"/db/md5_obj.csv"
alltasks=$path2dump"/db/all_tasks.csv"

if ! test "$alltasks" ; then

	echo "USAGE : $0 <PATH_TO_DUMP>"
	echo ""
	echo "PATH_TO_DUMP: "
	printf "\t"
	echo "Dump created via dump_ccm.sh : bash dump_ccm.sh <CCM_BASE> <PATH_TO_DUMP>"
	exit 1
fi

git status -s | awk '{print $2}' | while read path ; do
	find $path -type f -exec md5sum '{}' ';' 
done > /tmp/subadd.$$.tmp

git stash > /dev/null 

chmod -R u+w .

cat /tmp/subadd.$$.tmp | while read md5 path extra ; do 
	echo -n "$path;"; grep $md5 $objmd5  | head -n 1
	echo ; 
done | grep ';[a-f0-9]' | sed 's/;/ /g' | while read path newmd5 newid; do 

	oldmd5=$(md5sum $path | sed 's/ .*//')
	patholdmd5file=$path2dump"/files/"$(echo $oldmd5 | sed 's/\(..\)\(..\)/\1\/\2\//')
	oldid=$(grep $oldmd5 $objmd5 | sed 's/.*;//' | tail -n 1)

	if ! test "$oldmd5" = "$newmd5" ; then
		cat $patholdmd5file".history" | perl $path2bin"/history4fileversions.pl" "$oldid" "$newid" | tail -n +2 | while read versionid ; do
			md5=$(grep $versionid $objmd5 | sed 's/;.*//')
			echo -n $path";"$md5";" ; 
			grep "$versionid" $allobj | head -n 1
			echo ; 
		done
	else
	        echo -n $path";"$newmd5";" ;
	        grep "$newid" $allobj | head -n 1
	        echo ;
	fi
done | awk -F ';' '{print $8" "$6" "$7" "$1" "$2}END{print "#_FIN_ "}' | grep '_' | sort | while read date auteur task path md5; do 
	if test "$old" && ! test "$old" = "$auteur $task"; then
                if ! test "$mycomment" ; then
			mycomment="commentaire vide: $mytask"
		fi
		GIT_COMMITTER_DATE="$mydate" git commit -m "$mycomment" --date "$mydate" --author "$myauteur <$myauteur@eurocontrol.info>"
        fi
	if test "$path" && test "$md5"; then
		path2md5file=$path2dump"/files/"$(echo $md5 | sed 's/\(..\)\(..\)/\1\/\2\//')
		mkdir -p $(dirname $path)
		zcat $path2md5file > $path
		git add $path
	fi
	old="$auteur $task"
	mytask=$task
	mydate=$date
	myauteur=$auteur
	mycomment=$(grep ";$task[ ;]" $alltasks)
done

git stash pop > /dev/null

rm /tmp/subadd.$$.tmp


