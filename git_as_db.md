2 Git and Synergy principles
============================

The two different tools have different approaches. In particular, git is very purist and minimalist.

2.1 Git principles
------------------

A git repository is a collection of commits. Commits are organized hierarchically (commits have generally one parent, the initial commit has 0 parent, merge commits have generally two parents). A commit has also an author, a date, a committer, a message and the id of a tree.

A tree stores a group of files together (similar to unix directories). This manages filenames, permissions, nested trees and files (named blob). For example:

```bash
[jfbocque@tarkin gitproj] git cat-file -p master^{tree}
040000 tree 2ba9c1eff96a2d03efae6df94d0ec9b709f50d97    ESCAPE_Supervision_Delivery
120000 blob fba579f4290a866397916d1aa58ab03285152c91    Oasis_Infrastructure_Delivery
100644 blob dbaa5006a803246f30bd3fc7d23ad5ba498a93c1    build.xml
040000 tree 29a422c19251aeaeb907175e9b3219a9bed6c616    build
040000 tree e685d91cd7a5d3ffc1a41520391fb3a7f9f862f3    products
040000 tree 44fe786417ed7eb8c2d374f324d285329a94a402    tools
```

objects stored in the repository are either commits, trees or blobs. They are identified by the hash of their content. For these three kinds of objects (commits, trees, blobs), the repository is an immutable database (data are added, but never modified). A result of this immutability is that there is no need to make snapshots or baselines, we just need to write down the hash of a commit or to tag it with a human friendly name. A branch is a pointer to a commit that is updated when a new child commit is added.

2.2 Synergy principles
----------------------

Synergy has a different philosophy: it is a database of versioned objects. As objects are mutable, synergy has a complex system of states and roles to handle permissions.

Versioned objects are identified by a four parts objectname that is composed of the name, the version, the type and an instance number (that allows two different objects to have the same name).

Objects are mainly files, directories or projects.

A task is a message (named synopsis) associated with a set of versions of modified objects.

The version of an object selected in a project id defined using rules (reconfigure properties) or manually.

Baselines are created to create a snapshot of a project at a given time and to change states so that objects require more privileges to be modified.

Synergy introduces also the notion of release that is used to create maintenance branches. When we start working on a new release, a baseline of the sources in the previous release is created. The reconfigure properties are a set of tasks that has to be applied on this baseline.

When a task is developed in an old release, it can be merged in more recent releases either using reconfigure properties or using a merge task.


3 Migration principles
======================

