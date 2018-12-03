# Eurocontrol's Rational CM Synergy to git

Run the migration script :

    ccm history <an_id> | perl history2gitcommands.pl "project title" | bash

If you don't has access to the ccm command, you can fake it (for example by a command that generate random content) :

    cat ccm_history.output | perl history2gitcommands.pl 'project title' 'echo \$RANDOM > program.c #' | bash


