#!/bin/bash

#thsi script offers a basic fmri preprocessing
#we do
	#motion correction with mc flirt towards the last volume (closest to PA scan for subsequent optimal topup correction)
	#motion outliers with fsl_motion_outliers. 
		#current measure: FD , task threshold: 0.9, resting state threshold: 0.4
		#motion confound mstrix NOT created if no volume exceed threshold!
	#topup: is done assuming 5 volumes for PA and that the PA scan is done after the encoding scan 
		#(you can change the order from the function and the number of volumes from the acq file)
	#melodic: is done by loading up the gui (you need to press "Go")
		#includes BBR, FNIRT to 1mm MNI, 100Hz highpass filtering, no smoothing and melodic
	#fix: is done with 30 (found optimal in our testing)
	#pnm:

PROGNAME=$(basename $0)

function error_exit
{
#	----------------------------------------------------------------
#	Function for error control
#		Accepts 1 argument:
#			string containing descriptive error message
#	----------------------------------------------------------------
	echo "${PROGNAME}: ${1:-"Unknown Error"}" 1>&2
	exit 1
}

motion_correction () {
	local task=$1
	local subject=$2
	local input=$3
	local output=$4

	mkdir -p ${output}/${subject}/func/tmp
	mkdir -p ${output}/${subject}/func/tmp/mc


	num_vol=`fslval ${input}/${subject}/func/${subject}_${task}_bold.nii.gz dim4`
	num_vol=`expr $num_vol - 1`


	in_nii=${input}/${subject}/func/${subject}_${task}_bold.nii.gz
	out_nii="${output}/${subject}/func/tmp/mc/${subject}_${task}_bold_moco.nii.gz"

	(mcflirt -in $in_nii -out $out_nii -refvol $num_vol -mats -plots) || error_exit "cannot motion correct $in_nii"
	mv $out_nii ${output}/${subject}/func/${subject}_${task}_bold_corrected.nii.gz
}

motion_outliers () {

	local task=$1
	local subject=$2
	local input=$3
	local output=$4
	local threshold=$5

	mkdir -p ${output}/${subject}/func/tmp
	mkdir -p ${output}/${subject}/func/tmp/motion_outliers

	in_nii=${input}/${subject}/func/${subject}_${task}_bold.nii.gz
	out_nii="${output}/${subject}/func/tmp/motion_outliers/${subject}_${task}_bold"

	(fsl_motion_outliers -i $in_nii -o ${out_nii}_motion_confound.txt \
	-p ${out_nii}_FDplot.png -s ${out_nii}_FDvalues.txt --fd --thresh=$threshold) || error_exit "cannot do fsl_motion_outliers for $in_nii"

}

