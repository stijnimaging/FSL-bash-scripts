#!/bin/sh

# Target directory = run in .feat dir
DATA=$PWD

cd ${DATA}


	for cope in 1; do
	
		echo "	<p>COPE${cope} - zstat1 &nbsp;&nbsp;-&nbsp;&nbsp; C${cope} <br>
			<a href=cluster_zstat${cope}_std.html><IMG BORDER=0 SRC=rendered_thresh_zstat${cope}.png></a> "
	done
 >> ..//FEAT_summary.html
