#!/bin/sh

# Target directory = run in .feat dir

for feat in */ ; do
	cd $feat
	echo "<p>FEAT Directory = $feat <br>">> ../FEAT_summary.html

		for cope in {1..11} ; do
			echo "<p>COPE${cope} - zstat1 &nbsp;&nbsp;-&nbsp;&nbsp; C${cope} <br>
				<a href=$feat/cluster_zstat${cope}_std.html><IMG BORDER=0 SRC=$feat/rendered_thresh_zstat${cope}.png></a>"
		done >> ../FEAT_summary.html
			#append to FEAT_summary.html
	cd ../
done
