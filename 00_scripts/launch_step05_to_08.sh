#!/bin/bash
#Date:13-02-23
#Author QR
# WARNING STILL BETA #! 

source ../config/config
source config/colors 

##  ------------------------ general parameters --------------------------------  ##
while [ $# -gt 0 ] ; do
  case $1 in
    -g | --genome) genome="$2" ;echo "the genome file  is: $genome" >&2;;
    -s | --haplotype) haplotype="$2" ;echo "the haplotype name will be $haplotype" >&2;;
    -b | --bam )    bamlist="$2" ; echo "the optional bamlist of bam files will be $bamlist " >&2;;
    -m | --mask )   Mask="$2" ; echo "unknown TE will be removed after repeatemasking" >&2;;
    -r | --rna )    RNAseq="$2" ; echo "Is RNAseq provided ? $RNAseq " >&2;; 
    -f | --fungus ) fungus="$2" ; echo "Do species belong to fungi? $fungus" >&2;;
    -h | --help) echo -e "Option required:
    -g/--genome \t the reference genome file 
    -s/--haplotype\t the haplotype name (used for database building and basename in several steps)
    Optional:
    -m/--mask\t a string stating wether unknown TE should be removed for genome annotation (YES/NO) -- default: YES
    -r/--ref \t a string stating wether RNAseq data should be used (YES/NO) -- default: NO
    " >&2;exit 1;;
    esac
    shift
done

if [ -z "$genome" ] || [ -z "$haplotype" ] ; then
    echo >&2 "Fatal error: Ref genome (-g), and haplotype name (-s) not defined\n
    see manual with -h or --help"
exit 2
fi

#optional parameters:
if [ -z "$Mask" ] ; then
    Mask=YES
fi

if [ -z "$RNAseq" ] ; then 
  RNAseq=NO
fi

# ------------------ run RepeatModeler and RepeatMasker ------------------  ##

#check that no repeatmodeler output already exist:
rm_file="03_genome/genome.wholemask.fa"

if [  -e "$rm_file" ] ; then 
    echo -e "\n-----------------------------------------------------"
    echo -e "\trepeatmodeler output already exist\tnwill skip this step"; 
    echo -e "-----------------------------------------------------\n"
else 
    echo -e "\n-----------------------------------------------------"
    echo -e "no repeatmodeller output \n will launch repeatmodeller " ; 
    echo -e "-----------------------------------------------------\n"
    ../00_scripts/05_repeatmodeler.sh "$genome" "$haplotype" "$Mask" 2>&1 |tee log_rm
    if [ $? -eq 0 ]; then
        echo -e "---- repeatmodeler run successfull ----\n"
    else
        echo -e "repeatmodeler failed.\n
        check the provided libraries and software dependancies"   
        exit 
    fi
fi


# -------------------- run Braker  ---------------------------- #

#setting up path prior to running busco: 
tsebrapath=$(command -v tsebra.py |xargs dirname )
cdbpath=$(command -v cdbfasta |xargs dirname )
protpath=$(command -v prothint.py |xargs dirname)
gmarkpath=$(command -v gmes_petap.pl |xargs dirname)
augbin=$(command -v augustus |xargs dirname)
augscripts=$(echo $augbin  |sed 's/bin/scripts/' )
augconf=$(echo $augbin  |sed 's/bin/config/' )

#verify again that all path exist -----
[[ -z "$tsebrapath" ]] && { echo "Error: tsebra.py not found"; exit 1; }
[[ -z "$cdbpath" ]] && { echo "Error: cdbfasta not found"; exit 1; }
[[ -z "$protpath" ]] && { echo "Error: prothint not found"; exit 1; }
[[ -z "$gmarkpath" ]] && { echo "Error: genemark not found"; exit 1; }
[[ -z "$augbin" ]] && { echo "Error: Augustus binaries not found"; exit 1; }

# reshape braker code prior to run:
sed -i "s#CDB_PATH#export CDBTOOLS_PATH=$cdbpath#" ../00_scripts/06_braker.sh
sed -i "s#TSEBR_PATH#export TSEBRA_PATH=$tsebrapath#" ../00_scripts/06_braker.sh
sed -i "s#PROTH_PATH#export PROTHINT_PATH=$protpath#" ../00_scripts/06_braker.sh
sed -i "s#GMARK_PATH#export GENEMARK_PATH=$gmarkpath#" ../00_scripts/06_braker.sh
sed -i "s#AUGCO_PATH#export AUGUSTUS_CONFIG_PATH=$augconf#" ../00_scripts/06_braker.sh
sed -i "s#AUGBI_PATH#export AUGUSTUS_BIN_PATH=$augbin#" ../00_scripts/06_braker.sh
sed -i "s#AUGSC_PATH#export AUGUSTUS_SCRIPTS_PATH=$augscripts#" ../00_scripts/06_braker.sh

echo "---- running braker now on $haplotype ----- " 
echo "see details in braker_log in case of bugs" 
../00_scripts/06_braker.sh 03_genome/genome.wholemask.fa $haplotype $RNAseq $fungus $bamlist 2>&1 |tee braker_log  #NO for no rnaseq  

# -------------------- run Busco  ---------------------------- #
if [[ $RNAseq = "YES" ]]
then
    ../00_scripts/07_busco_after_braker.sh $busco_lineage YES 2>&1 |tee log_busco
else
   ../00_scripts/07_busco_after_braker.sh $busco_lineage 2>&1 |tee log_busco 
fi

# ---------------------reshape Braker output ----------------- #
if [[ $RNAseq = "YES" ]]
then
    ../00_scripts/08_braker_reshaping.sh -s  $haplotype -r YES 2>&1 |tee reshape_log 
else
   ../00_scripts/08_braker_reshaping.sh -s $haplotype -r NO 2>&1 |tee reshape_log 
fi
if [ $? -eq 0 ]; then
    echo -e "------\nbraker output successfully processed\n------"
else
    echo ERROR - verfiy braker outputs!   
    exit 1
fi