topup_apply () {

	local task=$1
	local subject=$2
	local input=$3
	local output=$4
	local acq_param=$5

	mkdir -p ${output}/${subject}/func/tmp
	mkdir -p ${output}/${subject}/func/tmp/topup

	cp ${output}/${subject}/func/${subject}_${task}_bold_corrected.nii.gz ${output}/${subject}/func/tmp/topup/${subject}_${task}_bold_corrected.nii.gz || error_exit "topup input fail 1"
	cp ${input}/${subject}/fmap/${subject}_${task}_PA.nii.gz ${output}/${subject}/func/tmp/topup/${subject}_${task}_PA.nii.gz || error_exit "topup input fail 2"

	dirpath=${output}/${subject}/func/tmp/topup
	echo $dirpath
	cd $dirpath

	file_to_slice=${subject}_${task}_bold_corrected.nii.gz;
	echo $file_to_slice
	#file to correct with (blip down)
	file_to_correct_with=${subject}_${task}_PA.nii.gz;
	echo $file_to_correct_with
	#order of scans (PA then scan or opposite)
	order_variable=2;

	#get dim4 dimensions of image
	a=`fslinfo ${file_to_slice} | grep dim4 | awk '{print $2;}'`;
	a=`echo $a|awk '{print $1;}'`;
	#if you have PA volume number=10, then you need 10 volumes
	#modify otherwise
	#and modify acq_param too
	let a=a-5;


	if   [ "${order_variable}" -eq "1" ]; then
		pos_slice=0;
	elif [ "${order_variable}" -eq "2" ]; then
		pos_slice=${a};
	else
		echo "wrong input";
	fi

	#cut away relevant part of the file for correction
	fslroi ${file_to_slice} AP_${file_to_slice} 0 -1 0 -1 0 -1 ${pos_slice} 5 || error_exit "topup fslroi fail";

	fname=`$FSLDIR/bin/remove_ext ${file_to_slice}`;

	#merge blip up and blip down to one
	#do something about which file it picks to merge
	fslmerge -t input_topup_${file_to_slice} AP_${file_to_slice} ${file_to_correct_with} || error_exit "topup merge fail";
	#fslview input_topup_${file_to_slice} ${file_to_slice} $file_to_correct_with


	#see if we need to cut away top slice (topup subsampling prerequisite)
	z_slice_num=`fslinfo input_topup_${file_to_slice} | grep dim3 | awk '{print $2;}'`;
	z_slice_num=`echo $z_slice_num|awk '{print $1;}'`;

	if   [ $((z_slice_num%2)) -ne 0 ]; then
		let z_slice_num=z_slice_num-1;
		fslroi input_topup_${file_to_slice} input_topup_${file_to_slice} 0 -1 0 -1 0 ${z_slice_num} 0 -1
		fslroi ${file_to_slice} ${file_to_slice} 0 -1 0 -1 0 ${z_slice_num} 0 -1
	fi


	#calculate epi distortion with topup
	topup --imain=input_topup_${file_to_slice} --datain=$acq_param \
	--config=$FSLDIR/etc/flirtsch/b02b0.cnf --out=${fname}_topup  --iout=${fname}_hifi_topup || error_exit "topup distortion estimation fail";

	#apply distortion correction to file
	applytopup --imain=${file_to_slice} --inindex=1 --method=jac --datain=$acq_param \
	--topup=${fname}_topup --out=${fname}_corrected || error_exit "topup applytopup fail";

	echo "done with" 
	echo ${subject}_${task};

	mv ${fname}_corrected.nii.gz ${output}/${subject}/func/${subject}_${task}_bold_topupcorrected.nii.gz

}


run_melodic () {
	local task=$1
	local subject=$2
	local input=$3
	local output=$4
	local melodic_template=$5

	mkdir -p ${output}/${subject}/func/tmp
	cp -rf $melodic_template ${output}/${subject}/func/tmp/${task}design_melodic.fsf

	echo $subject $task "melodic"

	input_file=${output}/${subject}/func/${subject}_${task}_bold_topupcorrected.nii.gz
	nvol_fmri=`fslval $input_file dim4`
	output_melodic=${output}/${subject}/func/${subject}_${task}_melodic
	input_brain=${input}/${subject}/anat/${subject}_T1w_brain.nii.gz

	echo $input_file
	echo $nvol_fmri
	echo $output_melodic
	echo $input_brain
	sed -e "s@OUTPUT_FILE@$output_melodic@g; s@NVOL@$nvol_fmri@g; s@INPUT_FMRI_FILE@$input_file@g; s@INPUT_T1_BRAIN@$input_brain@g" ${output}/${subject}/func/tmp/${task}design_melodic.fsf\
	 > ${output}/${subject}/func/tmp/${subject}_${task}_design_melodic.fsf \
	|| error_exit "cannot do melodic template for $subject $task"
	wait ${!}
	melodic_gui ${output}/${subject}/func/tmp/${subject}_${task}_design_melodic.fsf
}

run_fix () {
	local task=$1
	local subject=$2
	local input=$3
	local output=$4

	echo $subject $task "fix"
	#get motion parameters to melodic file
	#then do fix and cleanup
	mel_file=${output}/${subject}/func/${subject}_${task}_melodic.ica
	mkdir -p ${mel_file}/mc
	echo $mel_file
	#echo ${mel_file}/mc/prefiltered_func_data_mcf.par
	cp ${output}/${subject}/func/tmp/mc/${subject}_${task}_bold_moco.nii.gz.par ${mel_file}/mc/prefiltered_func_data_mcf.par \
	|| error_exit "cannot copy motion file for fix $subject $task"
	fix $mel_file /usr/local/fix/training_files/HCP_hp2000.RData 30 || error_exit "cannot do fix $subject $task"

	cp ${output}/${subject}/func/${subject}_${task}_melodic.ica/filtered_func_data_clean.nii.gz ${output}/${subject}/func/${subject}_${task}_fixed.nii.gz

}