The first step is the preservation of most of the data of synergy using the script [dump_ccm.sh](https://github.com/24eme/eurocontrol_synergy2git/blob/master/dump_ccm.sh). This script mimic the behaviour of git by storing the files in a tree of directories indexed by the checksum of their content.

A second script [history2gitcommands.pl](https://github.com/24eme/eurocontrol_synergy2git/blob/master/history2gitcommands.pl) generates a bash script that will call the synergy command "ccm cfs" to copy baselines to file system, call a third script [subadd.sh](https://github.com/24eme/eurocontrol_synergy2git/blob/master/subadd.sh) to generate intermediate commits and git commit to commit baselines.

The third script has many limitations and is still a work in progress.

4 Issues
========

The work performed by 24eme highlights the difficulties to extract data from Synergy. It is possible to perform many kind of queries on the database, but without a working area, I have not found any way to read the content of a symlink object, or to know the content of a directory (my best results were using ccm diff between two directories).

The command "ccm cfs" allows to extract content of baselines, but loses the information about the objectname. The objectname is needed to find the history of objects. In order to retrieve the objectname, the checksum of content is used, but this is error prone because different objects may have the same content.

Before being able to use "ccm cfs", a script has to run to setup workarea properties of all projects. If we want to avoid disturbing production database, we need to perform a copy. This is quite a heavy process.

The extracted data are difficult to query if latter we want to browse old history.

Another idea for the extraction of data from Synergy would be to use git to store files and to extract enough data in the first step to work without synergy in step 2 and 3. Using data extracted in step 1 instead of synergy for steps 2 and 3 would also prove that extracted data are easy to access in the future. If subtle bugs are found in steps 2 or 3, it becomes possible to fix them without synergy and without starting from scratch.

In order to avoid bloating the repository and to test this idea more quickly, the files that are not is_product will not be archived.

4.1 Extracted data new structure
--------------------------------

The extracted data shall be stored in the same git repository as the migrated projects, but in a specific branch named "db".

The files shall be stored using the four parts of objectname as a path (`<type>/<name>/<instance>/<version>`) toward a file named "content". The history is stored in the same directory in a file named "hist".

After dumping the objects and tasks, the content of released project baselines is obtained by making copies of project (ccm cp) that are removed afterwards.

When we have a copy of a project, the content of each of its directories (a list of objectnames) can be queried using "ccm ls --f '%objectname'" and stored in a file named `"<type>/<name>/<instance>/<version>/<directory_path>/ls"`. The script takes profit of this recursive walkthrough inside projects to identify symlinks and store them in `symlink/<name>/<instance>/<version>/content`.

The first step shall be launched using the following command, then commit the changes:

```bash
/home/jfbocque/homemade/eurocontrol_synergy2git_old/dump_ccm.sh arh /development/git/jef/arh_repo
```

This script is intended to be easily interrupted and relaunched. In this case, the single commit of branch db should be amended.

4.2 Advantages and drawbacks
----------------------------

The purpose of this new data extraction is to be more human friendly than a tree of checksums and to be complete enough to avoid synergy during step 2 and 3.

By using git, we benefit of all the features of the tool. It performs deduplication, compression and efficient storage of objects.

Performing a checkout of branch db is expensive because it decompress all files into the file system, but it is seldom needed because using "git show", it is possible to visualize any file of the branch db without being in that branch.

For example, we can list the content of directory ADS/products of a given version of project using:

```bash
git show db:project/ADS/ARH#1/ACE2005A_sun_20050927/ADS/products/ls
Configuration-1:ascii:ARH#2062
Makefile-3.1.2:makefile:ARH#1
```

We can show the content of the Makefile using:

```bash
git show db:makefile/Makefile/ARH#1/3.1.2/content
```

The organisation of the extracted data facilitates all the queries we used to perform on synergy. It is almost easier than with the synergy GUI. We can even compare versions of files:

```bash
git diff db:makefile/Makefile/ARH#1/3.1.2/content db:makefile/Makefile/ARH#1/4/content
```

This storage using git is inspired by the work performed by 24eme (that was using checksum for storage). The files all_obj, all_task and md5_obj imagined by 24eme have been preserved,with a slightly different content (git hash-object is used for hashing instead of md5sum).

During the lengthy extraction of data, we  can monitor the  progress (projects are handled in alphabetical order). If a new need is identified, it provides a simple structure to store additional data. This simple structure has been used to store the content of project baselines in order to avoid the usage of "ccm cfs" in later stages.

Creation and removal of projects may cause creation of automatic tasks. They are removed later using:

```bash
cli_arh
ccm set role ccm_admin
ccm query -t task "resolver='eris_viewer'"
ccm delete @
```

The full adaptation of the step 2 and 3 to this new structure is more work than what can be done in this short study.

5 Conclusions
=============

Rebuilding the history of projects using only tasks instead of project baselines seems infeasible.

The approach in 3 steps imagined by 24eme seems the only viable. This study has mainly documented the approach of 24eme and changed the first step in order to provide a better foundation for the migration of projects.

The git repo used to extract arh is available in tarkin:/development/git/jef/arh_repo.

With the new structure it will also be easy to build nice visualisation of old synergy projects in a browser.

Addendum
========
An additional script `my_cfs` uses the extracted data to copy a released project toward filesystem.
