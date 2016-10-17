#!/usr/bin/env python

import glob
import os

 
path = '/Users/jeanettemumford/Documents/Research/Talks/MumfordBrainStats/ds008/'

subdirs = glob.glob('%s/sub[0-9][0-9][0-9]'%(path))

for dir in subdirs:  
    print dir
    os.system("mkdir %s/anatomy/extra"%(dir))
    os.system("mv %s/anatomy/inplane.nii.gz %s/anatomy/extra/inplane.nii.gz"%(dir, dir))
    os.system("mv %s/anatomy/highres001_brain.nii.gz %s/anatomy/extra/highres001_brain.nii.gz"%(dir, dir))
    os.system("mv %s/anatomy/highres001_brain_mask.nii.gz %s/anatomy/extra/highres001_brain_mask.nii.gz"%(dir, dir))
    os.system("mv %s/anatomy/inplane_brain.nii.gz %s/anatomy/extra/inplane_brain.nii.gz"%(dir, dir))