phys_preproc () {
	local task=$1
	local subject=$2
	local input=$3
	local output=$4

	echo $subject $task "make phys regressors"
	phys_file=${output}/${subject}/func/physio
	mkdir -p $phys_file
	num_vol=`fslval ${input}/${subject}/func/${subject}_${task}_bold.nii.gz dim4`
	#num_vol=`expr $num_vol - 1`
	resp_file=${input}/${subject}/func/${subject}_${task}_physio.resp
	puls_file=${input}/${subject}/func/${subject}_${task}_physio.puls

	keep_samples=$((${num_vol}*2*50));
	head -${keep_samples} $resp_file > ${phys_file}/${subject}_${task}_physio_cropped.resp
	head -${keep_samples} $puls_file > ${phys_file}/${subject}_${task}_physio_cropped.puls


	output_trigger=${phys_file}/${subject}_${task}_trigger.txt
	rm $output_trigger
	touch $output_trigger
	x=1
	while [ $x -le $num_vol ]
	do 
		echo "1" >> ${output_trigger}
		printf '0\n%.0s' {1..99} >>${output_trigger}
		x=$((x+1))
	done

	paste ${phys_file}/${subject}_${task}_physio_cropped.resp ${phys_file}/${subject}_${task}_physio_cropped.puls ${output_trigger} \
	> ${phys_file}/${subject}_${task}_physio.txt || error_exit "cannot make physio cropped file"

	#open -e ${phys_file}/${subject}_${task}_physio.txt
}

pnm_regressors () {
	local task=$1
	local subject=$2
	local input=$3
	local output=$4

	echo $subject $task "make phys regressors"
	phys_file=${output}/${subject}/func/physio
	input_pnm_file=${phys_file}/${subject}_${task}_physio.txt

	pnm_file=${output}/${subject}/func/physio/${subject}_${task}_pnm/pnm
	mkdir -p ${output}/${subject}/func/physio/${subject}_${task}_pnm


	/usr/local/fsl/bin/fslFixText $input_pnm_file ${pnm_file}_input.txt
	/usr/local/fsl/bin/pnm_stage1 -i ${pnm_file}_input.txt -o ${pnm_file} -s 50 --tr=2.0 --smoothcard=0.1 --smoothresp=0.1 --resp=1 --cardiac=2 --trigger=3

	/usr/local/fsl/bin/fslFixText $input_pnm_file ${pnm_file}_input.txt


	/usr/local/fsl/bin/pnm_stage1 -i ${pnm_file}_input.txt -o ${pnm_file} -s 50 --tr=2.0 --smoothcard=0.1 --smoothresp=0.1 --resp=1 --cardiac=2 --trigger=3
	/usr/local/fsl/bin/popp -i ${pnm_file}_input.txt -o ${pnm_file} -s 50 --tr=2.0 --smoothcard=0.1 --smoothresp=0.1 --resp=1 --cardiac=2 --trigger=3
	
	open ${pnm_file}_pnm1.html 
	wait ${!}

	cd $pwd
	obase=$pnm_file
	# if [ $# -gt 0 ] ; then 
	# 	/usr/local/fsl/bin/popp -i ${pnm_file}_input.txt \
	# 	-o ${pnm_file} -s 50 --tr=2.0 --smoothcard=0.1 --smoothresp=0.1 --resp=1 --cardiac=2 --trigger=3 $@ ; 
	# fi
		/usr/local/fsl/bin/pnm_evs -i ${output}/${subject}/func/${subject}_${task}_bold_topupcorrected.nii.gz \
		-c ${pnm_file}_card.txt -r ${pnm_file}_resp.txt \
		-o $pnm_file --tr=2.0 --oc=4 --or=4 --multc=2 --multr=2 \
		--slicetiming=${input}/slicetimes.txt
	ls -1 `/usr/local/fsl/bin/imglob -extensions ${obase}ev0*` > ${pnm_file}_evlist.txt

}

