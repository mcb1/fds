#!/bin/bash

#--------------------------------------------------------
#  usage
#--------------------------------------------------------

function usage {
  echo "Usage: qfds.sh [options] casename.fds"
  echo ""
  echo "qfds.sh runs FDS using an executable specified by the -e option or from"
  echo "the respository if -e is not specified.  A parallel version of FDS is "
  echo "invoked by usingg -p to specify the number of MPI processes and/or -o to"
  echo "specify the number of OpenMP threads."
  echo ""
  echo "Common options"
  echo "--------------"
  echo " -e exe - full path of FDS used to run case"
  echo " -p p   - number of MPI processes [default: 1] "
  echo " -v     - output generated script to standard output"
  echo "Other options"
  echo "-------------"
  echo " -A     - used by timing scripts"
  echo " -b     - use debug version of FDS"
  echo " -B     - location of background program"
  echo " -c     - strip extension"
  echo " -d dir - specify directory where the case is found [default: .]"
  echo " -E email address - send an email when the job ends or if it aborts"
  echo " -f repository root - name and location of repository where FDS is located"
  echo "          [default: $FDSROOT]"
  echo " -h     - display this message"
  echo " -i     - use installed fds"
if [ "$QFDS_COMPILER" == "" ]; then
  echo " -I inteldist  - specify Intel library location";
else
  echo " -I inteldist  - specify Intel library location [default: $QFDS_COMPILER]";
fi
  echo " -j job - job prefix"
  echo " -l node1+node2+...+noden - specify which nodes to run job on"
  echo " -m m   - reserve m processes per node [default: 1]"
if [ "$QFDS_MPIDIST" == "" ]; then
  echo " -M mpidist  - specify mpi distribution location"
else
  echo " -M mpidist  - specify mpi distribution location [default: $QFDS_MPIDIST]"
fi
  echo " -n n   - number of MPI processes per node [default: 1]"
  echo " -N     - do not use socket or report binding options"
  echo " -o o   - number of OpenMP threads per process [default: 1]"
  echo " -q q   - name of queue. [default: batch]"
  echo "          If queue is terminal then casename.fds is run in the foreground"
  echo " -r     - report bindings"
  echo " -s     - stop job"
  echo " -t     - used for timing studies, run a job alone on a node"
  echo " -u     - use development version of FDS"
  echo " -v     - output generated script to standard output"
  echo " -w time - walltime, where time is hh:mm for PBS and dd-hh:mm:ss for SLURM. "
  echo "          [default: $walltime]"
  echo ""
  exit
}

#--------------------------------------------------------
#  IS_DIR_IN_LDPATH
#--------------------------------------------------------

IS_DIR_IN_LDPATH(){
  dir=$1
  case ":$LD_LIBRARY_PATH:" in
    *:"$dir":*)
      echo 1
      ;;
    *)
      echo 0
      ;;
  esac
}

#--------------------------------------------------------
#  GETABSDIR
#--------------------------------------------------------

GETABSDIR(){
  local curdir=`pwd`
  local filepath=$1
  local filedir=$(dirname $filepath)
  if [ -e $filedir ]; then
    cd $filedir
    filedir=`pwd`
  fi
  echo $filedir
  cd $curdir
}

#--------------------------------------------------------
#  GETFILENAME
#--------------------------------------------------------

GETFILENAME(){
  local filepath=$1
  local filename=$(filename $filepath)
  echo $filaname
}

QFDS_COMPILER=$IFORT_COMPILER_LIB
QFDS_MPIDIST=$MPIDIST
FDSROOT=~/FDS-SMV
if [ "$FIREMODELS" != "" ] ; then
  FDSROOT=$FIREMODELS
fi
if [ "$RESOURCE_MANAGER" == "SLURM" ] ; then
  walltime=99-99:99:99
else
  walltime=999:0:0
fi

