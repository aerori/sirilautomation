#!/bin/bash

## I don't like this but it's here to override using all threads and for more customization later.
while getopts 't:qds:h' option; do
	case "$option" in
		t)
			threads=$OPTARG
			;;
		q)
			silent=true
			;;
		d)
			onlyDev=true
			;;
		s)
			#script=$OPTARG
			;;
		h)
			echo -e "Usage: `basename $0` [OPTIONS]\n\n  -t\tthe number of CPU threads to use, default is max available according to /proc/cpuinfo\n  -q\t\"quiet\": no log, warning, or error output from `basename $0`\n  -d\tonly develop camera raw images, do not stack\n  -s\tscript to use for stacking (name of builtin or path to external), bypasses raw developing (does nothing at the moment but here to remind me to implement it)\n  -h\tthis help menu\n"
			exit 1
			;;
		?)
			echo -e "Usage: `basename $0` [-t THREADS] [-q] [-d] [-s SCRIPT NAME/PATH (does nothing currently, see -h] [-h]\nTry '`basename $0` -h' for more information."
			exit 1
			;;
	esac
done
shift "$(($OPTIND -1))"

if [ -z $silent ]; then
	log(){ echo -e "\e[1m[OSCProcessing - LOG]\t\t$1\e[m";}
	warning(){ echo -e "\e[1;33m[OSCProcessing - WARNING]\t$1\e[m";}
	error(){ echo -e "\e[1;31m[OSCProcessing - ERROR]\tCaught exit code $?: $1\e[m" && exit 1;}
else
	log(){ :;}
	warning(){ :;}
	error(){ exit 1;}
fi

## Check for dependencies
which bc > /dev/null || error "No usable version of bc found. Check your \$PATH or install bc"

if which dcraw_emu > /dev/null; then	## I still need to benchmark these to figure out which is faster
	dcraw=dcraw_emu
elif which dcraw > /dev/null; then
	dcraw=dcraw
else
	error "No usable version of dcraw found. Check your \$PATH or install dcraw"
fi
log "Using $dcraw"

if [ -z $onlyDev ]; then
	if which siril-cli > /dev/null; then
		siril=siril-cli
	elif which siril > /dev/null; then
		siril=siril
	else
		error "No usable version of siril found. Check your \$PATH or install siril"
	fi
	sirilVersion=`$siril -v | cut -d " " -f2- | rev | cut -d "-" -f2- | rev`	## Needed for my fancy custom siril scripts
	log "Using $siril version $sirilVersion or equivalent"
else
	log "Not using siril"
fi

## Copy data to temporary work directory (symlinks would be nice but don't work with dcraw), while checking to see what kind of data we have here
log "Copying data to temporary work directory"
rm -rf developed/
mkdir developed/

ls lights/ > /dev/null && for i in lights/*; do cp $i developed/lights_`basename $i`; done || error "No lights. Make sure you have camera raw light frames in lights/"

ls darks/ > /dev/null && darksPresent=true && for i in darks/*; do cp $i developed/darks_`basename $i`; done || darksPresent=false
log "Using darks: $darksPresent"

ls flats/ biases/ > /dev/null && flatsPresent=true && for i in {flats,biases}; do for n in $i/*; do cp $n developed/$i\_`basename $n`; done; done || flatsPresent=false
log "Using flats: $flatsPresent"

cd developed/

[ -z $threads ] && threads=`grep -c ^processor /proc/cpuinfo`
log "Using $threads threads"

files=`find . -type f | wc -l`
log "Processing $files images"

## Split files evenly into one directory for each thread available
for ((i=1; i<=$threads; i++)); do
	mkdir $i/
	for n in `find . -maxdepth 1 -type f | head -n "$(( \`echo \"$files/$threads\" | bc\`+1))"`; do
		mv $n $i/
	done
done

## Develop images
log "Hang tight; this will take nine years"

for i in `find ./* -type d`; do
	($dcraw -T -o 0 -a -q 1 -f -m 1 -H 5 -6 -t 0 $i/* && mv $i/*.tiff ./)&
done
wait

for ((i=1; i<=$threads; i++)); do rm -rf $i/; done

## Put developed images into appropriate directories for siril script and determine which script to use
log "Getting developed images ready"
mkdir lights/ && mv lights_*.tiff lights/
if [[ $darksPresent == "true" ]]; then
	script=Preprocessing_WithoutFlat
	log "Lights and darks ready"
	mkdir darks/ && mv darks_*.tiff darks/
	if [[ $flatsPresent == "1" ]]; then
		script=Preprocessing
		log "Lights, darks, biases, and flats ready"
		mkdir flats/ biases/
		mv flats_*.tiff flats/
		mv biases_*.tiff biases/
	fi
else
	if [[ $flatsPresent == "true" ]]; then
		script=Preprocessing_WithoutDark
		log "Lights, biases, and flats ready"
		mkdir flats/ biases/
		mv flats_*.tiff flats/
		mv biases_*.tiff biases/
	else
		script=Preprocessing_WithoutDBF
		log "Lights ready"
	fi
fi

if [ $onlyDev ]; then
	log "Developing images completed, exiting now"
	exit 0
fi

log "Handing over to siril."
siril-cli -d . -s /usr/local/share/siril/scripts/OSC_$script.ssf	##This will soon be obsolete with custom siril scripts

mv result*.fit ../
cd ../

log "Cleaning up and exiting"
rm -rf developed/
exit 0