run_pnm_feat () {
	local task=$1
	local subject=$2
	local input=$3
	local output=$4
	local melodic_template=$5

	mkdir -p ${output}/${subject}/func/tmp
	cp -rf $melodic_template ${output}/${subject}/func/tmp/${task}design_pnmfeat.fsf

	echo $subject $task "feat PNM"
	#maybe add a check that FIX has run already correctly!
	input_file=${output}/${subject}/func/${subject}_${task}_melodic.ica/filtered_func_data_clean.nii.gz
	nvol_fmri=`fslval $input_file dim4`
	output_melodic=${output}/${subject}/func/${subject}_${task}_feat_pnm
	input_brain=${input}/${subject}/anat/${subject}_T1w_brain.nii.gz

	pnm_evlist=${output}/${subject}/func/physio/${subject}_${task}_pnm/pnm_evlist.txt
	ev1=${output}/${subject}/func/GLM_task_EV/enc-retr_emo.txt
	ev2=${output}/${subject}/func/GLM_task_EV/enc-retr_neu.txt
	ev3=${output}/${subject}/func/GLM_task_EV/enc-retrWR_emo.txt
	ev4=${output}/${subject}/func/GLM_task_EV/enc-retrWR_neu.txt


	sed -e "s@OUTPUT_FILE@$output_melodic@g; s@NVOL@$nvol_fmri@g; s@INPUT_FMRI_FILE@$input_file@g; s@PNM_EV_LIST@$pnm_evlist@g; s@EV1_FILE@$ev1@g; s@EV2_FILE@$ev2@g; s@EV3_FILE@$ev3@g; s@EV4_FILE@$ev4@g; s@INPUT_T1_BRAIN@$input_brain@g" ${output}/${subject}/func/tmp/${task}design_pnmfeat.fsf\
	 > ${output}/${subject}/func/tmp/${subject}_${task}_design_pnm_feat.fsf \
	|| error_exit "cannot do feat PNM template for $subject $task"
	wait ${!}
	#open -e ${output}/${subject}/func/tmp/${subject}_${task}_design_pnm_feat.fsf
	feat ${output}/${subject}/func/tmp/${subject}_${task}_design_pnm_feat.fsf || error_exit "feat PNM failed for $subject $task"
}

pnm_noise_component () {
	local task=$1
	local subject=$2
	local input=$3
	local output=$4

	#save fixed fMRI data
	input_file=${output}/${subject}/func/${subject}_${task}_melodic.ica/filtered_func_data_clean.nii.gz
	#mv ${output}/${subject}/func/${subject}_${task}_melodic.ica/filtered_func_data_clean.nii.gz ${output}/${subject}/func/${subject}_${task}_fixed.nii.gz

	pnm_feat_noise=${output}/${subject}/func/${subject}_${task}_feat_pnm.feat/stats/res4d.nii.gz
	#set up pnm ica file
	mkdir -p ${output}/${subject}/func/tmp/${subject}_${task}_pnm.ica
	cp -rf ${output}/${subject}/func/${subject}_${task}_melodic.ica ${output}/${subject}/func/tmp/${subject}_${task}_pnm.ica 
	cp $pnm_feat_noise ${output}/${subject}/func/tmp/${subject}_${task}_pnm.ica/filtered_func_data_clean.nii.gz
	rm ${output}/${subject}/func/tmp/${subject}_${task}_pnm.ica/mc/prefiltered_func_data_mcf_conf.nii.gz
	rm ${output}/${subject}/func/tmp/${subject}_${task}_pnm.ica/mc/prefiltered_func_data_mcf_conf_hp.nii.gz
	#run fix
	fix ${output}/${subject}/func/tmp/${subject}_${task}_pnm.ica /usr/local/fix/training_files/HCP_hp2000.RData || error_exit "cannot do fix $subject $task"
	pnm_noise_fixed=${output}/${subject}/func/tmp/${subject}_${task}_pnm.ica/filtered_func_data_clean.nii.gz
	#demean and subtract from fixed fmri data
	fslmaths $pnm_noise_fixed -Tmean -mul -1 -add $pnm_noise_fixed ${output}/${subject}/func/${subject}_${task}_pnm_noise_fixed.nii.gz
	fslmaths ${output}/${subject}/func/${subject}_${task}_fixed.nii.gz -sub ${output}/${subject}/func/${subject}_${task}_pnm_noise_fixed.nii.gz ${output}/${subject}/func/${subject}_${task}_fixed_pnmed.nii.gz
	#demean and subtract from fixed fmri data
}