if [ $# -lt 1 ]
then
  usage
  exit
fi

# default parameter settings

ncores=8
if [ "`uname`" != "Darwin" ]; then
  ncores=`grep processor /proc/cpuinfo | wc -l`
fi
MPIRUN=
ABORTRUN=n
IB=
DB=
JOBPREFIX=
OUT2ERROR=
if [ "$FDSNETWORK" == "infiniband" ] ; then
  IB=ib
fi
EMAIL=

# --------------------------- parse options --------------------

# default parameter settings

queue=batch
stopjob=0

nmpi_processes=1
nmpi_processes_per_node=-1
max_processes_per_node=1
nopenmp_threads=1
use_installed=0
use_debug=0
use_devel=0
dir=.
benchmark=no
showinput=0
use_repository=1
strip_extension=0
REPORT_BINDINGS="--report-bindings"
nodelist=
erroptionfile=
nosocket=

if [ "$BACKGROUND" == "" ]; then
   BACKGROUND=background
fi
if [ "$BACKGROUND_DELAY" == "" ]; then
   BACKGROUND_DELAY=10
fi
if [ "$BACKGROUND_LOAD" == "" ]; then
   BACKGROUND_LOAD=75
fi

# read in parameters from command line

while getopts 'AbB:cd:e:E:f:hiI:j:l:m:M:Nn:o:p:q:rstuw:v' OPTION
do
case $OPTION  in
  A)
   DUMMY=1
   ;;
  b)
   use_debug=1
   ;;
  B)
   BACKGROUND="$OPTARG"
   ;;
  c)
   strip_extension=1
   ;;
  d)
   dir="$OPTARG"
   ;;
  e)
   fdsexe="$OPTARG"
   use_repository=0
   ;;
  E)
   EMAIL="$OPTARG"
   ;;
  f)
   FDSROOT="$OPTARG"
   ;;
  h)
   usage
   ;;
  i)
   use_installed=1
   use_repository=0
   ;;
  I)
   QFDS_COMPILER="$OPTARG"
   ;;
  j)
   JOBPREFIX="$OPTARG"
   ;;
  l)
   nodelist="$OPTARG"
   ;;
  m)
   max_processes_per_node="$OPTARG"
   ;;
  M)
   QFDS_MPIDIST="$OPTARG"
   ;;
  N)
   nosocket="1"
   ;;
  n)
   nmpi_processes_per_node="$OPTARG"
   ;;
  o)
   nopenmp_threads="$OPTARG"
   ;;
  p)
   nmpi_processes="$OPTARG"
   ;;
  q)
   queue="$OPTARG"
   ;;
  r)
   REPORT_BINDINGS="--report-bindings"
   ;;
  s)
   stopjob=1
   ;;
  t)
   benchmark="yes"
   ;;
  u)
   use_devel=1
   ;;
  v)
   showinput=1
   ;;
  w)
   walltime="$OPTARG"
   ;;
esac
done
shift $(($OPTIND-1))

# ^^^^^^^^^^^^^^^^^^^^^^^^parse options^^^^^^^^^^^^^^^^^^^^^^^^^

if [ "$nodelist" != "" ] ; then
  nodelist="-l nodes=$nodelist"
fi
if [ "$use_debug" == "1" ] ; then
  DB=_db
fi
if [ "$use_devel" == "1" ] ; then
  DB=_dv
fi

# define executables if the repository is used

# use fds from repository (-e was not specified)
if [ $use_repository -eq 1 ]; then
  fdsexe=$FDSROOT/fds/Build/mpi_intel_linux_64$IB$DB/fds_mpi_intel_linux_64$IB$DB
fi

if [ $use_installed -eq 1 ]; then
  notfound=`echo | fds |& tail -1 | grep "not found" | wc -l`
  if [ $notfound -eq 1 ]; then
    echo "fds is not installed. Run aborted."
    ABORTRUN=y
    fdsexe=
  else
    fdspath=`which fds`
    fdsdir=$(dirname "${fdspath}")
    curdir=`pwd`
    cd $fdsdir
    fdsexe=`pwd`/fds
    cd $curdir
  fi
fi

if [[ "$QFDS_COMPILER" != "" && ! -d $QFDS_COMPILER ]]; then
   echo "The Intel compiler shared library directory $QFDS_COMPILER"
   echo "does not exist. Run aborted"
   ABORTRUN=y
fi
if [[ "$QFDS_MPIDIST" != "" && ! -d $QFDS_MPIDIST ]]; then
  echo "The OpenMPI directory $QFDS_MPIDIST does not exist. Run aborted."
  ABORTRUN=y
