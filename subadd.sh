#!/bin/bash

# the script subadd.sh aims to generate a succession of commits associated to tasks
# It starts from a git repository with changes in the working tree.
# The md5sum of modified or created files is used to identify the tasks

# It takes as parameter the directory where files have been extracted
# for example in SPV
# subadd.sh /development/git/serge/export_arh

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
	echo "Dump created via dump_ccm.sh : bash dump_ccm.sh <PATH_TO_DUMP>"
	exit 1
fi

# the second column of git status output is the list of modified, created or deleted files
# the file /tmp/subadd_content.$$.tmp will contain the md5sum of all the files to be modified or created followed by spaces, then their full pathname.
git status -s > /tmp/subadd_status.$$.tmp

# retrieve content of each Modification
cat /tmp/subadd_status.$$.tmp | grep -v " D " | awk '{print $2}' | while read path ; do
	find $path -type f -exec md5sum '{}' ';'
done > /tmp/subadd_content.$$.tmp
# retrieve content of deletion (to retrieve all missing version between the deleted content and the current git content)
cat /tmp/subadd_status.$$.tmp | grep " D " | awk '{print $2}' | while read path ; do
	deletion_md5=$(git cat-file -p $(git ls-tree HEAD "$path" | cut -d " " -f 3 | sed -r 's/^([a-z0-9]+).+$/\1/')  | md5sum | sed 's/ *-.*//')
	printf "$deletion_md5  $path deletion"
done >> /tmp/subadd_content.$$.tmp


# save all the changes to the stash. This revert the working tree to the last commit
git stash > /dev/null

# ensure we have write access
chmod -R u+w .

# for each md5sum and pathname in /tmp/subadd_content.$$.tmp
cat /tmp/subadd_content.$$.tmp | while read md5 path extra ; do
	# use the md5sum to retrieve the objectname
	echo -n "$path;"; grep $md5 $objmd5  | head -n 1
	echo ;
	# foreach pathname, md5sum and objectname
done | grep ';[a-f0-9]' | sed 's/;/ /g' | while read path newmd5 newid; do

	# md5sum of the old file
	oldmd5=$(md5sum $path | sed 's/ .*//')
	patholdmd5file=$path2dump"/files/"$(echo $oldmd5 | sed 's/\(..\)\(..\)/\1\/\2\//')
	# objectname of the old file
	oldid=$(grep $oldmd5 $objmd5 | sed 's/.*;//' | tail -n 1)

	if ! test "$oldmd5" = "$newmd5" ; then
		# use the script history4fileversions.pl to retrieve all the objectnames between $oldid and $newid ($newid is included but not $oldid thanks to the tail -n +2).
		cat $patholdmd5file".history" | perl $path2bin"/history4fileversions.pl" "$oldid" "$newid" | tail -n +2 | while read versionid ; do
			md5=$(grep $versionid $objmd5 | sed 's/;.*//' | head -n 1)
			# the output is on 9 columns:
			# - the path
			# - the md5sum of the file
			# followed by all the columns of db/all_obj.csv
			# - line number
			# - objectname
			# - status
			# - owner
			# - task (comma separated list of tasks)
			# - create_time
			# - displayname
			echo -n $path";"$md5";" ;
			grep "$versionid" $allobj | head -n 1
			echo ;
		done
	else
        # it is a new file
        echo -n $path";"$newmd5";" ;
        grep "$newid" $allobj | head -n 1
        echo ;
	fi
done > /tmp/subadd_tasks.$$.tmp

#retrieve deletion task
cat /tmp/subadd_status.$$.tmp | grep " D " | awk '{print $2}' | while read path ; do
	deletion_md5=$(git cat-file -p $(git ls-tree HEAD "$path" | cut -d " " -f 3 | sed -r 's/^([a-z0-9]+).+$/\1/')  | md5sum | sed 's/ -.*//')
	deletion_id=$(grep $deletion_md5 $objmd5 | sed 's/.*;//' | tail -n 1)
	deletion_dirpath=$(find $path2dump"/files/" -name '*dir' -exec grep -l "\- $deletion_id" '{}' ';')
	deletion_dirid=$(head -n 1 $deletion_dirpath | sed 's/^= //' | sed 's/ =$//')
	deletion_dirmd5=$(grep $deletion_dirid $objmd5 | tail -n 1 | awk -F ';' '{print $1}')
	echo -n $path";"$deletion_dirmd5";" ;
	grep "$deletion_dirid" $allobj | head -n 1
done >> /tmp/subadd_tasks.$$.tmp

# foreach create_time, owner, task, path and md5sum (sorted by date). A dummy line "#_END_" is read at the last iteration.
cat /tmp/subadd_tasks.$$.tmp | awk -F ';' '{print $8" "$6" "$7" "$1" "$2}END{print "#_END_ "}' | grep '_' | sort | while read date auteur task path md5; do
	# if the task changes (or it is the #_END_), commit the previous group of changes
	if test "$old" && ! test "$old" = "$auteur $task"; then
		if ! test "$mycomment" ; then
			mycomment="commentaire vide: $mytask"
		fi
		GIT_COMMITTER_DATE="$mydate" git commit -m "$mycomment" --date "$mydate" --author "$myauteur <$myauteur@eurocontrol.info>"
	fi
	if test "$path" && test "$md5"; then
		# perform the file change or creation in the working tree
		path2md5file=$path2dump"/files/"$(echo $md5 | sed 's/\(..\)\(..\)/\1\/\2\//')
		#retrieve the content if exists
		if test -f "$path2md5file" ; then
			mkdir -p $(dirname "$path")
			zcat $path2md5file > "$path"
		#otherwise if there is a .dir file, it's a deletion
		elif test -f $path2md5file".dir" ; then
			rm "$path"
		fi
		# stage the file for the next commit
		git add --all "$path"
	fi
	old="$auteur $task"
	mytask=$task
	mydate=$date
	myauteur=$auteur
	# retrieve the synopsis of the task
	mycomment=$(grep ";$task[ ;]" $alltasks | sed 's/^[0-9]*;//')
done

# retrieve the stash to ensure the final commit will be faithfull to synergy
git stash pop > /dev/null

rm /tmp/subadd_status.$$.tmp /tmp/subadd_tasks.$$.tmp /tmp/subadd_content.$$.tmp
