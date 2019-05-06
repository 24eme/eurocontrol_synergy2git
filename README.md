# Eurocontrol's Rational CM Synergy to git

Run the migration script :

    ccm history <an_id> | perl history2gitcommands.pl <repo_path> | bash

If you don't has access to the ccm command, you can fake it (for example by a command that generate random content) :

    cat ccm_history.output | perl history2gitcommands.pl repo/ 'echo \$RANDOM > program.c #' | bash

## Dump all objects of a base

    bash dump_ccm.sh <the_base> <path_to_dump>

The dump structure :

 - ``db/all_obj.csv`` : the csv of all objects description of the database
 - ``db/all_tasks.csv`` : the csv of all tasks of the database
 - ``db/all_projects.csv`` : the csv of all projects (revision) of the database
 - ``db/md5_obj.csv`` : the md5 and CMSynergy objectid of all the objects of the database
 - ``files/XX/YY/ZZZZZZZZZZZZZZZZZZZZZZZZZZZZ`` : the content of an object (XXYYZZZZZZZZZZZZZZZZZZZZZZZZZZZZ is the md5 of the content)
 - ``files/XX/YY/ZZZZZZZZZZZZZZZZZZZZZZZZZZZZ.history`` : the CMSynergy history of an object)

## Advanced conversion

An advanced version of the history is avaliable. It allows to create a commit per project (revision), but aswell a commit (or more) by tasks.

The intermediate commits between project/revision is done by ``subadd.sh``. This script retrieves all the changed files and, thanks to their md5 checksums, the releted versions and their links to tasks. Thanks to the tasks, the script recreates the commits.

    ccm history <version> | perl history2gitcommands.pl <repo_directory> "ccm" $PWD"/subadd.sh  <absolute_path_to_dump>/" <internal_path> | bash

``<absolute_path_to_dump>`` is the dirctory generated thanks to ``dump_ccm.sh``.

``<internal_path>`` is a specific directory (in source of a ccm cfs) where directly get the files

## Integrating .gitignore files

If you want to ignore files, you can put a ``.gitignore`` file in the repo_directory before the conversion. The listed files (or the one mathing one of the listed partern), will be ignored.
