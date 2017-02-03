@ECHO OFF
REM *--------------------------------------
REM *- Install script for Text Mine
REM *--------------------------------------

REM *-- update the constants.pm file
perl utils/configure.pl
cd utils

REM *-- load dependent perl modules
perl load_mod.pl

REM *-- create and load the database
perl setup.pl

REM *-- copy files to web directories
cd ..
perl utils/install.pl
