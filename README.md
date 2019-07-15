# Eurocontrol's Rational CM Synergy to git

Run the migration script :

    ccm history <an_id> | perl history2gitcommands.pl <repo_path> <dump_git_repo> | bash

This command runs the advanced version of the history. It creates a commit per project (revision), but aswell a commit (or more) by tasks.

The intermediate commits between project/revision is done by ``subadd.sh``. This script retrieves all the changed files and, thanks to their git checksums, the releted versions and their links to tasks. Thanks to the tasks, the script recreates the commits.


## Dump all objects of a base

    perl dump_ccm.pl  <synergy_db_name> <dump_dir_path>

The dump structure :

 - ``all_obj.csv`` : the csv of all objects description of the database
 - ``all_tasks.csv`` : the csv of all tasks of the database
 - ``all_projects.csv`` : the csv of all projects (revision) of the database
 - ``md5_obj.csv`` : the md5 and CMSynergy objectid of all the objects of the database
 - ``ctype/name/instance/version/content`` : the content of an object
 - ``ctype/name/instance/version/id`` : the synergy id
 - ``ctype/name/instance/version/ls`` : the content of the object (for projects or directories)

## Advanced conversion


    .../subadd.sh  <absolute_path_to_dump>/" <internal_path> | bash

``<absolute_path_to_dump>`` is the dirctory generated thanks to ``dump_ccm.sh``.

``<internal_path>`` is a specific directory (in source of a ccm cfs) where directly get the files

## Integrating .gitignore files

If you want to ignore files, you can put a ``.gitignore`` file in the repo_directory before the conversion. The listed files (or the one mathing one of the listed partern), will be ignored.
