#!/usr/bin/python

# There is likely a better way to do this!  Please share if you know of one.  I know we can make an html file with all of the png files, but I've found this problematic if I'm ssh-ing into a linux system.  This will directly create a pdf file for each image type we need to evaluate.  The tricky part is adding the file path to the image, so we can identify who is problematic.

# Basically, I'm using python to create a text file with a huge command in it and then we run it.

import os
import glob

# We will start with the registration png files
outfile = "/Users/jeanettemumford/Documents/Research/Talks/MumfordBrainStats/ds008_R1.1.0_raw/QA/lev1_QA.html"
os.system("rm %s"%(outfile))

all_feats = glob.glob('/Users/jeanettemumford/Documents/Research/Talks/MumfordBrainStats/ds008_R1.1.0_raw/sub*/model/task001_run00*.feat/')

f = open(outfile, "w")
for file in list(all_feats):
  f.write("<p>============================================")
  f.write("<p>%s"%(file))
  f.write("<IMG SRC=\"%s/design.png\">"%(file))
  f.write("<IMG SRC=\"%s/design_cov.png\" >"%(file))
  f.write("<IMG SRC=\"%s/mc/disp.png\">"%(file))
  f.write("<IMG SRC=\"%s/mc/trans.png\" >"%(file))
  f.write("<p><IMG SRC=\"%s/reg/example_func2highres.png\" WIDTH=1200>"%(file))
  f.write("<p><IMG SRC=\"%s/reg/example_func2standard.png\" WIDTH=1200>"%(file))
  f.write("<p><IMG SRC=\"%s/reg/highres2standard.png\" WIDTH=1200>"%(file))
f.close()
