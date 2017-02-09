#!/bin/sh
#*--------------------------------------
#*- Install script for Text Mine
#*--------------------------------------

#*-- update the constants.pm file
perl utils/configure.pl
echo -n "Finished configuration continue (y/n): "
read INP
if [ $INP = n ]; 
 then exit 
fi

#*-- generate the lsi executable
cd lsi; make clean; make; cd ../utils

#*-- load dependent perl modules
echo -n "Load dependent modules (y/n): "
read INP
if [ $INP = y ]; 
 then perl load_mod.pl
fi

#*-- create and load the database
echo -n "Create and load the database (y/n): "
read INP
if [ $INP = y ]; 
 then perl setup.pl
fi

#*-- copy files to web directories
echo -n "Install Text Mine (y/n): "
cd ..
read INP
if [ $INP = y ]; 
 then perl utils/install.pl
fi
