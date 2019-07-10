#!/bin/bash

# the script subadd.sh aims to generate a succession of commits associated to tasks
# It starts from a git repository with changes in the working tree.
# The md5sum of modified or created files is used to identify the tasks

# It takes as parameter the directory where files have been extracted
# for example in SPV
# subadd.sh /development/git/serge/export_arh

path2dump=$1
path2bin=$(dirname $0)
path2repo=$(pwd)
dbargs="--git-dir="$path2dump"/.git/"

if ! git $dbargs show db:all_obj.csv > /dev/null 2>&1; then
	echo "USAGE : $0 <PATH_TO_DUMP>"
	echo ""
	echo "PATH_TO_DUMP: "
	printf "\t"
	echo "Dump created via dump_ccm.sh : bash dump_ccm.sh <PATH_TO_DUMP>"
	printf "\t"
	echo "The dump need to be a git repository with a db branch containing the dump"
	echo
	exit 1
fi

# the second column of git status output is the list of modified, created or deleted files
# the file /tmp/subadd_content.$$.tmp will contain the md5sum of all the files to be modified or created followed by spaces, then their full pathname.
git status -s | sed 's/"//g' > /tmp/subadd_status.$$.tmp

IFS=";"

# retrieve content of each Modification
cat /tmp/subadd_status.$$.tmp | grep -v "^ D " | sed 's/^ *[^ ]* *//' | while read path ; do
	find $path -type f | while read file ; do
		echo $(git hash-object "$file")";"$file";" ;
	done
done > /tmp/subadd_content.$$.tmp ;
# retrieve content of deletion (to retrieve all missing version between the deleted content and the current git content)
cat /tmp/subadd_status.$$.tmp | grep "^ D " | sed 's/^ *[^ ]* *//' | while read path ; do
	find $path -type f | while read file ; do
		deletion_hash=$(git ls-tree HEAD "$file" | awk '{print $3}')
		printf "$deletion_hash;$file;deletion"
	done
done >> /tmp/subadd_content.$$.tmp

# save all the changes to the stash. This revert the working tree to the last commit
git stash > /dev/null

# ensure we have write access
chmod -R u+w .

# for each md5sum and pathname in /tmp/subadd_content.$$.tmp
cat /tmp/subadd_content.$$.tmp | while read hash path extra ; do
	# use the md5sum to retrieve the objectname
	echo -n "$path;" ; git $dbargs show db:md5_obj.csv | grep $hash | head -n 1
	echo ;
	# foreach pathname, md5sum and objectname
done | grep ';[a-f0-9]' | while read path newhash otherhash newid indbpath; do

	# md5sum of the old file
	oldhash=$(git hash-object $path)
	# objectname of the old file
	oldid=$( git $dbargs show db:md5_obj.csv | grep $oldhash | awk -F ';' '{print $3}' | tail -n 1)
	patholdmd5file=$indbpath
	if ! test "$oldhash" = "$newhash" ; then
		# use the script history4fileversions.pl to retrieve all the objectnames between $oldid and $newid ($newid is included but not $oldid thanks to the tail -n +2).
		git $dbargs show "db:"$indbpath"/hist" | perl $path2bin"/history4fileversions.pl" "$oldid" "$newid" | tail -n +2 | while read versionid ; do
			hash=$( git $dbargs show db:md5_obj.csv | grep "$versionid" | awk -F ';' '{print $1}' | head -n 1)
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
			echo -n $path";"$hash";" ;
			git $dbargs show db:all_obj.csv | grep "$versionid" | head -n 1
			echo ;
		done
	else
        # it is a new file
        echo -n $path";"$newhash";" ;
        git $dbargs show db:all_obj.csv | grep "$newid" | head -n 1
        echo ;
	fi
done | grep ';' > /tmp/subadd_tasks.$$.tmp

#retrieve deletion task
cat /tmp/subadd_status.$$.tmp | grep " D " | sed 's/^ *[^ ]* *//' | while read path ; do
	find "$path" -type f | while read file ; do
		deletion_hash=$(git ls-tree HEAD "$file" | awk '{print $3}')
		if test "$deletion_hash" ; then
			deletion_id=$(git $dbargs show db:md5_obj.csv | grep "$deletion_hash" | awk -F ';' '{print $3}' | tail -n 1)
		if test "$deletion_id" ; then
			deletion_dirpath=$(git $dbargs grep  '^- '$deletion_id db | awk -F ':' '{print $1":"$2}' | sed 's|/ls|/id|' | head -n 1)
		if test "$deletion_dirpath" ; then
			deletion_dirid=$(git $dbargs show $deletion_dirpath)
			deletion_dirhash=$(git $dbargs show db:md5_obj.csv | grep $deletion_dirid | tail -n 1 | awk -F ';' '{print $1}')
			echo "deletion - $deletion_hash - $deletion_id - $deletion_dirpath - $deletion_dirid - $deletion_dirhash " >&2
			echo -n $file";"$deletion_dirhash";" ;
			git $dbargs show db:all_obj.csv | grep "$deletion_dirid" | head -n 1
		fi
		fi
		fi
		echo ;
	done
done | grep ';' >> /tmp/subadd_tasks.$$.tmp

# foreach create_time, owner, task, path and md5sum (sorted by date). A dummy line "#_END_" is read at the last iteration.
cat /tmp/subadd_tasks.$$.tmp | awk -F ';' '{print $8";"$6";"$7";"$1";"$2}END{print "#_END_ "}' | sort | while read date auteur task path hash; do
	# if the task changes (or it is the #_END_), commit the previous group of changes
	if test "$old" && ! test "$old" = "$auteur $task"; then
		if ! test "$mycomment" ; then
			mycomment="commentaire vide: $mytask"
		fi
		GIT_COMMITTER_DATE="$mydate" git commit -m "$mycomment" --date "$mydate" --author "$myauteur <$myauteur@eurocontrol.info>"
	fi
	if test "$path" && test "$hash"; then
		# perform the file change or creation in the working tree
		path2fileindb=$(git $dbargs show db:md5_obj.csv | grep $hash | awk -F ';' '{print $4}' | tail -n 1)
		#retrieve the content if exists
		if git $dbargs show db:$path2fileindb | grep content > /dev/null ; then
			mkdir -p $(dirname "$path")
			git $dbargs show db:$path2fileindb"/content" > "$path"
		#otherwise if there is a .dir file, it's a deletion
		elif git $dbargs show db:$path2fileindb | grep ls > /dev/null; then
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
	mycomment=$(git $dbargs show db:all_task.csv | grep "^$task[ ;]" | awk -F ';' '{print $1" "$3}')
done

# retrieve the stash to ensure the final commit will be faithfull to synergy
git stash pop > /dev/null

rm /tmp/subadd_status.$$.tmp /tmp/subadd_tasks.$$.tmp /tmp/subadd_content.$$.tmp