fi

#define input file

in=$1
infile=${in%.*}

# if there is more than 1 process then use the mpirun command

TITLE="$infile"

# define number of nodes

if test $nmpi_processes_per_node -gt $ncores ; then
  nmpi_processes_per_node=$ncores
fi

if test $nmpi_processes_per_node = -1 ; then
  if test $nmpi_processes -gt 1 ; then
    nmpi_processes_per_node=2
  else
    nmpi_processes_per_node=1
  fi
fi

let "nodes=($nmpi_processes-1)/$nmpi_processes_per_node+1"
if test $nodes -lt 1 ; then
  nodes=1
fi

# define processes per node

let "ppn=($nopenmp_threads)*($nmpi_processes_per_node)"
if test $ppn -le $max_processes_per_node ; then
  ppn=$max_processes_per_node
fi

# in benchmark mode run a case "alone" on one node

if [ "$benchmark" == "yes" ]; then
  let "nodes=($nmpi_processes-1)/$ncores+1"
  ppn=$ncores
  nmpi_processes_per_node=$ncores
fi

# default: Use mpirun option to bind processes to socket (for MPI).
# Or, bind processs to and map processes by socket if
# OpenMP is being used (number of OpenMP threads > 1).

if test $nopenmp_threads -gt 1 ; then
 SOCKET_OPTION="--bind-to core --map-by socket:PE=$nopenmp_threads"
else
 SOCKET_OPTION="--bind-to socket --map-by socket"
fi

if [ "$benchmark" == "yes" ]; then
 SOCKET_OPTION="--bind-to core --map-by node:PE=$nopenmp_threads"
fi

# the "none" queue does not use the queing system, so blank out SOCKET_OPTIONS and REPORT_BINDINGS

if [ "$queue" == "none" ]; then
 SOCKET_OPTION=
 REPORT_BINDINGS=
fi
if [ "$nosocket" == "1" ]; then
 SOCKET_OPTION=
 REPORT_BINDINGS=
fi

# use mpirun if there is more than 1 process

  MPIRUN="$QFDS_MPIDIST/bin/mpirun $REPORT_BINDINGS $SOCKET_OPTION -np $nmpi_processes"
  TITLE="$infile(MPI)"
  case $FDSNETWORK in
    "infiniband") TITLE="$infile(MPI_IB)"
  esac

cd $dir
fulldir=`pwd`

# define files

outerr=$fulldir/$infile.err
outlog=$fulldir/$infile.log
stopfile=$fulldir/$infile.stop
in_full_file=$fulldir/$in

# make sure various files exist before running case

if ! [ -e $in_full_file ]; then
  if [ "$showinput" == "0" ] ; then
    echo "The input file, $in_full_file, does not exist. Run aborted."
    ABORTRUN=y
  fi
fi
if [ "$strip_extension" == "1" ] ; then
  in=$infile
fi
if [ $STOPFDS ]; then
 echo "stopping case: $in"
 touch $stopfile
 exit
fi
if [ "$fdsexe" != "" ]; then
  if ! [ -e "$fdsexe" ]; then
    if [ "$showinput" == "0" ] ; then
      echo "The program, $fdsexe, does not exist. Run aborted."
      ABORTRUN=y
    fi
  fi
fi
if [ -e $outlog ]; then
  echo "Removing log file: $outlog"
  rm $outlog
fi
if [ "$ABORTRUN" == "y" ] ; then
  if [ "$showinput" == "0" ] ; then
    exit
  fi
fi
fdsdir=`GETABSDIR $fdsexe`
fdsname=`GETFILENAME $fdsexe`
is_fdsinstalled=0
if [[ "$FDSBINDIR" != "" && "$FDSBINDIR/fds" == "$fdsdir/$fdsname" ]]; then
  is_fdsinstalled=1
fi
if [ "$STOPFDSMAXITER" != "" ]; then
  echo "creating delayed stop file: $infile"
  echo $STOPFDSMAXITER > $stopfile
fi
if [ "$stopjob" == "1" ]; then
 echo "stopping case: $in"
 touch $stopfile
 exit
fi
if [ "$STOPFDSMAXITER" == "" ]; then
  if [ -e $stopfile ]; then
    rm $stopfile
  fi
