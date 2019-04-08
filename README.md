# Eurocontrol's Rational CM Synergy to git

Run the migration script :

    ccm history <an_id> | perl history2gitcommands.pl "project title" | bash

If you don't has access to the ccm command, you can fake it (for example by a command that generate random content) :

    cat ccm_history.output | perl history2gitcommands.pl 'project title' 'echo \$RANDOM > program.c #' | bash

## Dump all objects of a base

    bash dump_ccm.sh <the_base> <path_to_dump>

The dump structure :

 - db/all_obj.csv : the csv of all objects description of the database
 - db/all_tasks.csv : the csv of all tasks of the database
 - db/all_projects.csv : the csv of all projects (revision) of the database
 - db/md5_obj.csv : the md5 and CMSynergy objectid of all the objects of the database
 - files/XX/YY/ZZZZZZZZZZZZZZZZZZZZZZZZZZZZ : the content of an object (XXYYZZZZZZZZZZZZZZZZZZZZZZZZZZZZ is the md5 of the content)
 - files/XX/YY/ZZZZZZZZZZZZZZZZZZZZZZZZZZZZ.history : the CMSynergy history of an object)

## Advanced conversion

    ccm history <version> | perl history2gitcommands.pl <repo_directory> "ccm" $PWD"/subadd.sh  <absolute_path_to_dump>/" | bash

