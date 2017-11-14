#!/bin/sh

# Run in .feat dir


for feat in */ ; do
	cd $feat
	echo "<p>FEAT Directory = $feat <br>">> ../REG_summary.html		
	echo "<p>Functional --> highres T1 <br>
		<a><IMG BORDER=0 SRC=$feat/reg/example_func2highres.png alt=example_func2highres.png WIDTH=2000></a>
	      <p>Highres T1 --> Standard <br>
		<a><IMG BORDER=0 SRC=$feat/reg/highres2standard.png alt=highres2standard.png WIDTH=2000></a>
	      <p>Functional --> Standard <br>
		<a><IMG BORDER=0 SRC=$feat/reg/example_func2standard.png alt=example_func2standard.png WIDTH=2000></a>" >> ../REG_summary.html
		#append to REG_summary.html
	cd ../
done