fi

QSUB="qsub -q $queue $nodelist"

if [ "$queue" == "terminal" ] ; then
  QSUB=
  MPIRUN=
fi

# use the queue none and the program background on systems
# without a queing system

if [ "$queue" == "none" ]; then
  OUT2ERROR=" 2> $outerr"
  notfound=`$BACKGROUND -help 2>&1 | tail -1 | grep "not found" | wc -l`
  if [ "$showinput" == "0" ]; then
    if [ "$notfound" == "1" ];  then
      echo "The program $BACKGROUND was not found."
      echo "Install FDS which has the background utility."
      echo "Run aborted"
      exit
    fi
  fi
  MPIRUN=
  QSUB="$BACKGROUND -u $BACKGROUND_LOAD -d $BACKGROUND_DELAY "
fi

# setup for systems using the queuing system SLURM

if [ "$RESOURCE_MANAGER" == "SLURM" ] ; then
  MPIRUN="srun"
  QSUB="sbatch -p $queue --ignore-pbs"
fi

# Set walltime parameter only if walltime is specified as input argument
walltimestring_pbs=
walltimestring_slurm=
if [ "$walltime" != "" ] ; then
  walltimestring_pbs="-l walltime=$walltime"
  walltimestring_slurm="-t $walltime"
fi

# create a random script file for submitting jobs
scriptfile=`mktemp /tmp/script.$$.XXXXXX`

cat << EOF > $scriptfile
#!/bin/bash
EOF

if [ "$queue" != "none" ] ; then
if [ "$RESOURCE_MANAGER" == "SLURM" ] ; then
cat << EOF >> $scriptfile
#SBATCH -J $JOBPREFIX$infile
#SBATCH $walltimestring_slurm
#SBATCH --mem-per-cpu=3000
#SBATCH -e $outerr
#SBATCH -o $outlog
#SBATCH -p $queue
#SBATCH -n $nmpi_processes
#SBATCH --nodes=$nodes
#SBATCH --cpus-per-task=$nopenmp_threads
EOF
else
cat << EOF >> $scriptfile
#PBS -N $JOBPREFIX$TITLE
#PBS -e $outerr
#PBS -o $outlog
#PBS -l nodes=$nodes:ppn=$ppn
EOF
if [ "$EMAIL" != "" ]; then
cat << EOF >> $scriptfile
#PBS -M $EMAIL
#PBS -m ae
EOF
fi
if [ "$walltimestring_pbs" != "" ] ; then
cat << EOF >> $scriptfile
#PBS $walltimestring_pbs
EOF
fi
fi
fi

cat << EOF >> $scriptfile
export OMP_NUM_THREADS=$nopenmp_threads

cd $fulldir
echo
echo \`date\`
echo "Input file: $in"
echo " Directory: \`pwd\`"
echo "      Host: \`hostname\`"
if [ "$QFDS_MPIDIST" != "" ]; then
  echo "   OpenMPI: $QFDS_MPIDIST"
if
if [ "$QFDS_COMPILER" != "" ]; then
  echo "  Compiler:$QFDS_COMPILER"
fi
$MPIRUN $fdsexe $in $OUT2ERROR
EOF

# if requested, output script file to screen

if [ "$showinput" == "1" ] ; then
  cat $scriptfile
  exit
fi

# output info to screen

if [ "$queue" != "none" ] ; then
  echo "         Input file:$in"
  echo "         Executable:$fdsexe"
  echo "              Queue:$queue"
  echo "              Nodes:$nodes"
  echo "          Processes:$nmpi_processes"
  echo " Processes per node:$nmpi_processes_per_node"
  if test $nopenmp_threads -gt 1 ; then
    echo "Threads per process:$nopenmp_threads"
  fi
  if [ "$QFDS_MPIDIST" != "" ]; then
    echo "            OpenMPI: $QFDS_MPIDIST"
  fi
  if [ "$QFDS_COMPILER" != "" ]; then
    echo "           Compiler:$QFDS_COMPILER"
  fi
fi

# run script

chmod +x $scriptfile
$QSUB $scriptfile
if [ "$queue" != "none" ] ; then
  rm $scriptfile
fi