slice_timing_correction () {
	local task=$1
	local subject=$2
	local input=$3
	local output=$4

	input_file=${output}/${subject}/func/${subject}_${task}_fixed.nii.gz
	slicetimer \
	--in=${input_file} \
	--out=$(dirname $input_file)/$(basename $input_file .nii.gz)_slicecorr.nii.gz \
	--tcustom=/Users/nikos/Locus1/BIDS_nii_structure/slicetimes_in_TR_fractions.txt \
	--repeat=2 \
	|| error_exit "cannot slice correct $subject $task"

}

#	----------------------------------------------------------------
#	parameters  setup
#		we assume that within the dir_path there are a bunch of subjects files 
#		and within them another folder with unpacked dcm data
# 		
#	----------------------------------------------------------------

BIDS_nii_folder=/Users/nikos/Locus1/BIDS_nii_structure

subject_list=${BIDS_nii_folder}/subjectlist_behav.txt
acq_param=${BIDS_nii_folder}/acq_params.txt
melodic_template=${BIDS_nii_folder}/template_melodic.fsf
output_file=${BIDS_nii_folder}/BIDS_proc
feat_pnm_enc_template=${BIDS_nii_folder}/template_pnm_enc_feat.fsf


fmri_array=( ret enc rs1 rs2 )
task_array=( ret enc )
rs_array=( rs1 rs2 )

#	----------------------------------------------------------------
#	commands
#	----------------------------------------------------------------

#make processing file
mkdir -p $output_file || error_exit "cannot make output file"


#go through all subjects in list
cat $subject_list | while read line
do
	echo $$
   # #motion correction
   # echo "Motion correction"
   # for task in "${fmri_array[@]}"; do motion_correction $task $line $BIDS_nii_folder $output_file & done || error_exit "cannot do motion correction for $line"
   # wait ${!}
   # echo "motion outliers"
   # #motion outliers for task
   # for task in "${task_array[@]}"; do motion_outliers $task $line $BIDS_nii_folder $output_file 0.9 & done || error_exit "cannot find motion outliers for $line"
   # wait ${!}
   # #motion outliers for resting state
   # for task in "${rs_array[@]}"; do motion_outliers $task $line $BIDS_nii_folder $output_file 0.4 & done || error_exit "cannot find motion outliers for $line"
   # wait ${!}
   # echo "topup"
   # for task in "${fmri_array[@]}"; do topup_apply $task $line $BIDS_nii_folder $output_file $acq_param & done || error_exit "cannot do topup for $line"
   # wait ${!}
  
   # echo "melodic"
   # for task in "${fmri_array[@]}"; do run_melodic $task $line $BIDS_nii_folder $output_file $melodic_template & done || error_exit "cannot do melodic for $line"  
   # wait ${!}
   # echo $$
   # for task in "${fmri_array[@]}"; do run_fix $task $line $BIDS_nii_folder $output_file & done || error_exit "cannot do fix for $line"  
   # wait ${!}

   # #make physiological regressors
   # echo $$
   # for task in "${fmri_array[@]}"; do phys_preproc $task $line $BIDS_nii_folder $output_file & done || error_exit "cannot make phys file for $line"  
   # wait ${!}
   # echo $$
   # for task in "${fmri_array[@]}"; do pnm_regressors $task $line $BIDS_nii_folder $output_file & done || error_exit "cannot make pnm regressors for $line"  
   # wait ${!}
   # #run feat to find PNM residuals
   # task="enc"
   # echo $$
   # run_pnm_feat $task $line $BIDS_nii_folder $output_file $feat_pnm_enc_template & done || error_exit "cannot feat pnm for $line"  
   # wait ${!}  
   echo "slice time correction $line"
   for task in "${fmri_array[@]}"; do slice_timing_correction $task $line $BIDS_nii_folder $output_file & done 
   #|| error_exit "cannot do slice timing correction for $line"  
   wait ${!}
done


