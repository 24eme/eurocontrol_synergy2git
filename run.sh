#!/bin/bash

if ! test -f "$1"; then
    echo "run.sh <config.inc>"
    exit;
fi

. $1

mkdir $FOLDER 2> /dev/null

if ! test -f $FOLDER/history; then
	VERSION_SMALL=$(cat $FOLDER_DUMP/db/all_projects.csv | grep ";$PROJECT;" | head -n 1 | cut -d ";" -f 2)
	VERSION_COMPLETE=$(cat $FOLDER_DUMP/db/all_obj.csv | grep ";$VERSION_SMALL$" | head -n 1 | cut -d ";" -f 2)

	ccm history $VERSION_COMPLETE > $FOLDER/history
fi

cat $FOLDER/history | perl history2gitcommands.pl $FOLDER "ccm" $PWD"/subadd.sh "$FOLDER_DUMP"/" $FOLDER_INTERNAL | bash
